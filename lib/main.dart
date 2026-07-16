import 'dart:async';
import 'dart:io'; // AGGIUNTO: Necessario per verificare la piattaforma (Platform.isIOS)
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Richiesto per la gestione dell'orientamento
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // AGGIUNTO: Pacchetto ufficiale per i messaggi push
import 'screens/visualizzazione_prenotazioni_screen.dart';
import 'firebase_options.dart';
import 'screens/prenotazione_servizi_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/storico_prenotazioni_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/gestione_servizi_screen.dart';
import 'screens/gestione_operatori_screen.dart';
import 'screens/gestione_orari_screen.dart';
import 'screens/gestione_calendario_screen.dart';
import 'screens/gestione_turni_operatori_screen.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'services/notification_service.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';
import 'screens/gestione_clienti_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // AGGIUNTO: Necessario per resettare il badge nativo su iOS

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT', null);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Accensione del sistema notifiche all'avvio (Inizializzazione Unica e Centralizzata)
  await NotificationService().init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // --- CONTROLLO ORIENTAMENTO DINAMICO (SOLO TABLET IN LANDSCAPE) ---
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isNotEmpty) {
      final data = MediaQueryData.fromView(views.first);
      bool isTablet = data.size.shortestSide >= 600;

      if (isTablet) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    }

    const Color agVerde = Color(0xFF164638);
    const Color agOro = Color(0xFFE2B13C);

    return MaterialApp(
      title: 'AG Barber',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('it', 'IT'),
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: agVerde,
          primary: agVerde,
          secondary: agOro,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6F5),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: agVerde,
          primary: agOro,
          secondary: agVerde,
          surface: const Color(0xFF0F2E25),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF101715),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  // Riferimento per cancellare la sottoscrizione allo stream quando il widget viene distrutto
  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _currentUid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controllaAggiornamentoObbligatorio();
      _pulisciNotificheEBadge(); // MODIFICATO: Richiama la pulizia del badge all'avvio
    });

    // Inizializza l'ascolto globale del cambio token (onTokenRefresh)
    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      if (_currentUid != null) {
        await _salvaTokenSuFirestore(_currentUid!, newToken);
      }
    });
  }

  @override
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    super.dispose();
  }

  // MODIFICATO: Pulisce le notifiche nel centro notifiche e resetta a zero il badge (pallino rosso) dell'icona su iOS
  Future<void> _pulisciNotificheEBadge() async {
    try {
      if (Platform.isIOS) {
        final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
        await flutterLocalNotificationsPlugin
            .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
            ?.cancelAll(); // Corretto da cancelAllNotifications() a cancelAll()
      }
    } catch (e) {
      debugPrint("Errore durante l'azzeramento delle notifiche e badge su iOS: $e");
    }
  }

  // Funzione isolata per scrivere i dati in modo pulito ed evitare duplicazioni di codice
  Future<void> _salvaTokenSuFirestore(String uid, String token) async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fcmToken': token,
        'pushToken': token,
        'timestamp': FieldValue.serverTimestamp(),
      });
      debugPrint("FCM Token sincronizzato con successo su Firestore.");
    } catch (e) {
      debugPrint("Errore durante il salvataggio del token su Firestore: $e");
    }
  }

  // Implementata la logica di Bounded Retry (max 5 secondi) per evitare la Race Condition nativa su iOS
  Future<void> _configuraNotifichePushRemote(String uid) async {
    _currentUid = uid; // Memorizza l'uid corrente per l'onTokenRefresh
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;

      NotificationSettings settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        if (Platform.isIOS) {
          // Soluzione dell'articolo: 10 tentativi da 500ms ciascuno per attendere l'APNs nativo
          String? apnsToken;
          for (int i = 0; i < 10; i++) {
            apnsToken = await messaging.getAPNSToken();
            if (apnsToken != null) break;
            await Future.delayed(const Duration(milliseconds: 500));
          }

          if (apnsToken == null) {
            debugPrint("APNs fallito o non ancora pronto dopo 5 secondi di tentativi.");
            return; // Interrompe per evitare di richiedere un FCM token nullo
          }
          debugPrint("APNs Token validato con successo: $apnsToken");
        }

        // Generazione del token definitivo sicuro
        String? fcmToken = await messaging.getToken();

        if (fcmToken != null && fcmToken.isNotEmpty) {
          await _salvaTokenSuFirestore(uid, fcmToken);
        }
      }
    } catch (e) {
      debugPrint("Errore registrazione token push: $e");
    }
  }

  Future<void> _controllaAggiornamentoObbligatorio() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;

      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: kDebugMode ? const Duration(minutes: 5) : const Duration(hours: 4),
      ));

      await remoteConfig.fetchAndActivate();

      String versioneMinima = remoteConfig.getString('version_minima_richiesta');
      if (versioneMinima.isEmpty) return;

      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String versioneAttuale = packageInfo.version;

      if (_deveAggiornare(versioneAttuale, versioneMinima)) {
        _mostraDialogBloccante();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint("Errore Remote Config: $e");
      }
    }
  }

  bool _deveAggiornare(String installata, String minima) {
    try {
      List<int> vInst = installata.split('.').map(int.parse).toList();
      List<int> vMin = minima.split('.').map(int.parse).toList();

      for (int i = 0; i < vMin.length; i++) {
        if (i >= vInst.length) return true;
        if (vInst[i] < vMin[i]) return true;
        if (vInst[i] > vMin[i]) return false;
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  void _mostraDialogBloccante() {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
            title: Text(
              "Aggiornamento Obbligatorio 🚀",
              style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
            ),
            content: Text(
              "Una nuova versione di AG Barber è disponibile nello store ufficiale. "
                  "Per garantire la massima stabilità nella prenotazione degli slot orari, aggiorna l'applicazione prima di procedere.",
              style: TextStyle(color: isDarkMode ? Colors.grey : Colors.black54),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  // Rileva la piattaforma per reindirizzare allo store corretto
                  final String urlString = Platform.isIOS
                      ? "https://apps.apple.com/it/app/ag-barber/id6784350580"
                      : "https://play.google.com/store/apps/details?id=com.LoSco.agbarber.prenotazionibarbiere&hl=it";

                  final url = Uri.parse(urlString);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                },
                child: const Text(
                  "AGGIORNA ORA",
                  style: TextStyle(color: Color(0xFFE2B13C), fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          _currentUid = null;
          return const ClienteHomePage(nomeUtente: "Ospite");
        }

        final User user = snapshot.data!;

        _configuraNotifichePushRemote(user.uid);

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            String nomeEstratto = "Cliente";

            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData = userSnapshot.data!.data() as Map<String, dynamic>;
              final String ruolo = userData['role'] ?? 'cliente';

              nomeEstratto = userData['name'] ?? user.displayName ?? "Cliente";

              if (ruolo == 'barbiere') {
                // MODIFICATO: Per evitare il loop di refresh e il doppio caricamento grafico,
                // aggiorniamo il token in background anziché attendere in modo sincrono con un FutureBuilder.
                user.getIdToken();
                return const BarbiereHomePage();
              }
            }

            return ClienteHomePage(nomeUtente: nomeEstratto);
          },
        );
      },
    );
  }
}

class ClienteHomePage extends StatefulWidget {
  final String nomeUtente;

  const ClienteHomePage({super.key, required this.nomeUtente});

  @override
  State<ClienteHomePage> createState() => _ClienteHomePageState();
}

class _ClienteHomePageState extends State<ClienteHomePage> {
  int _indiceSelezionato = 0;

  late final List<Widget> _pagine = [
    const PrenotazioneServiziScreen(),
    const StoricoPrenotazioniScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    const Color agVerde = Color(0xFF164638);
    const Color agOro = Color(0xFFE2B13C);

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color coloreSfondoAdattivo = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF4F6F5);
    final Color coloreNavAdattiva = isDarkMode ? const Color(0xFF121212) : Colors.white;

    return Scaffold(
      backgroundColor: coloreSfondoAdattivo,
      appBar: _indiceSelezionato == 0
          ? AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Image.asset(
            'assets/A di barber.png',
            fit: BoxFit.contain,
          ),
        ),
        title: const Text(
            'AG BARBER',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white)
        ),
        backgroundColor: agVerde,
        centerTitle: true,
        actions: const [
          SizedBox(width: 48),
        ],
      )
          : null,

      body: IndexedStack(
        index: _indiceSelezionato,
        children: _ppages ?? _pagine,
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _indiceSelezionato,
        onTap: (index) {
          setState(() {
            _indiceSelezionato = index;
          });
        },
        type: BottomNavigationBarType.fixed,
        backgroundColor: coloreNavAdattiva,
        selectedItemColor: agOro,
        unselectedItemColor: isDarkMode ? Colors.grey : Colors.grey.shade600,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.format_list_bulleted),
            label: 'Prenotazioni',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Utente',
          ),
        ],
      ),
    );
  }

  List<Widget>? get _ppages => null;
}

class BarbiereHomePage extends StatelessWidget {
  const BarbiereHomePage({super.key});

  void _mostraConfermaDisconnessione(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text(
            'Disconnetti',
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Sei sicuro di voler uscire dal pannello admin?',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Annulla',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade900),
              onPressed: () async {
                Navigator.pop(context);
                await FirebaseAuth.instance.signOut();
              },
              child: const Text(
                'Esci',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color coloreSfondoAdattivo = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF4F6F5);

    return Scaffold(
      backgroundColor: coloreSfondoAdattivo,
      appBar: AppBar(
        title: const Text(
            'DASHBOARD BARBIERE',
            style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Color(0xFF164638))
        ),
        backgroundColor: const Color(0xFFE2B13C),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF164638)),
            onPressed: () => _mostraConfermaDisconnessione(context),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.content_cut, size: 80, color: Color(0xFF164638)),
                    SizedBox(height: 16),
                    Text(
                      'Benvenuto Barber Admin!',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('Pannello di controllo e gestione del negozio.'),
                  ],
                ),
              ),
              const SizedBox(height: 40),

              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF164638),
                    child: Icon(Icons.design_services, color: Colors.white),
                  ),
                  title: const Text(
                    'Gestione Listino Servizi',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  subtitle: const Text('Aggiungi, modifica o elimina i servizi offerti e i relativi prezzi'),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFFE2B13C), size: 30),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const GestioneServiziScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF164638),
                    child: Icon(Icons.people, color: Colors.white),
                  ),
                  title: const Text(
                    'Gestione Staff / Operatori',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  subtitle: const Text('Aggiungi o rimuovi i dipendenti del salone (es. Gerardo, Jessica)'),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFFE2B13C), size: 30),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const GestioneOperatoriScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF164638),
                    child: Icon(Icons.calendar_month, color: Colors.white),
                  ),
                  title: const Text(
                    'Orari di Apertura',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  subtitle: const Text('Imposta i giorni di chiusura e le fasce orarie lavorative'),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFFE2B13C), size: 30),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const GestioneOrariScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF164638),
                    child: Icon(Icons.edit_calendar, color: Colors.white),
                  ),
                  title: const Text(
                    'Chiusure/Aperture Speciali & Ferie',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  subtitle: const Text('Blocca giornate specifiche sul calendario (es. Ferie d\'Agosto, festività)'),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFFE2B13C), size: 30),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const GestioneCalendarioScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF164638),
                    child: Icon(Icons.person_search, color: Colors.white),
                  ),
                  title: const Text(
                    'Orari e Turni Staff',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  subtitle: const Text('Gestisci assenze o mezze giornate lavorative di ogni dipendente'),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFFE2B13C), size: 30),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const GestioneTurniOperatoriScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF164638),
                    child: Icon(Icons.calendar_today, color: Colors.white),
                  ),
                  title: const Text(
                    'Agendamento & Prenotazioni',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  subtitle: const Text('Visualizza, filtra e controlla gli appuntamenti ricevuti in tempo reale'),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFFE2B13C), size: 30),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const VisualizzazionePrenotazioniScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF164638),
                    child: Icon(Icons.assignment_ind, color: Colors.white),
                  ),
                  title: const Text(
                    'Anagrafica & Gestione Clienti',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  subtitle: const Text('Visualizza l\'elenco alfabetico, cerca, elimina o blocca l\'accesso alle email'),
                  trailing: const Icon(Icons.chevron_right, color: Color(0xFFE2B13C), size: 30),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const GestioneClientiScreen()),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}