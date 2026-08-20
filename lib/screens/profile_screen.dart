import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // AGGIUNTO: Necessario per i filtri di testo (digitsOnly)
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // AGGIUNTO: Necessario per leggere e aggiornare il telefono
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // AGGIUNTO: Necessario per gestire la cancellazione del token FCM
import 'package:intl/intl.dart'; // AGGIUNTO: Per la formattazione della data di nascita
import 'login_screen.dart'; // Importato per permettere il reindirizzamento al login

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? _user = FirebaseAuth.instance.currentUser;
  bool _isLoading = false;
  String _telefonoCorrente = "Caricamento..."; // AGGIUNTO: Stato locale per il numero di telefono
  String _compleannoCorrente = "Non impostato"; // AGGIUNTO: Stato locale per la data di nascita
  int _appuntamentiSaltati = 0; // AGGIUNTO: Stato locale per gli appuntamenti saltati
  double _saldoTotale = 0.0; // MODIFICATO: Stato locale per il saldo del cliente

  @override
  void initState() {
    super.initState();
    _recuperaDatiIniziali(); // MODIFICATO: Cambiato nome per riflettere il recupero completo
  }

  // MODIFICATO: Recupera il numero di telefono, la data di compleanno, gli appuntamenti saltati e il saldo corrente da Firestore
  Future<void> _recuperaDatiIniziali() async {
    if (_user == null) return;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_user.uid).get();

      // CORREZIONE DI SICUREZZA: Verifica se il widget è ancora montato prima di aggiornare lo stato
      if (!mounted) return;

      if (doc.exists && doc.data() != null) {
        final dati = doc.data() as Map<String, dynamic>;
        setState(() {
          _telefonoCorrente = dati['phone'] ?? 'Nessun cellulare';
          _compleannoCorrente = dati['birthdate'] ?? 'Non impostato';
          _appuntamentiSaltati = dati['appuntamentisaltati'] ?? 0;
          _saldoTotale = (dati['saldo'] ?? 0).toDouble();
        });
      } else {
        setState(() {
          _telefonoCorrente = 'Nessun cellulare';
          _compleannoCorrente = 'Non impostato';
          _appuntamentiSaltati = 0;
          _saldoTotale = 0.0;
        });
      }
    } catch (e) {
      debugPrint("Errore recupero dati utente: $e");
      if (mounted) {
        setState(() {
          _telefonoCorrente = 'Nessun cellulare';
          _compleannoCorrente = 'Non impostato';
          _appuntamentiSaltati = 0;
          _saldoTotale = 0.0;
        });
      }
    }
  }

  // AGGIUNTO: Mostra il DatePicker nativo per selezionare la data di nascita
  Future<void> _selezionaDataCompleanno() async {
    DateTime dataIniziale = DateTime(2000, 1, 1);

    if (_compleannoCorrente != 'Non impostato' && _compleannoCorrente.isNotEmpty) {
      try {
        dataIniziale = DateFormat('dd/MM/yyyy').parse(_compleannoCorrente);
      } catch (_) {}
    }

    final DateTime? dataSelezionata = await showDatePicker(
      context: context,
      initialDate: dataIniziale,
      firstDate: DateTime(1930),
      lastDate: DateTime.now(),
      locale: const Locale('it', 'IT'),
      builder: (context, child) {
        final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: isDarkMode
              ? ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFE2B13C),
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          )
              : ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF164638),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (dataSelezionata != null) {
      final String dataFormattata = DateFormat('dd/MM/yyyy').format(dataSelezionata);
      await _aggiornaCompleannoSuFirestore(dataFormattata);
    }
  }

  // AGGIUNTO: Salva la data di nascita su Firestore
  Future<void> _aggiornaCompleannoSuFirestore(String nuovaData) async {
    if (_user == null) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(_user.uid).update({
        'birthdate': nuovaData,
      });
      if (mounted) {
        setState(() => _compleannoCorrente = nuovaData);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Data di nascita aggiornata con successo.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante l\'aggiornamento: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // AGGIUNTO: Mostra il popup sicuro per la modifica o rimozione del numero telefonico italiano
  void _mostraDialogoModificaTelefono() {
    final bool haTelefono = _telefonoCorrente != 'Nessun cellulare';
    final TextEditingController telController = TextEditingController(
      text: haTelefono ? _telefonoCorrente : '',
    );
    final FocusNode telFocus = FocusNode();
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    void resettaSelezioneTesto(TextEditingController controller) {
      final text = controller.text;
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }

    // Resetta la selezione e apre la tastiera nativa all'apertura del dialogo
    resettaSelezioneTesto(telController);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text(
            'Modifica Cellulare',
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Inserisci il tuo nuovo numero di cellulare (10 cifre) o rimuovilo usando il pulsante sotto.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: telController,
                focusNode: telFocus,
                autofocus: true, // Assegna automaticamente il focus all'apertura
                maxLength: 10, // Blocca l'inserimento oltre la decima cifra
                keyboardType: TextInputType.phone,
                style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87),
                onTap: () => resettaSelezioneTesto(telController),
                onTapOutside: (event) => telFocus.unfocus(),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly, // Impedisce caratteri strani, spazi o simboli
                ],
                decoration: const InputDecoration(
                  labelText: 'Numero di cellulare',
                  labelStyle: TextStyle(color: Colors.grey),
                  counterText: "",
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFF164638)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Color(0xFFE2B13C)),
                  ),
                  prefixIcon: Icon(Icons.phone, color: Color(0xFFE2B13C)),
                ),
              ),
            ],
          ),
          actions: [
            // AGGIUNTO: Pulsante Rimuovi condizionale (visibile solo se l'utente ha già un numero salvato)
            if (haTelefono)
              TextButton(
                onPressed: () async {
                  telController.dispose();
                  telFocus.dispose();
                  Navigator.pop(context);
                  await _aggiornaTelefonoSuFirestore('Nessun cellulare');
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Rimuovi', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            TextButton(
              onPressed: () {
                telController.dispose();
                telFocus.dispose();
                Navigator.pop(context);
              },
              child: const Text('Annulla', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF164638)),
              onPressed: () async {
                final String nuovoTel = telController.text.trim();

                // Validazione rigorosa per i numeri mobili italiani (esattamente 10 cifre, iniziano per 3)
                if (nuovoTel.isEmpty || nuovoTel.length != 10 || !nuovoTel.startsWith('3')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Inserisci un numero di cellulare italiano valido (10 cifre, es: 3xxxxxxxxx)."),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                telController.dispose();
                telFocus.dispose();
                Navigator.pop(context);
                await _aggiornaTelefonoSuFirestore(nuovoTel);
              },
              child: const Text('Salva', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  // AGGIUNTO: Esegue la scrittura del numero validato o della rimozione su Cloud Firestore
  Future<void> _aggiornaTelefonoSuFirestore(String nuovoNumero) async {
    if (_user == null) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(_user.uid).update({
        'phone': nuovoNumero,
      });
      if (mounted) {
        setState(() => _telefonoCorrente = nuovoNumero);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nuovoNumero == 'Nessun cellulare'
                ? 'Numero rimosso con successo.'
                : 'Numero aggiornato con successo.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante l\'aggiornamento: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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

  // AGGIUNTO: Mostra il dialogo di conferma per la disconnessione dall'applicazione e cancella i token FCM
  void _mostraConfermaDisconnessione() {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool isDisconnessioneInCorso = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: !isDisconnessioneInCorso,
              child: AlertDialog(
                backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                title: Text(
                  'Disconnetti',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: Text(
                  'Sei sicuro di voler uscire dal tuo account?',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isDisconnessioneInCorso ? null : () => Navigator.pop(dialogContext),
                    child: const Text(
                      'Annulla',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade900),
                    onPressed: isDisconnessioneInCorso
                        ? null
                        : () async {
                      setDialogState(() {
                        isDisconnessioneInCorso = true;
                      });

                      // AGGIUNTO: Rimuove il token di questo dispositivo prima del logout
                      try {
                        final user = FirebaseAuth.instance.currentUser;
                        if (user != null) {
                          final token = await FirebaseMessaging.instance.getToken();
                          if (token != null && token.isNotEmpty) {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(user.uid)
                                .update({
                              'fcmTokens': FieldValue.arrayRemove([token]),
                              'fcmToken': FieldValue.delete(),
                            });
                          }
                        }
                        await FirebaseMessaging.instance.deleteToken();
                      } catch (e) {
                        debugPrint("Errore nella rimozione del token FCM al logout cliente: $e");
                      }

                      await FirebaseAuth.instance.signOut();
                      if (dialogContext.mounted) {
                        Navigator.pop(dialogContext);
                      }
                      if (mounted) {
                        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                      }
                    },
                    child: isDisconnessioneInCorso
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : const Text(
                      'Esci',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Funzione per ottimizzare l'eliminazione dell'account richiamando la Cloud Function universale e cancellando il token
  Future<void> _eliminaAccount() async {
    if (_user == null) return;

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
          'Sei sicuro? Questa azione è irreversibile e cancellerà permanentemente tutti i tuoi dati, incluse tutte le tue prenotazioni.',
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
      final FirebaseFunctions functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

      final HttpsCallable callable = functions.httpsCallable(
        'eliminaUtenteCompleto',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      await callable.call(<String, dynamic>{
        'uid': _user.uid,
      });

      // AGGIUNTO: Cancella il token hardware locale dopo l'eliminazione dell'account
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (e) {
        debugPrint("Errore rimozione token post eliminazione account: $e");
      }

      await FirebaseAuth.instance.signOut();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account e relative prenotazioni eliminati con successo.'),
            backgroundColor: Colors.green,
          ),
        );
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante l\'eliminazione: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color agVerde = Color(0xFF164638);
    const Color agOro = Color(0xFFE2B13C);

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final Color coloreSfondoSchermata = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF4F6F5);
    final Color coloreSfondoCard = isDarkMode ? const Color(0xFF1C2824) : Colors.white;
    final Color coloreTestoPrimario = isDarkMode ? Colors.white : Colors.black87;
    final Color coloreTestoSecondario = isDarkMode ? Colors.grey : Colors.black54;

    final bool isPositivoOZero = _saldoTotale >= 0;
    final Color coloreSaldo = isPositivoOZero ? Colors.green : Colors.red;

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

          Text('Dati Profilo', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: coloreTestoSecondario)),
          const Divider(color: agVerde),

          // Voce di menu per visualizzare e modificare in sicurezza il numero di telefono
          ListTile(
            leading: const Icon(Icons.phone, color: agOro),
            title: Text('Numero di Cellulare', style: TextStyle(color: coloreTestoPrimario)),
            subtitle: Text(_telefonoCorrente, style: TextStyle(color: coloreTestoSecondario)),
            trailing: Icon(Icons.edit, color: coloreTestoSecondario),
            onTap: _mostraDialogoModificaTelefono,
          ),

          // AGGIUNTO: Voce di menu per visualizzare e modificare la data del compleanno
          ListTile(
            leading: const Icon(Icons.cake, color: agOro),
            title: Text('Data di Nascita', style: TextStyle(color: coloreTestoPrimario)),
            subtitle: Text(_compleannoCorrente, style: TextStyle(color: coloreTestoSecondario)),
            trailing: Icon(Icons.edit, color: coloreTestoSecondario),
            onTap: _selezionaDataCompleanno,
          ),

          // AGGIUNTO: Voce informativa per visualizzare gli appuntamenti saltati
          ListTile(
            leading: Icon(
              Icons.event_busy,
              color: _appuntamentiSaltati > 0 ? Colors.red : Colors.green,
            ),
            title: Text('Appuntamenti Saltati', style: TextStyle(color: coloreTestoPrimario)),
            subtitle: Text(
              '$_appuntamentiSaltati',
              style: TextStyle(
                color: _appuntamentiSaltati > 0 ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          // MODIFICATO: Voce informativa per visualizzare il saldo totale
          ListTile(
            leading: Icon(Icons.account_balance_wallet, color: coloreSaldo),
            title: Text('Saldo Totale', style: TextStyle(color: coloreTestoPrimario)),
            subtitle: Text(
              '€ ${_saldoTotale.toStringAsFixed(2).replaceAll('.', ',')}',
              style: TextStyle(
                color: coloreSaldo,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),

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
            onTap: _mostraConfermaDisconnessione, // MODIFICATO: Collegato al metodo di conferma
          ),
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