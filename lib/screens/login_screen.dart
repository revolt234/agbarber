import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  // Creiamo i FocusNode dedicati per gestire i singoli focus
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();

  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _inviaForm() async {
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        // 1. Logica di Accesso (Login)
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        // 2. Logica di Registrazione
        UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );

        // Salva il ruolo 'cliente' su Firestore usando l'ID univoco dell'utente (UID)
        if (userCredential.user != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid)
              .set({
            'email': _emailController.text.trim(),
            'role': 'cliente', // Di base nascono tutti come clienti
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
    } // <--- Parentesi graffa corretta qui
  }

  @override
  Widget build(BuildContext context) {
    // Questo trucco rileva l'altezza della tastiera di sistema.
    // Se è 0, significa che la tastiera è chiusa (anche tramite tasto BACK).
    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    if (!isKeyboardOpen) {
      // Se la tastiera si è chiusa (in qualsiasi modo), togliamo il focus fantasma
      _emailFocus.unfocus();
      _passwordFocus.unfocus();
    }

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
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

                // Campo Email
                TextField(
                  controller: _emailController,
                  focusNode: _emailFocus, // Assegnato il focus node
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),

                // Campo Password
                TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocus, // Assegnato il focus node
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