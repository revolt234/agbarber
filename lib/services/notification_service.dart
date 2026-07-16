import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // Aggiunto per permettere l'uso dell'oggetto Color
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // Definizione del canale nativo ad alta priorità per Android in primo piano (foreground)
  static const AndroidNotificationChannel _foregroundAndroidChannel = AndroidNotificationChannel(
    'agbarber_foreground_notif',
    'Notifiche in tempo reale AG Barber',
    description: 'Canale usato per far comparire le notifiche quando l\'app è aperta.',
    importance: Importance.max,
    playSound: true,
  );

  /// Inizializza il sistema di notifiche e i fusi orari
  Future<void> init() async {
    tz.initializeTimeZones();

    // 1. Richiesta dei permessi e opzioni nativi iOS/Android per il foreground
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Configurazione per Android
    // Punta direttamente al file ic_stat_name dentro la cartella drawable generica
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('ic_stat_name');

    // Configurazione per iOS
    const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notificationsPlugin.initialize(settings: initializationSettings);

    // Creazione del canale fisico ad alta priorità su Android
    if (Platform.isAndroid) {
      await _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_foregroundAndroidChannel);
    }

    // Avvio del listener per intercettare i push in tempo reale ad app aperta
    _setupForegroundListener();
  }

  /// Listener globale per le notifiche ricevute mentre l'app è in uso
  void _setupForegroundListener() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (kDebugMode) {
        print("Notifica ricevuta in primo piano: ${notification?.title} - ${notification?.body}");
      }

      // Solo per Android generiamo il banner popup locale a schermo aperto
      if (notification != null && Platform.isAndroid) {
        _notificationsPlugin.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _foregroundAndroidChannel.id,
              _foregroundAndroidChannel.name,
              channelDescription: _foregroundAndroidChannel.description,
              importance: Importance.max,
              priority: Priority.high,
              icon: android?.smallIcon ?? 'ic_stat_name',
            ),
          ),
        );
      }
    });
  }

  /// Pianifica una notifica locale 15 minuti prima dell'appuntamento
  Future<void> pianificaNotificaAppuntamento({
    required int idNotifica, // Un ID univoco (puoi usare l'hashcode dell'ID documento di Firebase)
    required String dataStr, // es: "2026-06-21"
    required String slotStr, // es: "15:30"
    required String servizi, // es: "Taglio, Barba"
  }) async {
    try {
      // 1. Convertiamo le stringhe in un oggetto DateTime reale
      final DateTime orarioAppuntamento = DateFormat("yyyy-MM-dd HH:mm").parse("$dataStr $slotStr");

      // 2. Sottraiamo i 15 minuti richiesti
      final DateTime orarioNotifica = orarioAppuntamento.subtract(const Duration(minutes: 15));

      // Se l'orario della notifica è già passato (es. prenotazione last-minute), non pianificarla
      if (orarioNotifica.isBefore(DateTime.now())) return;

      // 3. Convertiamo il DateTime nel formato TZDateTime richiesto dalla libreria
      final tz.TZDateTime tzOrarioNotifica = tz.TZDateTime.from(orarioNotifica, tz.local);

      // 4. Definiamo i dettagli grafici e sonori della notifica
      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'ag_barber_reminders', // ID del canale interno
        'Promemoria Appuntamenti', // Nome visibile nelle impostazioni del telefono
        channelDescription: 'Notifiche in tutto il salone prima del taglio di capelli',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        color: Color(0xFF164638), // MODIFICATO: Colore verde del brand per il cerchietto nella tendina
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      // 5. Programmiamo la sveglia (SINTASSI V22 COMPLETA E PULITA)
      await _notificationsPlugin.zonedSchedule(
        id: idNotifica,
        title: '💈 Promemoria AG Barber!',
        body: 'Il tuo appuntamento per "$servizi" inizierà tra 15 minuti!',
        scheduledDate: tzOrarioNotifica,
        notificationDetails: platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        // RIMOSSO IL PARAMETRO DEPRECATO 'uiLocalNotificationDateInterpretation'
      );
    } catch (e) {
      if (kDebugMode) {
        print("Errore nella pianificazione della notifica: $e");
      }
    }
  }

  /// Pianifica una notifica locale con preavviso flessibile (30 min, 1h, 2h) prima dell'appuntamento
  Future<void> pianificaNotificaFlessibile({
    required int idNotifica,
    required String dataStr,
    required String slotStr,
    required String servizi,
    required int minutiPreavviso,
  }) async {
    try {
      final DateTime orarioAppuntamento = DateFormat("yyyy-MM-dd HH:mm").parse("$dataStr $slotStr");

      // Sottrae il tempo scelto dinamicamente dal pannello (30, 60 o 120 minuti)
      final DateTime orarioNotifica = orarioAppuntamento.subtract(Duration(minutes: minutiPreavviso));

      if (orarioNotifica.isBefore(DateTime.now())) return;

      final tz.TZDateTime tzOrarioNotifica = tz.TZDateTime.from(orarioNotifica, tz.local);

      const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
        'ag_barber_reminders',
        'Promemoria Appuntamenti',
        channelDescription: 'Notifiche inviate prima del taglio di capelli',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        color: Color(0xFF164638),
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _notificationsPlugin.zonedSchedule(
        id: idNotifica,
        title: '💈 Promemoria AG Barber!',
        body: 'Il tuo appuntamento per "$servizi" inizierà a breve!',
        scheduledDate: tzOrarioNotifica,
        notificationDetails: platformDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      if (kDebugMode) {
        print("Errore nella pianificazione flessibile della notifica: $e");
      }
    }
  }

  /// Cancella una notifica (utile se l'appuntamento viene eliminato o disdetto)
  Future<void> cancellaNotifica(int idNotifica) async {
    // CORRETTO: Aggiunto 'id:' richiesto esplicitamente dalla v22+
    await _notificationsPlugin.cancel(id: idNotifica);
  }
}