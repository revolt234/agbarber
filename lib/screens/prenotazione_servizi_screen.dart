import 'dart:async';
import 'dart:io'; // Per verificare lo stato della rete reale
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:prenotazionibarbiere/screens/prenotazione_calendario_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _inizializzaStream();
    _ascoltaNomeUtenteInTempoReale();
    _richiediPermessiNotifiche();
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    super.dispose();
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

  void _ascoltaNomeUtenteInTempoReale() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _userSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((userDoc) {
        if (userDoc.exists && userDoc.data() != null) {
          final data = userDoc.data() as Map<String, dynamic>;
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
            _nomeUtente = "Cliente";
            _isLoadingNome = false;
          });
        }
      });
    } else {
      if (mounted) {
        setState(() {
          _nomeUtente = "Ospite"; // Impostato esplicitamente a Ospite per coerenza visiva
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

  // Funzione di supporto per mostrare il popup di avviso per l'Ospite
  void _mostraDialogoRegistrazioneObbligatoria() {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text(
            "Accesso Richiesto 🔐",
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            "Per poter completare la prenotazione dei servizi ed inserire il tuo appuntamento in agenda, è necessario creare un account o effettuare l'accesso.",
            style: TextStyle(
              color: isDarkMode ? Colors.grey.shade400 : Colors.black54,
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
                Navigator.pop(context); // Chiude il dialogo corrente
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
    // MODIFICATO: Rilevazione del tema attivo sul telefono (Light/Dark)
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Configurazione dei colori dinamici della pagina
    final Color coloreSfondoSchermata = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF4F6F5);
    final Color coloreTestoTitoli = isDarkMode ? Colors.white : Colors.black87;
    final Color coloreSfondoCardSpenta = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final Color coloreTestoCardSpenta = isDarkMode ? Colors.white : Colors.black87;
    final Color coloreIconaCardSpenta = isDarkMode ? const Color(0xFFE2B13C) : const Color(0xFF164638);

    return Scaffold(
      backgroundColor: coloreSfondoSchermata, // MODIFICATO: Sfondo adattivo
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
                // 1. INTESTAZIONE
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
                            child: CircularProgressIndicator(color: Color(0xFFE2B13C), strokeWidth: 2),
                          ),
                        ),
                      )
                          : Text(
                        'Ciao, $_nomeUtente!',
                        style: TextStyle(color: coloreTestoTitoli, fontSize: 24, fontWeight: FontWeight.bold), // MODIFICATO: Testo adattivo
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            padding: const EdgeInsets.all(4.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFF164638),
                              shape: BoxShape.circle,
                              border: Border.all(color: const Color(0xFFE2B13C), width: 2),
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/A di barber.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AG The gentleman\nBarber di Abate Gerardo',
                                  style: TextStyle(color: coloreTestoTitoli, fontSize: 16, fontWeight: FontWeight.bold, height: 1.2), // MODIFICATO: Testo adattivo
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Via Sacco Giovanni, 18\nCapaccio Paestum',
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 2. LISTA DEI SERVIZI
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
                                const Icon(Icons.wifi_off, color: Color(0xFFE2B13C), size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  'Connessione internet assente\no instabile.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: coloreTestoTitoli, fontSize: 16), // MODIFICATO: Testo adattivo
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
                        return const Center(child: CircularProgressIndicator(color: Color(0xFFE2B13C)));
                      }

                      if (!haDatiValidi) {
                        return Center(child: Text('Nessun servizio disponibile al momento.', style: TextStyle(color: coloreTestoTitoli))); // MODIFICATO: Testo adattivo
                      }

                      final servizi = snapshot.data!.docs;

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
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
                              margin: const EdgeInsets.only(bottom: 14),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                              decoration: BoxDecoration(
                                // MODIFICATO: Sfondo card e bordi che variano dinamicamente in base a selezione e darkmode
                                color: isSelezionato
                                    ? (isDarkMode ? const Color(0xFFFFF1CC) : const Color(0xFFFFF6E0))
                                    : coloreSfondoCardSpenta,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isSelezionato ? const Color(0xFFE2B13C) : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    nome.toLowerCase().contains('barba') ? Icons.chair : Icons.content_cut,
                                    color: isSelezionato ? const Color(0xFF164638) : coloreIconaCardSpenta, // MODIFICATO: Icona adattiva
                                    size: 28,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nome,
                                          style: TextStyle(
                                              color: isSelezionato ? Colors.black : coloreTestoCardSpenta, // MODIFICATO: Testo adattivo
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$durata min',
                                          style: TextStyle(color: isSelezionato ? Colors.grey.shade700 : Colors.grey.shade500, fontSize: 12), // MODIFICATO: Sottotesto adattivo
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${prezzo.toStringAsFixed(2).replaceAll('.', ',')} €',
                                    style: TextStyle(
                                        color: isSelezionato ? Colors.black : coloreTestoCardSpenta, // MODIFICATO: Prezzo adattivo
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE2B13C),
                      foregroundColor: const Color(0xFF121212),
                      disabledBackgroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08), // MODIFICATO: Disabilitato adattivo
                      disabledForegroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.25), // MODIFICATO: Testo disabilitato adattivo
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 2,
                    ),
                    onPressed: puoProseguire
                        ? () async {
                      // INTERCETTAZIONE OSPITE: Controlla se l'utente non è autenticato prima di procedere
                      final utenteCorrente = FirebaseAuth.instance.currentUser;
                      if (utenteCorrente == null) {
                        _mostraDialogoRegistrazioneObbligatoria();
                        return;
                      }

                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(color: Color(0xFFE2B13C)),
                        ),
                      );

                      bool online = await _controllaConnessioneReale();

                      if (!context.mounted) return;
                      Navigator.pop(context);

                      if (online) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PrenotazioneCalendarioScreen( // MODIFICATO: Ora punta al calendario mensile
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
                      'Prosegui',
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