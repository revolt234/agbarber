import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart'; // Importato per permettere il reindirizzamento al login

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;
  bool _isLoading = false;

  // Funzione per cambiare la password (invia un'email di reset automatica da Firebase)
  Future<void> _cambiaPassword() async {
    if (_user?.email == null) return;

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: _user!.email!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email di reset della password inviata! Controlla la tua posta.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Funzione per eliminare l'account definitivamente
  Future<void> _eliminaAccount() async {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    bool confermato = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        title: Text(
          'Elimina Account',
          style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Sei sicuro? Questa azione è irreversibile e cancellerà tutti i tuoi dati.',
          style: TextStyle(color: isDarkMode ? Colors.grey : Colors.black54),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Elimina Definitivamente'),
          ),
        ],
      ),
    ) ?? false;

    if (!confermato) return;

    setState(() => _isLoading = true);
    try {
      await _user?.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account eliminato con successo.')),
        );

        // CORREZIONE DEFINITIVA: Sradica tutte le vecchie schermate e rimanda all'AuthGate di partenza
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        if (e.code == 'requires-recent-login') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Per sicurezza, effettua nuovamente il login prima di eliminare l\'account.'),
              backgroundColor: Colors.orange,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Errore: ${e.message}'), backgroundColor: Colors.red),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color agVerde = Color(0xFF164638);
    const Color agOro = Color(0xFFE2B13C);

    // MODIFICATO: Rilevazione del tema (Light/Dark) per garantire consistenza estetica
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Colori adattivi per l'interfaccia utente
    final Color coloreSfondoSchermata = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF4F6F5);
    final Color coloreSfondoCard = isDarkMode ? const Color(0xFF1C2824) : Colors.white;
    final Color coloreTestoPrimario = isDarkMode ? Colors.white : Colors.black87;
    final Color coloreTestoSecondario = isDarkMode ? Colors.grey : Colors.black54;

    return Scaffold(
      backgroundColor: coloreSfondoSchermata,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Image.asset(
            'assets/A di barber.png',
            fit: BoxFit.contain,
          ),
        ),
        title: const Text(
          'GESTIONE ACCOUNT',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
        backgroundColor: agVerde,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: agOro))
          : (_user == null
          ? Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.account_circle,
                size: 100,
                color: agOro.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 24),
              Text(
                'Profilo non configurato',
                style: TextStyle(
                  fontSize: 18,
                  color: coloreTestoPrimario,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Accedi o crea un account per gestire il tuo profilo e le tue preferenze.',
                style: TextStyle(color: coloreTestoSecondario, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: agVerde,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(220, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                onPressed: () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                        (route) => false,
                  );
                },
                child: const Text(
                  'ACCEDI / REGISTRATI',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ],
          ),
        ),
      )
          : ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            color: coloreSfondoCard,
            elevation: isDarkMode ? 2 : 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: isDarkMode ? agVerde : Colors.grey.shade300, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: agOro,
                    child: Icon(Icons.person, size: 35, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Account Cliente',
                          style: TextStyle(fontSize: 14, color: coloreTestoSecondario),
                        ),
                        Text(
                          _user.email ?? 'Nessuna email',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: coloreTestoPrimario),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          Text('Opzioni Sicurezza', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: coloreTestoSecondario)),
          const Divider(color: agVerde),

          ListTile(
            leading: const Icon(Icons.lock_reset, color: agOro),
            title: Text('Modifica Password', style: TextStyle(color: coloreTestoPrimario)),
            subtitle: Text('Ricevi un link via email per reimpostare la password', style: TextStyle(color: coloreTestoSecondario)),
            trailing: Icon(Icons.chevron_right, color: coloreTestoSecondario),
            onTap: _cambiaPassword,
          ),

          ListTile(
            leading: const Icon(Icons.logout, color: Colors.orange),
            title: Text('Disconnetti', style: TextStyle(color: coloreTestoPrimario)),
            subtitle: Text('Esci dal tuo account corrente', style: TextStyle(color: coloreTestoSecondario)),
            trailing: Icon(Icons.chevron_right, color: coloreTestoSecondario),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
          ),

          const SizedBox(height: 32),
          const Text('Zona Pericolo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
          const Divider(color: Colors.red),

          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Elimina Account', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            subtitle: Text('Cancella permanentemente il tuo profilo da AG Barber', style: TextStyle(color: coloreTestoSecondario)),
            onTap: _eliminaAccount,
          ),
        ],
      )),
    );
  }
}