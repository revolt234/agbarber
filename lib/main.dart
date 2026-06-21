import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
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
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
        scaffoldBackgroundColor: const Color(0xFFF4F6F5), // Un bianco leggermente sporco che sta benissimo col verde
        useMaterial3: true,
      ),

      // TEMA SCURO: Sfondo scuro total green, elementi in oro ed eleganza al massimo
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: agVerde,
          primary: agOro, // In dark mode usiamo l'oro come colore principale per farlo risaltare
          secondary: agVerde,
          surface: const Color(0xFF0F2E25), // Variante ancora più scura del verde per le card/sfondi
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF101715), // Sfondo quasi nero con una punta di verde
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
        // Se l'utente non è loggato, mostra lo schermo di Login
        if (!snapshot.hasData) {
          return const LoginScreen();
        }

        // Se l'utente è loggato, leggiamo il suo ruolo da Firestore in tempo reale
        final User user = snapshot.data!;

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, userSnapshot) {
            // Finché i dati caricano, mostra un indicatore di caricamento
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }

            // Se il documento esiste, controlliamo il ruolo
            if (userSnapshot.hasData && userSnapshot.data!.exists) {
              final userData = userSnapshot.data!.data() as Map<String, dynamic>;
              final String ruolo = userData['role'] ?? 'cliente';

              if (ruolo == 'barbiere') {
                return const BarbiereHomePage(); // Se è il capo, vede l'interfaccia barbiere
              }
            }

            // Di base, o se non trova il documento, rimanda alla Home del Cliente
            return const ClienteHomePage();
          },
        );
      },
    );
  }
}

/// -----------------------------------------------------------------------
/// INTERFACCIA CLIENTE
/// -----------------------------------------------------------------------
class ClienteHomePage extends StatelessWidget {
  const ClienteHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Inserisce il logo in alto a sinistra
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

        // Pulsante utente in alto a destra per il profilo
        actions: [
          IconButton(
            icon: const Icon(
              Icons.account_circle,
              size: 28,
              color: Color(0xFFE2B13C),
            ),
            onPressed: () {
              // Naviga verso la schermata del profilo
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      // Sostituito il Center precedente con la schermata reale di prenotazione servizi
      body: const PrenotazioneServiziScreen(),
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
        // L'app bar del barbiere è in Oro per distinguerla nettamente a colpo d'occhio
        backgroundColor: const Color(0xFFE2B13C),
        centerTitle: true,
        actions: [
          // Aggiungiamo il logout rapido anche per l'admin in alto a destra
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

            // PULSANTE: Gestione Servizi (Listino)
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

// PULSANTE: Gestione Operatori
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

// PULSANTE: Gestione Orari
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

// PULSANTE: Gestione Eccezioni Calendario (Ferie/Chiusure straordinarie)
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

// PULSANTE: Gestione Turni Singoli Operatori
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

            // SEGNAPOSTO: Gestione Appuntamenti (per i futuri step)
            Card(
              elevation: 2,
              color: Colors.grey.shade100,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: const ListTile(
                contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                leading: CircleAvatar(
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.calendar_today, color: Colors.white),
                ),
                title: Text(
                  'Agendamento & Prenotazioni',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.grey),
                ),
                subtitle: Text('Prossimamente: Visualizza e gestisci gli appuntamenti ricevuti'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}