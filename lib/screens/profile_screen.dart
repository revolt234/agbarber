import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Email di reset della password inviata! Controlla la tua posta.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Funzione per eliminare l'account definitivamente
  Future<void> _eliminaAccount() async {
    // Mostriamo prima un dialogo di conferma per sicurezza
    bool confermato = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Elimina Account'),
        content: const Text('Sei sicuro? Questa azione è irreversibile e cancellerà tutti i tuoi dati.'),
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
      Navigator.pop(context); // Torna indietro (l'AuthGate farà il resto)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Account eliminato con successo.')),
      );
    } on FirebaseAuthException catch (e) {
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
            } finally {
        setState(() => _isLoading = false);
        }
        }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestione Account', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF164638),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Card con info Utente
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Color(0xFFE2B13C),
                    child: Icon(Icons.person, size: 35, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Account Cliente',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        Text(
                          _user?.email ?? 'Nessuna email',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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

          const Text('Opzioni Sicurezza', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
          const Divider(),

          // Modifica Password
          ListTile(
            leading: const Icon(Icons.lock_reset, color: Color(0xFF164638)),
            title: const Text('Modifica Password'),
            subtitle: const Text('Ricevi un link via email per reimpostare la password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _cambiaPassword,
          ),

          // Logout
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.orange),
            title: const Text('Disconnetti'),
            subtitle: const Text('Esci dal tuo account corrente'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              FirebaseAuth.instance.signOut();
              Navigator.pop(context); // Chiude la pagina del profilo
            },
          ),

          const SizedBox(height: 32),
          const Text('Zona Pericolo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red)),
          const Divider(color: Colors.red),

          // Elimina Account
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Elimina Account', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            subtitle: const Text('Cancella permanentemente il tuo profilo da AG Barber'),
            onTap: _eliminaAccount,
          ),
        ],
      ),
    );
  }
}