import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // Aggiunto per permettere l'uso dell'oggetto Color
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:intl/intl.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  /// Inizializza il sistema di notifiche e i fusi orari
  Future<void> init() async {
    tz.initializeTimeZones();

    // Configurazione per Android
    // MODIFICATO: Sostituito '@mipmap/ic_launcher' con la tua nuova immagine 'img' posizionata in drawable
    // Configurazione per Android
// Punti all'icona ufficiale generata automaticamente a partire dagli assets
    // Configurazione per Android
// Punta direttamente al file img.png dentro la cartella drawable generica
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('ic_stat_name');
/*const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');*/
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
        channelDescription: 'Notifiche inviate 15 minuti prima del taglio di capelli',
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

  /// Cancella una notifica (utile se l'appuntamento viene eliminato o disdetto)
  Future<void> cancellaNotifica(int idNotifica) async {
    // CORRETTO: Aggiunto 'id:' richiesto esplicitamente dalla v22+
    await _notificationsPlugin.cancel(id: idNotifica);
  }
}