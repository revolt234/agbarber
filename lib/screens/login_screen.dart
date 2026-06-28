import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nomeCognomeController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _recuperoEmailController = TextEditingController();

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
    _recuperoEmailController.dispose();
    _nomeCognomeFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  // CORREZIONE UTILITY: Posiziona il cursore alla fine del testo senza selezionarlo
  void _resettaSelezioneTesto(TextEditingController controller) {
    final text = controller.text;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _mostraDialogoRecuperoPassword() {
    _recuperoEmailController.text = _emailController.text.trim();
    _resettaSelezioneTesto(_recuperoEmailController);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Recupero Password',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Inserisci la tua email. Ti invieremo un link sicuro per reimpostare la tua password.',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _recuperoEmailController,
              maxLength: 45, // Limite max 50 caratteri richiesto
              style: const TextStyle(color: Colors.white),
              onTap: () => _resettaSelezioneTesto(_recuperoEmailController), // Protezione dialogo
              decoration: const InputDecoration(
                labelText: 'Email',
                labelStyle: TextStyle(color: Colors.grey),
                counterText: "", // Nasconde il contatore numerico di default per pulizia estetica
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFF164638)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFE2B13C)),
                ),
                prefixIcon: Icon(Icons.email, color: Color(0xFFE2B13C)),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF164638)),
            onPressed: () async {
              final email = _recuperoEmailController.text.trim();
              if (email.isEmpty || !email.contains('@')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Inserisci un'email valida."), backgroundColor: Colors.red),
                );
                return;
              }
              Navigator.pop(context);
              _inviaEmailReset(email);
            },
            child: const Text('Invia Link', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _inviaEmailReset(String email) async {
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email di ripristino inviata! Controlla la tua casella postale.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseException catch (e) {
      String errore = "Impossibile inviare l'email.";
      if (e.code == 'network-request-failed') {
        errore = "Nessuna connessione a Internet. Controlla la tua rete.";
      } else if (e.code == 'user-not-found') {
        errore = "Nessun account associato a questa email.";
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errore), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _inviaForm() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Compila tutti i campi richiesti."), backgroundColor: Colors.red),
      );
      return;
    }

    if (!_isLogin && _nomeCognomeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Il campo Nome e Cognome è obbligatorio."), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        if (kIsWeb) {
          await FirebaseAuth.instance.setSettings(appVerificationDisabledForTesting: false);
        }

        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        if (userCredential.user != null) {
          await userCredential.user!.updateDisplayName(_nomeCognomeController.text.trim());

          await FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid)
              .set({
            'name': _nomeCognomeController.text.trim(),
            'email': email,
            'role': 'cliente',
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } on FirebaseAuthException catch (e) {
      // STAMPA L'ERRORE REALE NELLA CONSOLE DI APPETIZE PER VEDERLO
      debugPrint("Firebase Auth Error Code: ${e.code}");
      debugPrint("Firebase Auth Error Message: ${e.message}");

      String messaggioErrore = "Si è verificato un errore: ${e.message}"; // Mostra l'errore reale a schermo

      if (e.code == 'network-request-failed') {
        messaggioErrore = "Nessuna connessione a Internet. Controlla la tua rete e riprova.";
      } else if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
        messaggioErrore = "Non esiste un account registrato con questa email o la password è errata.";
      } else if (e.code == 'wrong-password') {
        messaggioErrore = "Password errata. Riprova.";
      } else if (e.code == 'email-already-in-use') {
        messaggioErrore = "Questa email è già registrata con un altro account.";
      } else if (e.code == 'invalid-email') {
        messaggioErrore = "Il formato dell'email inserita non è valido.";
      } else if (e.code == 'weak-password') {
        messaggioErrore = "La password inserita è troppo debole (minimo 6 caratteri).";
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(messaggioErrore), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      String erroreGenerico = "Si è verificato un errore di rete.";
      if (e is SocketException) {
        erroreGenerico = "Internet non disponibile. Verifica la tua connessione.";
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(erroreGenerico), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
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
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 24),

                if (!_isLogin) ...[
                  TextField(
                    controller: _nomeCognomeController,
                    focusNode: _nomeCognomeFocus,
                    maxLength: 45, // Limite max 50 caratteri richiesto
                    style: const TextStyle(color: Colors.white),
                    onTap: () => _resettaSelezioneTesto(_nomeCognomeController), // CORREZIONE: Cursore pulito al click
                    onTapOutside: (event) => _nomeCognomeFocus.unfocus(),
                    decoration: const InputDecoration(
                      labelText: 'Nome e Cognome',
                      labelStyle: TextStyle(color: Colors.grey),
                      counterText: "", // Nasconde la barra del contatore numerico
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE2B13C))),
                      prefixIcon: Icon(Icons.person, color: Color(0xFFE2B13C)),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                ],

                TextField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  maxLength: 45, // Limite max 50 caratteri richiesto
                  style: const TextStyle(color: Colors.white),
                  onTap: () => _resettaSelezioneTesto(_emailController), // CORREZIONE: Cursore pulito al click
                  onTapOutside: (event) => _emailFocus.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    labelStyle: TextStyle(color: Colors.grey),
                    counterText: "", // Nasconde la barra del contatore numerico
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE2B13C))),
                    prefixIcon: Icon(Icons.email, color: Color(0xFFE2B13C)),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),

                TextField(
                  controller: _passwordController,
                  focusNode: _passwordFocus,
                  maxLength: 45, // Limite max 50 caratteri richiesto
                  style: const TextStyle(color: Colors.white),
                  onTap: () => _resettaSelezioneTesto(_passwordController), // CORREZIONE: Cursore pulito al click
                  onTapOutside: (event) => _passwordFocus.unfocus(),
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    labelStyle: TextStyle(color: Colors.grey),
                    counterText: "", // Nasconde la barra del contatore numerico
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE2B13C))),
                    prefixIcon: Icon(Icons.lock, color: Color(0xFFE2B13C)),
                  ),
                  obscureText: true,
                ),

                if (_isLogin)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _mostraDialogoRecuperoPassword,
                      child: const Text(
                        'Hai dimenticato la password?',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                    ),
                  ),

                const SizedBox(height: 16),

                _isLoading
                    ? const CircularProgressIndicator(color: Color(0xFFE2B13C))
                    : ElevatedButton(
                  onPressed: _inviaForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF164638),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_isLogin ? 'ACCEDI' : 'REGISTRATI', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() {
                    _isLogin = !_isLogin;
                    // Pulisce i campi quando l'utente cambia schermata per sicurezza
                    _nomeCognomeController.clear();
                    _emailController.clear();
                    _passwordController.clear();
                  }),
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