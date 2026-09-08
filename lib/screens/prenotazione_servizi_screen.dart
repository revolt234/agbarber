import 'dart:async';
import 'dart:io'; // Per verificare lo stato della rete reale
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart'; // AGGIUNTO: Necessario per richiamare eliminaUtenteCompleto
import 'package:firebase_messaging/firebase_messaging.dart'; // AGGIUNTO: Necessario per recuperare il token FCM aggiornato
import 'package:firebase_remote_config/firebase_remote_config.dart'; // AGGIUNTO: Necessario per la lettura dinamica della versione Privacy
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart'; // AGGIUNTO: Per layout a incastro (Tetris/Masonry)
import 'package:prenotazionibarbiere/screens/prenotazione_calendario_screen.dart';
import 'package:url_launcher/url_launcher.dart'; // AGGIUNTO: Necessario per aprire il link alla Privacy Policy
import 'login_screen.dart'; // Importato per permettere il reindirizzamento alla LoginScreen
import 'package:flutter/foundation.dart' show kIsWeb;

class PrenotazioneServiziScreen extends StatefulWidget {
  const PrenotazioneServiziScreen({super.key});

  @override
  State<PrenotazioneServiziScreen> createState() => _PrenotazioneServiziScreenState();
}

class _PrenotazioneServiziScreenState extends State<PrenotazioneServiziScreen> {
  String? _servizioSelezionatoId;
  Map<String, dynamic>? _datiServizioSelezionato;
  String _nomeUtente = "";
  bool _isLoadingNome = true;
  late Stream<QuerySnapshot> _servicesStream;
  StreamSubscription<DocumentSnapshot>? _userSubscription;

  // AGGIUNTO: ScrollController per la gestione e la visualizzazione permanente della Scrollbar
  final ScrollController _scrollController = ScrollController();

  // MODIFICATO: Versione dinamica letta da Firebase Remote Config (con fallback a "1.0")
  String _versionePrivacyRichiesta = "1.0";
  bool _dialogPrivacyMostrato = false;

  // Colore Oro per le selezioni
  final Color _coloreOro = const Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _inizializzaStream();
    _inizializzaRemoteConfig(); // AGGIUNTO: Inizializza e recupera la versione da Remote Config
    _ascoltaNomeUtenteInTempoReale();
    _richiediPermessiNotifiche();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _scrollController.dispose(); // AGGIUNTO: Rilascio delle risorse dello ScrollController
    super.dispose();
  }

  // AGGIUNTO: Recupera dinamicamente il parametro "privacy_required_version" da Firebase Remote Config
  Future<void> _inizializzaRemoteConfig() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: Duration.zero, // Consente di recuperare immediatamente le modifiche
      ));
      await remoteConfig.setDefaults({'privacy_required_version': '1.0'});
      await remoteConfig.fetchAndActivate();

      final String versioneRemota = remoteConfig.getString('privacy_required_version');
      if (versioneRemota.isNotEmpty) {
        _versionePrivacyRichiesta = versioneRemota;
      }
    } catch (e) {
      debugPrint("Errore durante il recupero da Remote Config: $e");
    }
  }

  void _inizializzaStream() {
    _servicesStream = FirebaseFirestore.instance
        .collection('services')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  Future<void> _richiediPermessiNotifiche() async {
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
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

  // AGGIUNTO: Esegue la cancellazione completa dell'account se l'utente rifiuta le nuove condizioni della privacy
  Future<void> _eliminaAccountEseguiLogout(String uid) async {
    // Mostra indicatore di caricamento bloccante
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
      ),
    );

    try {
      final FirebaseFunctions functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
      final HttpsCallable callable = functions.httpsCallable(
        'eliminaUtenteCompleto',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      await callable.call(<String, dynamic>{'uid': uid});

      // Cancella il token FCM hardware locale
      try {
        await FirebaseMessaging.instance.deleteToken();
      } catch (e) {
        debugPrint("Errore rimozione token FCM post eliminazione account: $e");
      }

      await FirebaseAuth.instance.signOut();

      if (mounted) {
        Navigator.pop(context); // Chiude il loader
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account e relative prenotazioni eliminati con successo per rifiuto privacy.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Chiude il loader
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante l\'eliminazione dell\'account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // AGGIUNTO: Mostra il dialogo di accettazione obbligatoria con la versione letta da Remote Config e opzione di recesso
  void _mostraDialogoAccettazionePrivacyObbligatoria(String uid) {
    if (_dialogPrivacyMostrato) return;
    _dialogPrivacyMostrato = true;

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false, // Impedisce la chiusura toccando all'esterno
      builder: (context) {
        bool isSalvataggioInCorso = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: false, // Impedisce la chiusura con il tasto Indietro
              child: AlertDialog(
                backgroundColor: isDarkMode ? const Color(0xFFFDFBF7) : Colors.white,
                title: Text(
                  "Informativa Privacy 📋",
                  style: TextStyle(
                    color: isDarkMode ? const Color(0xFF211D1A) : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Abbiamo aggiornato le nostre norme sulla Privacy Policy per garantire una maggiore trasparenza e sicurezza dei tuoi dati personali.",
                      style: TextStyle(
                        color: isDarkMode ? const Color(0xFF3D3734) : Colors.black87,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _apriPrivacyPolicy,
                      child: const Text(
                        "Clicca qui per leggere l'Informativa sulla Privacy completa",
                        style: TextStyle(
                          color: Color(0xFFD4AF37),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      "Per continuare ad utilizzare l'applicazione ed effettuare prenotazioni è necessario prendere visione ed accettare i nuovi termini.",
                      style: TextStyle(
                        color: isDarkMode ? const Color(0xFF6B635E) : Colors.black54,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                actions: [
                  // Pulsante per Rifiutare e avviare la cancellazione dell'account o il logout
                  TextButton(
                    onPressed: isSalvataggioInCorso
                        ? null
                        : () async {
                      // Mostra conferma di eliminazione/recesso
                      final bool confermaEliminazione = await showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: isDarkMode ? const Color(0xFFFDFBF7) : Colors.white,
                          title: Text(
                            "Rifiuta e Cancella Account",
                            style: TextStyle(color: isDarkMode ? const Color(0xFF211D1A) : Colors.black87),
                          ),
                          content: Text(
                            "Rifiutando la Privacy Policy non potrai utilizzare i servizi di prenotazione. Vuoi eliminare definitivamente il tuo account e tutti i dati associati?",
                            style: TextStyle(color: isDarkMode ? const Color(0xFF3D3734) : Colors.black87),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text("Annulla"),
                            ),
                            TextButton(
                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text("Elimina Account"),
                            ),
                          ],
                        ),
                      ) ?? false;

                      if (confermaEliminazione && context.mounted) {
                        _dialogPrivacyMostrato = false;
                        Navigator.pop(context); // Chiude il dialogo della privacy
                        await _eliminaAccountEseguiLogout(uid); // Richiama la procedura di eliminazione
                      }
                    },
                    child: const Text(
                      'Rifiuta ed Elimina Account',
                      style: TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF164638),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: isSalvataggioInCorso
                        ? null
                        : () async {
                      setDialogState(() => isSalvataggioInCorso = true);
                      try {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(uid)
                            .update({
                          'privacyAccepted': true,
                          'privacyAcceptedVersion': _versionePrivacyRichiesta,
                          'privacyAcceptedAt': FieldValue.serverTimestamp(),
                        });

                        _dialogPrivacyMostrato = false;
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      } catch (e) {
                        debugPrint("Errore aggiornamento accettazione privacy: $e");
                        setDialogState(() => isSalvataggioInCorso = false);
                      }
                    },
                    child: isSalvataggioInCorso
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                        : const Text(
                      'ACCETTA E CONTINUA',
                      style: TextStyle(fontWeight: FontWeight.bold),
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

  // AGGIUNTO: Funzione asincrona di allineamento del token in background all'avvio dell'app per sessioni persistenti
  Future<void> _sincronizzaTokenFCM(String uid) async {
    if (kIsWeb) return;
    try {
      // Verifica o richiede i permessi per le notifiche push remota
      await FirebaseMessaging.instance.requestPermission();

      // Preleva il token FCM rigenerato dall'aggiornamento dell'app
      String? tokenAttuale = await FirebaseMessaging.instance.getToken();

      if (tokenAttuale != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .update({'fcmToken': tokenAttuale});
        debugPrint("Token FCM sincronizzato correttamente all'avvio per la sessione attiva.");
      }
    } catch (e) {
      debugPrint("Errore silenzioso sincronizzazione token all'avvio: $e");
    }
  }

  void _ascoltaNomeUtenteInTempoReale() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // MODIFICATO: Sincronizziamo il token preventivamente non appena rileviamo l'utente loggato in persistenza
      _sincronizzaTokenFCM(user.uid);

      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((userDoc) async {

        // Controlliamo che l'utente sia ancora presente nell'istanza Auth locale
        final currentUserCheck = FirebaseAuth.instance.currentUser;
        if (currentUserCheck == null) {
          _userSubscription?.cancel();
          return;
        }

        // MODIFICATO: Evitiamo il falso positivo per gli account appena registrati.
        // Se il documento non esiste ancora sul server, controlliamo da quanto tempo è stato creato l'account Auth.
        if (!userDoc.exists && !userDoc.metadata.isFromCache) {
          final DateTime? creationTime = currentUserCheck.metadata.creationTime;
          if (creationTime != null) {
            final differenza = DateTime.now().difference(creationTime);
            // Se l'account è stato registrato da meno di 45 secondi, non effettuiamo il logout.
            // Stiamo dando il tempo a LoginScreen di terminare la scrittura .set() su Firestore.
            if (differenza.inSeconds < 45) {
              if (mounted) {
                setState(() {
                  _nomeUtente = currentUserCheck.displayName ?? "Cliente";
                  _isLoadingNome = false;
                });
              }
              return;
            }
          }

          // Se l'account è vecchio e il documento non esiste sul server, allora è stato rimosso davvero dal barbiere.
          _userSubscription?.cancel();
          await FirebaseAuth.instance.signOut();

          if (mounted) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Il tuo account è stato rimosso o non è più attivo."),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
            Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
          }
          return;
        }

        if (userDoc.exists && userDoc.data() != null) {
          final data = userDoc.data() as Map<String, dynamic>;

          // AGGIUNTO: Controllo dinamico rispetto alla versione letta da Remote Config
          final String versioneAccettata = data['privacyAcceptedVersion']?.toString() ?? '';
          if (versioneAccettata != _versionePrivacyRichiesta && mounted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _mostraDialogoAccettazionePrivacyObbligatoria(user.uid);
            });
          }

          if (data.containsKey('name') && data['name']!.toString().trim().isNotEmpty) {
            if (mounted) {
              setState(() {
                _nomeUtente = data['name'];
                _isLoadingNome = false;
              });
            }
            return;
          }
        }
      }, onError: (e) {
        debugPrint("Errore nell'ascolto del nome utente: $e");
        if (mounted) {
          setState(() {
            _nomeUtente = FirebaseAuth.instance.currentUser?.displayName ?? "Cliente";
            _isLoadingNome = false;
          });
        }
      });
    } else {
      if (mounted) {
        setState(() {
          _nomeUtente = "Ospite";
          _isLoadingNome = false;
        });
      }
    }
  }

  Future<bool> _controllaConnessioneReale() async {
    if (kIsWeb) {
      return true;
    }
    try {
      final risultato = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      return risultato.isNotEmpty && risultato[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _mostraDialogoRegistrazioneObbligatoria() {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFFFDFBF7) : Colors.white,
          title: Text(
            "Accesso Richiesto 🔐",
            style: TextStyle(
              color: isDarkMode ? const Color(0xFF211D1A) : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            "Per poter completare la prenotazione dei servizi ed inserire il tuo appuntamento in agenda, è necessario creare un account o effettuare l'accesso.",
            style: TextStyle(
              color: isDarkMode ? const Color(0xFF6B635E) : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'ANNULLA',
                style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF164638),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              },
              child: const Text(
                'ACCEDI / REGISTRATI',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final Color coloreSfondoSchermata = isDarkMode ? const Color(0xFFF5F2EB) : const Color(0xFFF4F6F5);
    final Color coloreTestoTitoli = isDarkMode ? const Color(0xFF211D1A) : Colors.black87;
    final Color coloreSfondoCardSpenta = isDarkMode ? const Color(0xFFFDFBF7) : Colors.white;
    final Color coloreTestoCardSpenta = isDarkMode ? const Color(0xFF211D1A) : Colors.black87;
    final Color coloreIconaCardSpenta = isDarkMode ? _coloreOro : const Color(0xFF164638);

    return Scaffold(
      backgroundColor: coloreSfondoSchermata,
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: _servicesStream,
          builder: (context, snapshot) {
            final bool haErroreConnessione = snapshot.hasError;
            final bool haDatiValidi = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
            final bool puoProseguire = !haErroreConnessione && haDatiValidi && _servizioSelezionatoId != null;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _isLoadingNome
                          ? const SizedBox(
                        height: 32,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(color: Color(0xFFD4AF37), strokeWidth: 2),
                          ),
                        ),
                      )
                          : Text(
                        'Cliente: $_nomeUtente',
                        style: TextStyle(color: coloreTestoTitoli, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Container(
                          width: 60,
                          height: 60,
                          padding: const EdgeInsets.all(4.0),
                          decoration: BoxDecoration(
                            color: const Color(0xFF164638),
                            shape: BoxShape.circle,
                            border: Border.all(color: _coloreOro, width: 2),
                          ),
                          child: ClipOval(
                            child: Image.asset(
                              'assets/A di barber.png',
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: Builder(
                    builder: (context) {
                      if (haErroreConnessione) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.wifi_off, color: Color(0xFFD4AF37), size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  'Connessione internet assente\no instabile.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: coloreTestoTitoli, fontSize: 16),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF164638),
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _inizializzaStream();
                                      _isLoadingNome = true;
                                      _ascoltaNomeUtenteInTempoReale();
                                    });
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Riprova'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)));
                      }

                      if (!haDatiValidi) {
                        return Center(child: Text('Nessun servizio disponibile al momento.', style: TextStyle(color: coloreTestoTitoli)));
                      }

                      final servizi = snapshot.data!.docs;

                      // AGGIUNTO: Scrollbar visibile e MasonryGridView per incastro tipo Tetris
                      return Scrollbar(
                        controller: _scrollController,
                        thumbVisibility: true,
                        interactive: true,
                        thickness: 6.0,
                        radius: const Radius.circular(8.0),
                        child: MasonryGridView.count(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                          crossAxisCount: 2,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 16,
                          itemCount: servizi.length,
                          itemBuilder: (context, index) {
                            final doc = servizi[index];
                            final dati = doc.data() as Map<String, dynamic>;

                            final String id = doc.id;
                            final String nome = dati['name'] ?? 'Servizio';
                            final double prezzo = (dati['price'] ?? 0.0).toDouble();
                            final int durata = dati['duration'] ?? 0;

                            final bool isSelezionato = _servizioSelezionatoId == id;

                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _servizioSelezionatoId = id;
                                  _datiServizioSelezionato = dati;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                decoration: BoxDecoration(
                                  color: isSelezionato
                                      ? (isDarkMode ? const Color(0xFFFFFDF8) : const Color(0xFFFFFDF7))
                                      : coloreSfondoCardSpenta,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isSelezionato ? _coloreOro : (isDarkMode ? const Color(0xFFE2DCD2) : Colors.black12),
                                    width: isSelezionato ? 2.5 : 1.0,
                                  ),
                                  boxShadow: isDarkMode ? null : [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.05),
                                      blurRadius: 6,
                                      offset: const Offset(0, 3),
                                    )
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min, // Si adatta verticalmente al contenuto
                                    children: [
                                      // Fascia superiore stilizzata del blocco note (con fori circolari)
                                      Container(
                                        height: 32,
                                        color: isSelezionato
                                            ? _coloreOro
                                            : (isDarkMode ? const Color(0xFFE2DCD2) : const Color(0xFFE0E0E0)),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: isDarkMode ? const Color(0xFFFDFBF7) : Colors.white,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: isDarkMode ? const Color(0xFFFDFBF7) : Colors.white,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Contenuto del foglio a sviluppo dinamico verticale
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              nome.toLowerCase().contains('barba') ? Icons.chair : Icons.content_cut,
                                              color: isSelezionato ? _coloreOro : coloreIconaCardSpenta,
                                              size: 30,
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              nome,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                color: isSelezionato ? (isDarkMode ? const Color(0xFF211D1A) : Colors.black) : coloreTestoCardSpenta,
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Text(
                                              '$durata min',
                                              style: TextStyle(
                                                color: isSelezionato
                                                    ? (isDarkMode ? const Color(0xFF6B635E) : Colors.grey.shade700)
                                                    : Colors.grey.shade600,
                                                fontSize: 12,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${prezzo.toStringAsFixed(2).replaceAll('.', ',')} €',
                                              style: TextStyle(
                                                color: isSelezionato ? _coloreOro : coloreTestoCardSpenta,
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _coloreOro,
                      foregroundColor: const Color(0xFF121212),
                      disabledBackgroundColor: isDarkMode ? Colors.black.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
                      disabledForegroundColor: isDarkMode ? Colors.black.withValues(alpha: 0.25) : Colors.black.withValues(alpha: 0.25),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 2,
                    ),
                    onPressed: puoProseguire
                        ? () async {
                      final utenteCorrente = FirebaseAuth.instance.currentUser;
                      if (utenteCorrente == null) {
                        _mostraDialogoRegistrazioneObbligatoria();
                        return;
                      }

                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(color: Color(0xFFD4AF37)),
                        ),
                      );

                      try {
                        if (utenteCorrente.email != null) {
                          final String emailNormalizzata = utenteCorrente.email!.trim().toLowerCase();
                          final banDoc = await FirebaseFirestore.instance
                              .collection('banned_emails')
                              .doc(emailNormalizzata)
                              .get(const GetOptions(source: Source.server));

                          if (banDoc.exists) {
                            if (context.mounted) Navigator.pop(context);

                            await FirebaseAuth.instance.signOut();

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).clearSnackBars();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Accesso negato: questo account email è stato bloccato dall'amministratore."),
                                  backgroundColor: Colors.orange,
                                  duration: Duration(seconds: 5),
                                ),
                              );
                              Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                            }
                            return;
                          }
                        }
                      } catch (e) {
                        debugPrint("Errore durante la verifica della blacklist: $e");
                      }

                      bool online = await _controllaConnessioneReale();

                      if (!context.mounted) return;
                      Navigator.pop(context);

                      if (online) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PrenotazioneCalendarioScreen(
                              servizioId: _servizioSelezionatoId!,
                              servizioNome: _datiServizioSelezionato?['name'] ?? 'Servizio',
                              servizioDurata: _datiServizioSelezionato?['duration'] ?? 30,
                              servizioPrezzo: (_datiServizioSelezionato?['price'] ?? 0.0).toDouble(),
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Impossibile proseguire: connessione internet assente o instabile.'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                        : null,
                    child: const Text(
                      'Avanti',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}