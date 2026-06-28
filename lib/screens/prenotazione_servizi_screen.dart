import 'dart:async';
import 'dart:io'; // AGGIUNTO: Per verificare lo stato della rete reale
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'prenotazione_data_screen.dart';
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
          _nomeUtente = "Cliente";
          _isLoadingNome = false;
        });
      }
    }
  }

  // AGGIUNTO: Metodo per controllare la connettività di rete reale in modo istantaneo
  Future<bool> _controllaConnessioneReale() async {
    // Se l'app sta girando sul Web (Browser)
    if (kIsWeb) {
      // Evitiamo controlli IP/DNS che sul browser falliscono.
      // Ritorniamo direttamente true per sbloccare il tasto su Web.
      return true;
    }

    // Se l'app sta girando su Smartphone (Android / iOS)
    try {
      final risultato = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      return risultato.isNotEmpty && risultato[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: _servicesStream,
          builder: (context, snapshot) {
            // CORREZIONE: Gestiamo l'errore se Firestore fallisce esplicitamente il recupero.
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
                        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
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
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AG The gentleman\nBarber di Abate Gerardo',
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, height: 1.2),
                                ),
                                SizedBox(height: 4),
                                Text(
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
                                const Text(
                                  'Connessione internet assente\no instabile.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white, fontSize: 16),
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
                        return const Center(child: Text('Nessun servizio disponibile al momento.', style: TextStyle(color: Colors.white)));
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
                                color: isSelezionato ? const Color(0xFFFFF6E0) : Colors.white,
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
                                    color: const Color(0xFF164638),
                                    size: 28,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nome,
                                          style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$durata min',
                                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${prezzo.toStringAsFixed(2).replaceAll('.', ',')} €',
                                    style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
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
                      foregroundColor: const Color(0xFF121212), // CORREZIONE: Forza il testo attivo a essere visibile e scuro sul fondo oro
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.12),
                      disabledForegroundColor: Colors.white.withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 2,
                    ),
                    onPressed: puoProseguire
                        ? () async {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (context) => const Center(
                          child: CircularProgressIndicator(color: Color(0xFFE2B13C)),
                        ),
                      );

                      // CONTROLLO DI SICUREZZA: Eseguiamo una verifica reale e istantanea dello stato della rete
                      bool online = await _controllaConnessioneReale();

                      if (!context.mounted) return;
                      Navigator.pop(context); // Chiude il Dialog di caricamento

                      if (online) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PrenotazioneDataScreen(
                              servizioId: _servizioSelezionatoId!,
                              servizioNome: _datiServizioSelezionato?['name'] ?? 'Servizio',
                              servizioDurata: _datiServizioSelezionato?['duration'] ?? 30,
                              servizioPrezzo: (_datiServizioSelezionato?['price'] ?? 0.0).toDouble(), // AGGIUNTO: Trasmette il prezzo reale alla schermata successiva
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