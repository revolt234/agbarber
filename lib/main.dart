import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/visualizzazione_prenotazioni_screen.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/prenotazione_servizi_screen.dart';
import 'screens/profile_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/gestione_servizi_screen.dart';
import 'screens/gestione_operatori_screen.dart';
import 'screens/gestione_orari_screen.dart';
import 'screens/gestione_calendario_screen.dart';
import 'screens/gestione_turni_operatori_screen.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('it_IT', null);
  // Questo comando adesso leggerà da solo le opzioni WEB, ANDROID e IOS in modo nativo e sicuro
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Definizione dei colori ufficiali del logo AG Barber
    const Color agVerde = Color(0xFF164638);
    const Color agOro = Color(0xFFE2B13C);

    return MaterialApp(
      title: 'AG Barber',
      debugShowCheckedModeBanner: false,

      // TEMA CHIARO: Sfondo chiaro, ma dettagli, scritte importanti e pulsanti in Verde e Oro
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

      // TEMA SCURO: Sfondo scuro total green, elementi in oro ed eleganza al massimo
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

/// -----------------------------------------------------------------------
/// SCHERMATA DI CONTROLLO ACCESSO (AuthGate)
/// -----------------------------------------------------------------------
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        final User user = snapshot.data!;

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            String nomeEstratto = "Cliente"; // Fallback di sicurezza

            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData = userSnapshot.data!.data() as Map<String, dynamic>;
              final String ruolo = userData['role'] ?? 'cliente';

              // Recupera il nome inserito in fase di registrazione su Firestore
              nomeEstratto = userData['name'] ?? user.displayName ?? "Cliente";

              if (ruolo == 'barbiere') {
                return const BarbiereHomePage();
              }
            }

            // Passa il nome reale alla home del cliente
            return ClienteHomePage(nomeUtente: nomeEstratto);
          },
        );
      },
    );
  }
}

/// -----------------------------------------------------------------------
/// INTERFACCIA CLIENTE (AGGIORNATA)
/// -----------------------------------------------------------------------
class ClienteHomePage extends StatelessWidget {
  final String nomeUtente; // <--- Riceve il nome reale da AuthGate

  const ClienteHomePage({super.key, required this.nomeUtente});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
        backgroundColor: const Color(0xFF164638),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.account_circle,
              size: 28,
              color: Color(0xFFE2B13C),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Ora l'app passa il nome direttamente alla schermata interna senza ri-estrarre la mail
      body: PrenotazioneServiziScreen(),
    );
  }
}

/// -----------------------------------------------------------------------
/// INTERFACCIA BARBIERE (ADMIN)
/// -----------------------------------------------------------------------
class BarbiereHomePage extends StatelessWidget {
  const BarbiereHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: SingleChildScrollView(
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
                  'Chiusure Speciali & Ferie',
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
          ],
        ),
      ),
    );
  }
}