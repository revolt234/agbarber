import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // Importato per identificare se siamo su Web

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nomeCognomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  final FocusNode _nomeCognomeFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nomeCognomeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _nomeCognomeFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _inviaForm() async {
    if (!_isLogin && _nomeCognomeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Il campo Nome e Cognome è obbligatorio."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        if (kIsWeb) {
          await FirebaseAuth.instance.setSettings(
            appVerificationDisabledForTesting: false,
          );
        }

        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        if (userCredential.user != null) {
          await userCredential.user!.updateDisplayName(_nomeCognomeController.text.trim());

          await FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid)
              .set({
            'name': _nomeCognomeController.text.trim(),
            'email': _emailController.text.trim(),
            'role': 'cliente',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } on FirebaseAuthException catch (e) {
      String messaggioErrore = "Si è verificato un errore.";
      if (e.code == 'user-not-found') messaggioErrore = "Utente non trovato.";
      if (e.code == 'wrong-password') messaggioErrore = "Password errata.";
      if (e.code == 'email-already-in-use') messaggioErrore = "Email già registrata.";

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(messaggioErrore), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // RIMOSSO IL VECCHIO BLOCCO DI UNFOCUS AUTOMATICO CHE CREAVA IL BUG SU WEB/DESKTOP

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), // Gestisce la chiusura focus quando clicchi sul vuoto
      child: Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  'assets/A di barber.png',
                  width: 120,
                  height: 120,
                ),
                const SizedBox(height: 32),
                Text(
                  _isLogin ? 'Accedi a AG Barber' : 'Crea il tuo Account',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),

                if (!_isLogin) ...[
                  TextField(
                    controller: _nomeCognomeController,
                    focusNode: _nomeCognomeFocus,
                    decoration: const InputDecoration(
                      labelText: 'Nome e Cognome',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                ],

                TextField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 24),

                _isLoading
                    ? const CircularProgressIndicator()
                    : ElevatedButton(
                  onPressed: _inviaForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF164638),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: Text(_isLogin ? 'ACCEDI' : 'REGISTRATI'),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() => _isLogin = !_isLogin),
                  child: Text(
                    _isLogin
                        ? 'Non hai un account? Registrati qui'
                        : 'Hai già un account? Accedi',
                    style: const TextStyle(color: Color(0xFFE2B13C)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}