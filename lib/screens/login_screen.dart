import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // AGGIUNTO: Necessario per recuperare il token del dispositivo
import 'package:firebase_remote_config/firebase_remote_config.dart'; // AGGIUNTO: Necessario per registrare la versione corrente della Privacy Policy
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart'; // AGGIUNTO per aprire il link della Privacy Policy

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
  final _telefonoFocus = FocusNode();

  bool _isLogin = true;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _accettaPrivacyPolicy = false; // AGGIUNTO: Stato per la spunta obbligatoria Privacy Policy

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

  void _resettaSelezioneTesto(TextEditingController controller) {
    final text = controller.text;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    // SOLUZIONE: Forza l'apertura della tastiera. Risolve il bug in cui
    // la tastiera non si riapre dopo aver usato il tasto back di Android,
    // poiché il TextField mantiene il focus ma la tastiera risulta chiusa.
    SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  void _mostraDialogoRecuperoPassword() {
    _recuperoEmailController.text = _emailController.text.trim();
    _resettaSelezioneTesto(_recuperoEmailController);

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) {
        final FocusNode recuperoEmailFocusNode = FocusNode();

        return AlertDialog(
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
                focusNode: recuperoEmailFocusNode,
                autofocus: true,
                maxLength: 45,
                style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87),
                onTap: () => _resettaSelezioneTesto(_recuperoEmailController),
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
        );
      },
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

  // AGGIUNTO: Funzione helper per aprire la Privacy Policy sul browser
  Future<void> _apriPrivacyPolicy() async {
    final Uri url = Uri.parse('https://agbarber-bc826.web.app/privacypolicy.html');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Errore durante l'apertura del link della Privacy Policy: $e");
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

      // AGGIUNTO: Verifica obbligatoria del consenso Privacy Policy in registrazione
      if (!_accettaPrivacyPolicy) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("È necessario accettare la Privacy Policy per poter creare un account."),
            backgroundColor: Colors.red,
          ),
        );
        return;
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

        // MODIFICATO: Aggiunge il token nell'array fcmTokens (multi-dispositivo) al momento del login
        if (userCredential.user != null && !kIsWeb) {
          try {
            final String? token = await FirebaseMessaging.instance.getToken();
            if (token != null && token.isNotEmpty) {
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(userCredential.user!.uid)
                  .update({
                'fcmTokens': FieldValue.arrayUnion([token]),
                'fcmToken': token, // Mantengo retrocompatibilità
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

          // AGGIUNTO: Recupero dinamico della versione Privacy Policy richiesta da Remote Config
          String versionePrivacyAttuale = "1.0";
          try {
            final remoteConfig = FirebaseRemoteConfig.instance;
            versionePrivacyAttuale = remoteConfig.getString('privacy_required_version');
            if (versionePrivacyAttuale.isEmpty) versionePrivacyAttuale = "1.0";
          } catch (e) {
            debugPrint("Errore lettura Remote Config in registrazione: $e");
          }

          // MODIFICATO: Recupero preventivo dell'fcmToken del dispositivo in fase di registrazione
          String? token;
          if (!kIsWeb) {
            try {
              // Richiede i permessi per le notifiche push
              await FirebaseMessaging.instance.requestPermission();
              token = await FirebaseMessaging.instance.getToken();
            } catch (e) {
              debugPrint("Errore nel recupero dell'fcmToken alla registrazione: $e");
            }
          }

          final List<String> listaTokenIniziale = (token != null && token.isNotEmpty) ? [token] : [];

          // CORRETTO: Inserimento dei campi di tracciamento e accettazione della Privacy Policy per evitare il ri-check
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid)
              .set({
            'name': _nomeCognomeController.text.trim(),
            'email': email,
            'role': 'cliente',
            'phone': telefonoFinale,
            'fcmToken': token ?? '', // Campo legacy
            'fcmTokens': listaTokenIniziale, // MODIFICATO: Salvataggio multi-dispositivo nativo del token
            'privacyAccepted': true, // AGGIUNTO: Registra l'accettazione del consenso
            'privacyAcceptedVersion': versionePrivacyAttuale, // AGGIUNTO: Salva la versione corrente
            'privacyAcceptedAt': FieldValue.serverTimestamp(), // AGGIUNTO: Registra la data e l'ora di accettazione
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }

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

    return GestureDetector(
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
                    onTap: () => _resettaSelezioneTesto(_nomeCognomeController),
                    onTapOutside: (event) => _nomeCognomeFocus.unfocus(),
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
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onTap: () => _resettaSelezioneTesto(_telefonoController),
                    onTapOutside: (event) => _telefonoFocus.unfocus(),
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
                  onTap: () => _resettaSelezioneTesto(_emailController),
                  onTapOutside: (event) => _emailFocus.unfocus(),
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
                  onTap: () => _resettaSelezioneTesto(_passwordController),
                  onTapOutside: (event) => _passwordFocus.unfocus(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    labelStyle: const TextStyle(color: Colors.grey),
                    counterText: "",
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: coloreBordiInput)),
                    focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Color(0xFFE2B13C))),
                    prefixIcon: const Icon(Icons.lock, color: Color(0xFFE2B13C)),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscurePassword,
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

                // AGGIUNTO: Checkbox per accettazione Privacy Policy (visibile solo durante la Registrazione)
                if (!_isLogin) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: _accettaPrivacyPolicy,
                        activeColor: const Color(0xFFE2B13C),
                        checkColor: Colors.black,
                        onChanged: (bool? newValue) {
                          setState(() {
                            _accettaPrivacyPolicy = newValue ?? false;
                          });
                        },
                      ),
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              'Ho letto e accetto la ',
                              style: TextStyle(color: coloreTestoInput, fontSize: 13),
                            ),
                            GestureDetector(
                              onTap: _apriPrivacyPolicy,
                              child: const Text(
                                'Privacy Policy',
                                style: TextStyle(
                                  color: Color(0xFFE2B13C),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],

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
                    _accettaPrivacyPolicy = false; // AGGIUNTO: Reset dello stato Privacy Policy al cambio vista
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
    );
  }
}