import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
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
  final _telefonoController = TextEditingController();

  final FocusNode _nomeCognomeFocus = FocusNode();
  final FocusNode _emailFocus = FocusNode();
  final FocusNode _passwordFocus = FocusNode();
  final FocusNode _telefonoFocus = FocusNode();

  bool _isLogin = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _nomeCognomeController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _recuperoEmailController.dispose();
    _telefonoController.dispose();
    _nomeCognomeFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _telefonoFocus.dispose();
    super.dispose();
  }

  void _mostraDialogoRecuperoPassword() {
    _recuperoEmailController.text = _emailController.text.trim();

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        title: Text(
          'Recupero Password',
          style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87, fontWeight: FontWeight.bold),
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
              maxLength: 45,
              style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87),
              textInputAction: TextInputAction.done,
              onTap: () {
                if (FocusScope.of(context).hasFocus) {
                  FocusScope.of(context).unfocus();
                  Future.microtask(() => FocusScope.of(context).requestFocus());
                }
              },
              decoration: const InputDecoration(
                labelText: 'Email',
                labelStyle: TextStyle(color: Colors.grey),
                counterText: "",
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
    // 1. DISSOCIAZIONE COMPLETA E NATIVA DEL CANALE TASTIERA PRIMA DELL'AUTENTICAZIONE
    FocusScope.of(context).unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    await SystemChannels.textInput.invokeMethod('TextInput.hide');

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

    if (!_isLogin) {
      final String telInserito = _telefonoController.text.trim();
      if (telInserito.isNotEmpty) {
        if (telInserito.length != 10 || !telInserito.startsWith('3')) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Inserisci un numero di cellulare italiano valido (esattamente 10 cifre, es: 3xxxxxxxxx)."),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }
    }

    setState(() => _isLoading = true);
    try {
      final String emailNormalizzata = email.toLowerCase();
      final banDoc = await FirebaseFirestore.instance
          .collection('banned_emails')
          .doc(emailNormalizzata)
          .get(const GetOptions(source: Source.server));

      if (banDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Accesso negato: questo account email è stato bloccato dall'amministratore."),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      UserCredential? userCredential;

      if (_isLogin) {
        if (kIsWeb) {
          await FirebaseAuth.instance.setSettings(appVerificationDisabledForTesting: false);
        }

        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        if (userCredential.user != null && !kIsWeb) {
          try {
            final String? token = await FirebaseMessaging.instance.getToken();
            if (token != null && token.isNotEmpty) {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(userCredential.user!.uid)
                  .update({
                'fcmTokens': FieldValue.arrayUnion([token]),
                'fcmToken': token,
              });
            }
          } catch (e) {
            debugPrint("Impossibile aggiornare gli fcmTokens al login: $e");
          }
        }
      } else {
        userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        if (userCredential.user != null) {
          await userCredential.user!.updateDisplayName(_nomeCognomeController.text.trim());

          final String telInserito = _telefonoController.text.trim();
          final String telefonoFinale = telInserito.isNotEmpty ? telInserito : 'Nessun cellulare';

          String? token;
          if (!kIsWeb) {
            try {
              await FirebaseMessaging.instance.requestPermission();
              token = await FirebaseMessaging.instance.getToken();
            } catch (e) {
              debugPrint("Errore nel recupero dell'fcmToken alla registrazione: $e");
            }
          }

          final List<String> listaTokenIniziale = (token != null && token.isNotEmpty) ? [token] : [];

          await FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid)
              .set({
            'name': _nomeCognomeController.text.trim(),
            'email': email,
            'role': 'cliente',
            'phone': telefonoFinale,
            'fcmToken': token ?? '',
            'fcmTokens': listaTokenIniziale,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

      // 2. GARANTISCE CHE IL CANALE NATIVO TASTIERA SIA CHIUSO PRIMA DI SMONTARE LA ROTTA
      FocusScope.of(context).unfocus();
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod('TextInput.hide');
      await Future.delayed(const Duration(milliseconds: 150));

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }

    } on FirebaseAuthException catch (e) {
      debugPrint("Firebase Auth Error Code: ${e.code}");
      debugPrint("Firebase Auth Error Message: ${e.message}");

      String messaggioErrore = "Si è verificato un errore: ${e.message}";

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
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final Color coloreSfondoSchermata = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF4F6F5);
    final Color coloreTestoTitoli = isDarkMode ? Colors.white : Colors.black87;
    final Color coloreTestoInput = isDarkMode ? Colors.white : Colors.black87;
    final Color coloreBordiInput = isDarkMode ? Colors.grey : Colors.grey.shade400;

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          FocusScope.of(context).unfocus();
        }
      },
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: coloreSfondoSchermata,
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
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: coloreTestoTitoli),
                  ),
                  const SizedBox(height: 24),

                  if (!_isLogin) ...[
                    TextField(
                      controller: _nomeCognomeController,
                      focusNode: _nomeCognomeFocus,
                      maxLength: 45,
                      style: TextStyle(color: coloreTestoInput),
                      textInputAction: TextInputAction.next,
                      onTap: () {
                        if (_nomeCognomeFocus.hasFocus) {
                          _nomeCognomeFocus.unfocus();
                          Future.microtask(() => _nomeCognomeFocus.requestFocus());
                        }
                      },
                      onSubmitted: (_) => FocusScope.of(context).requestFocus(_telefonoFocus),
                      decoration: InputDecoration(
                        labelText: 'Nome e Cognome',
                        labelStyle: const TextStyle(color: Colors.grey),
                        counterText: "",
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: coloreBordiInput)),
                        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE2B13C))),
                        prefixIcon: const Icon(Icons.person, color: Color(0xFFE2B13C)),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _telefonoController,
                      focusNode: _telefonoFocus,
                      maxLength: 10,
                      style: TextStyle(color: coloreTestoInput),
                      textInputAction: TextInputAction.next,
                      onTap: () {
                        if (_telefonoFocus.hasFocus) {
                          _telefonoFocus.unfocus();
                          Future.microtask(() => _telefonoFocus.requestFocus());
                        }
                      },
                      onSubmitted: (_) => FocusScope.of(context).requestFocus(_emailFocus),
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      decoration: InputDecoration(
                        labelText: 'Cellulare (Opzionale)',
                        labelStyle: const TextStyle(color: Colors.grey),
                        counterText: "",
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: coloreBordiInput)),
                        focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE2B13C))),
                        prefixIcon: const Icon(Icons.phone, color: Color(0xFFE2B13C)),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 16),
                  ],

                  TextField(
                    controller: _emailController,
                    focusNode: _emailFocus,
                    maxLength: 45,
                    style: TextStyle(color: coloreTestoInput),
                    textInputAction: TextInputAction.next,
                    onTap: () {
                      if (_emailFocus.hasFocus) {
                        _emailFocus.unfocus();
                        Future.microtask(() => _emailFocus.requestFocus());
                      }
                    },
                    onSubmitted: (_) => FocusScope.of(context).requestFocus(_passwordFocus),
                    decoration: InputDecoration(
                      labelText: 'Email',
                      labelStyle: const TextStyle(color: Colors.grey),
                      counterText: "",
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: coloreBordiInput)),
                      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE2B13C))),
                      prefixIcon: const Icon(Icons.email, color: Color(0xFFE2B13C)),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _passwordController,
                    focusNode: _passwordFocus,
                    maxLength: 45,
                    style: TextStyle(color: coloreTestoInput),
                    textInputAction: TextInputAction.done,
                    onTap: () {
                      if (_passwordFocus.hasFocus) {
                        _passwordFocus.unfocus();
                        Future.microtask(() => _passwordFocus.requestFocus());
                      }
                    },
                    onSubmitted: (_) => _inviaForm(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      labelStyle: const TextStyle(color: Colors.grey),
                      counterText: "",
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: coloreBordiInput)),
                      focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE2B13C))),
                      prefixIcon: const Icon(Icons.lock, color: Color(0xFFE2B13C)),
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
                      _nomeCognomeController.clear();
                      _emailController.clear();
                      _passwordController.clear();
                      _telefonoController.clear();
                    }),
                    child: Text(
                      _isLogin
                          ? 'Non hai un account? Registrati qui'
                          : 'Hai già un account? Accedi',
                      style: const TextStyle(color: Color(0xFFE2B13C)),
                    ),
                  ),
                  const SizedBox(height: 8),

                  OutlinedButton(
                    onPressed: () {
                      FocusScope.of(context).unfocus();
                      FocusManager.instance.primaryFocus?.unfocus();
                      SystemChannels.textInput.invokeMethod('TextInput.hide');
                      if (Navigator.of(context).canPop()) {
                        Navigator.pop(context);
                      } else {
                        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF164638), width: 1.5),
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text(
                      'CONTINUA COME OSPITE',
                      style: TextStyle(
                        color: Color(0xFF164638),
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}