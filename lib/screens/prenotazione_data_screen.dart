import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';

class PrenotazioneDataScreen extends StatefulWidget {
  final String servizioId;
  final String servizioNome;
  final int servizioDurata;

  const PrenotazioneDataScreen({
    super.key,
    required this.servizioId,
    required this.servizioNome,
    required this.servizioDurata,
  });

  @override
  State<PrenotazioneDataScreen> createState() => _PrenotazioneDataScreenState();
}

// Classe di supporto per mappare gli appuntamenti esistenti in minuti
class IntervalloAppuntamento {
  final int inizio;
  final int fine;
  IntervalloAppuntamento({required this.inizio, required this.fine});
}

class _PrenotazioneDataScreenState extends State<PrenotazioneDataScreen> {
  DateTime _dataSelezionata = DateTime.now();
  String? _barbiereSelezionatoId;
  String? _barbiereSelezionatoNome;
  String? _orarioSelezionato;

  bool _isLoadingSlot = false;
  bool _isLoadingConfig = true;
  bool _isSaving = false;

  Map<String, dynamic> _orariNegozioBase = {};
  Map<String, dynamic> _eccezioniCalendario = {};
  List<String> _slotOrariCalcolati = [];
  List<IntervalloAppuntamento> _appuntamentiOccupati = [];

  final List<String> _giorniSettimana = [
    'domenica', 'lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato'
  ];

  @override
  void initState() {
    super.initState();
    _inizializzaDati();
  }

  Future<void> _inizializzaDati() async {
    try {
      final orariDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('orari_negozio')
          .get(const GetOptions(source: Source.server));

      if (orariDoc.exists) _orariNegozioBase = orariDoc.data() ?? {};

      final eccezioniSnap = await FirebaseFirestore.instance
          .collection('calendar_exceptions')
          .get(const GetOptions(source: Source.server));

      for (var doc in eccezioniSnap.docs) {
        _eccezioniCalendario[doc.id] = doc.data();
      }
      setState(() => _isLoadingConfig = false);
    } catch (e) {
      debugPrint("Errore inizializzazione: $e");
      setState(() => _isLoadingConfig = false);
    }
  }

  Future<void> _aggiornaSlotOrari() async {
    if (_barbiereSelezionatoId == null) return;
    setState(() => _isLoadingSlot = true);
    _slotOrariCalcolati.clear();
    _appuntamentiOccupati.clear();

    try {
      final String dataStr = _formattaData(_dataSelezionata);

      final appuntamentiPresi = await FirebaseFirestore.instance
          .collection('appointments')
          .where('date', isEqualTo: dataStr)
          .where('barberId', isEqualTo: _barbiereSelezionatoId)
          .get(const GetOptions(source: Source.server));

      for (var doc in appuntamentiPresi.docs) {
        final datiApp = doc.data();
        if (datiApp.containsKey('slot') && datiApp['slot'] != null) {
          int inizioMinuti = _minutiDaStringa(datiApp['slot']);

          int durataAppuntamento = 30;
          if (datiApp.containsKey('duration')) {
            durataAppuntamento = datiApp['duration'];
          } else if (datiApp.containsKey('totalDuration')) {
            durataAppuntamento = datiApp['totalDuration'];
          } else if (datiApp.containsKey('services_duration')) {
            durataAppuntamento = datiApp['services_duration'];
          }

          int fineMinuti = inizioMinuti + durataAppuntamento;

          _appuntamentiOccupati.add(
              IntervalloAppuntamento(inizio: inizioMinuti, fine: fineMinuti)
          );
        }
      }

      // Ordiniamo gli appuntamenti per orario di inizio per rendere i controlli fluidi
      _appuntamentiOccupati.sort((a, b) => a.inizio.compareTo(b.inizio));

      final barberEx = await FirebaseFirestore.instance
          .collection('barber_exceptions')
          .doc("${dataStr}_$_barbiereSelezionatoId")
          .get(const GetOptions(source: Source.server));

      final dataEx = barberEx.exists ? barberEx.data() : null;

      if (dataEx != null && dataEx['type'] == 'assente') {
        setState(() => _isLoadingSlot = false);
        return;
      }

      String nomeGiorno = _giorniSettimana[_dataSelezionata.weekday % 7];
      var orariGiorno = _orariNegozioBase[nomeGiorno];

      if (orariGiorno != null && orariGiorno['isAperto'] == true) {
        if (orariGiorno.containsKey('mattina')) {
          _calcolaSlotPerFascia(orariGiorno['mattina'], dataEx);
        }
        if (orariGiorno.containsKey('pomeriggio')) {
          _calcolaSlotPerFascia(orariGiorno['pomeriggio'], dataEx);
        }
      }
    } catch (e) {
      debugPrint("Errore aggiornamento slot (probabilmente offline): $e");
      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Errore di connessione nel caricamento degli orari.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } finally {
      setState(() => _isLoadingSlot = false);
    }
  }

  // CORREZIONE GENERAZIONE FLUIDA: Calcola gli incastri dinamici al minuto per evitare buchi temporali
  void _calcolaSlotPerFascia(Map<String, dynamic> fasciaData, Map<String, dynamic>? dataEx) {
    int start = _minutiDaStringa(fasciaData['apertura'] ?? "09:00");
    int end = _minutiDaStringa(fasciaData['chiusura'] ?? "13:00");

    final adesso = DateTime.now();
    final bool isOggi = _formattaData(_dataSelezionata) == _formattaData(adesso);
    final int minutiAttuali = (adesso.hour * 60) + adesso.minute;

    // Scansioniamo la giornata con una granularità di 10 minuti per intercettare gli incastri perfetti
    for (int m = start; m + widget.servizioDurata <= end; m += 10) {
      if (isOggi && m <= minutiAttuali) {
        continue;
      }

      int ora = m ~/ 60;
      if (dataEx != null && dataEx['type'] == 'mezza_giornata') {
        if (dataEx['fascia'] == 'mattina' && ora >= 13) continue;
        if (dataEx['fascia'] == 'pomeriggio' && ora < 13) continue;
      }

      // 1. Verifichiamo se lo slot si scontra (overlapping) con appuntamenti esistenti
      int fineSlot = m + widget.servizioDurata;
      bool siSovrappone = false;
      for (var app in _appuntamentiOccupati) {
        if (m < app.fine && fineSlot > app.inizio) {
          siSovrappone = true;
          break;
        }
      }
      if (siSovrappone) continue;

      // 2. LOGICA DI INCASTRO FLUIDO: Lo slot deve essere l'apertura, seguire un appuntamento,
      // oppure rispettare il passo naturale del servizio rispetto all'ultimo blocco libero.
      // MODIFICATO: Corretto il nome della variabile rimuovendo l'accento iniziale per gli standard Dart
      bool eIncastroValido = (m == start); // Condizione 1: È l'apertura del turno

      if (!eIncastroValido) {
        // Condizione 2: Si attacca perfettamente alla fine di un appuntamento precedente
        for (var app in _appuntamentiOccupati) {
          if (m == app.fine) {
            eIncastroValido = true;
            break;
          }
        }
      }

      if (!eIncastroValido) {
        // Condizione 3: Calcoliamo lo spazio dall'ultimo vincolo temporale precedente (apertura o fine appuntamento)
        int ultimoPuntoRiferimento = start;
        for (var app in _appuntamentiOccupati) {
          if (app.fine <= m) {
            ultimoPuntoRiferimento = app.fine;
          }
        }
        // Se lo spazio vuoto è un multiplo esatto della durata del servizio, lo slot è coerente
        if ((m - ultimoPuntoRiferimento) % widget.servizioDurata == 0) {
          eIncastroValido = true;
        }
      }

      if (eIncastroValido) {
        int min = m % 60;
        _slotOrariCalcolati.add("${ora.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}");
      }
    }
  }

  int _minutiDaStringa(String s) => int.parse(s.split(':')[0]) * 60 + int.parse(s.split(':')[1]);
  String _formattaData(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  bool _isChiuso(DateTime d) {
    if (_eccezioniCalendario[_formattaData(d)]?['status'] == 'chiuso') return true;
    return _orariNegozioBase[_giorniSettimana[d.weekday % 7]]?['isAperto'] == false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingConfig) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE2B13C))),
      );
    }

    final String dataStr = _formattaData(_dataSelezionata);
    final bool giornoCorrenteChiuso = _isChiuso(_dataSelezionata);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Scegli Data e Barber', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF164638),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. SELEZIONE GIORNO
            const Padding(
              padding: EdgeInsets.only(left: 20.0, top: 16, bottom: 8),
              child: Text('Seleziona il giorno:', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 14,
                itemBuilder: (ctx, i) {
                  DateTime d = DateTime.now().add(Duration(days: i));
                  bool isChiusoGiorno = _isChiuso(d);
                  bool sel = _formattaData(d) == dataStr;

                  final List<String> settimanaAbbr = ['Dom', 'Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab'];
                  String nomeGiorno = settimanaAbbr[d.weekday % 7];

                  return GestureDetector(
                    onTap: isChiusoGiorno || _isSaving
                        ? null
                        : () {
                      setState(() {
                        _dataSelezionata = d;
                        _orarioSelezionato = null;
                      });
                      _aggiornaSlotOrari();
                    },
                    child: Container(
                      width: 65,
                      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: sel
                            ? const Color(0xFFE2B13C)
                            : (isChiusoGiorno ? Colors.red.withAlpha(51) : const Color(0xFF1C2824)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isChiusoGiorno ? Colors.red.shade800 : Colors.transparent,
                          width: isChiusoGiorno ? 1.5 : 0,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(nomeGiorno, style: TextStyle(color: isChiusoGiorno ? Colors.red.shade300 : (sel ? Colors.black : Colors.grey), fontSize: 13)),
                          const SizedBox(height: 4),
                          Text('${d.day}', style: TextStyle(color: isChiusoGiorno ? Colors.red.shade300 : (sel ? Colors.black : Colors.white), fontSize: 18, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // 2. SELEZIONE OPERATORE
            const Padding(
              padding: EdgeInsets.only(left: 20.0, top: 16, bottom: 8),
              child: Text('Scegli chi ti guiderà:', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 110,
              child: giornoCorrenteChiuso
                  ? const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.0),
                  child: Text(
                    'Il salone è chiuso in questa data. Scegli un giorno attivo sopra.',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
                  : StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('barbers').snapshots(),
                builder: (ctx, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFE2B13C)));
                  final barbieri = snap.data!.docs;

                  return ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: barbieri.length,
                    itemBuilder: (context, index) {
                      var doc = barbieri[index];
                      var data = doc.data() as Map<String, dynamic>;
                      final id = doc.id;
                      final nome = data['name'] ?? 'Staff';
                      bool sel = _barbiereSelezionatoId == id;

                      return GestureDetector(
                        onTap: _isSaving
                            ? null
                            : () {
                          setState(() {
                            _barbiereSelezionatoId = id;
                            _barbiereSelezionatoNome = nome;
                            _orarioSelezionato = null;
                          });
                          _aggiornaSlotOrari();
                        },
                        child: Container(
                          width: 100,
                          margin: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C2824),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: sel ? const Color(0xFFE2B13C) : Colors.transparent, width: 2),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                backgroundColor: sel ? const Color(0xFFE2B13C) : const Color(0xFF164638),
                                child: Icon(Icons.person, color: sel ? Colors.black : Colors.white),
                              ),
                              const SizedBox(height: 8),
                              Text(nome, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // 3. GRIGLIA ORARI DINAMICI
            const Padding(
              padding: EdgeInsets.only(left: 20.0, top: 20, bottom: 8),
              child: Text('Orari disponibili:', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: giornoCorrenteChiuso
                  ? const SizedBox.shrink()
                  : (_barbiereSelezionatoId == null
                  ? const Center(child: Text('Seleziona un operatore per vedere gli orari.', style: TextStyle(color: Colors.grey)))
                  : (_isLoadingSlot
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFE2B13C)))
                  : (_slotOrariCalcolati.isEmpty
                  ? const Center(child: Text('Nessun orario disponibile o operatore fuori turno.', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)))
                  : GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  // MODIFICATO: Passato da 4 a 3 colonne per dare molto più spazio orizzontale
                  crossAxisCount: 3,
                  mainAxisSpacing: 12, // Leggermente aumentato lo spazio verticale tra i bottoni
                  crossAxisSpacing: 12, // Leggermente aumentato lo spazio orizzontale
                  // MODIFICATO: Ridotto il ratio per rendere i bottoni più alti e cicciotti
                  childAspectRatio: 1.8,
                ),
                itemCount: _slotOrariCalcolati.length,
                itemBuilder: (context, index) {
                  final ora = _slotOrariCalcolati[index];
                  bool sel = _orarioSelezionato == ora;

                  return GestureDetector(
                    onTap: _isSaving ? null : () => setState(() => _orarioSelezionato = ora),
                    child: Container(
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFFE2B13C) : const Color(0xFF1C2824),
                        borderRadius: BorderRadius.circular(14), // Arrotondato un po' di più per estetica
                        border: Border.all(
                          color: sel ? Colors.white : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          ora,
                          style: TextStyle(
                            color: sel ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            // MODIFICATO: Aumentato il font da 14 a 18 per una leggibilità perfetta
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              )))),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(left: 20.0, right: 20.0, bottom: 16.0),
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE2B13C),
              minimumSize: const Size.fromHeight(54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: (_barbiereSelezionatoId == null || _orarioSelezionato == null || giornoCorrenteChiuso || _isSaving)
                ? null
                : () {
              showDialog(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Conferma Prenotazione'),
                  content: Text('Servizio: ${widget.servizioNome}\nData: $dataStr\nOra: $_orarioSelezionato\nCon: $_barbiereSelezionatoNome'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Modifica'),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(dialogContext);

                        setState(() => _isSaving = true);

                        try {
                          await FirebaseFirestore.instance
                              .collection('settings')
                              .doc('orari_negozio')
                              .get(const GetOptions(source: Source.server));

                          final user = FirebaseAuth.instance.currentUser;
                          if (user == null) throw 'Utente non autenticato';

                          String nomeRealeCliente = "Cliente";

                          final userDoc = await FirebaseFirestore.instance
                              .collection('users')
                              .doc(user.uid)
                              .get(const GetOptions(source: Source.server));

                          if (userDoc.exists && userDoc.data() != null) {
                            nomeRealeCliente = userDoc.data()?['name'] ?? user.displayName ?? "Cliente";
                          }

                          int prezzoStimato = 15;

                          final docRef = await FirebaseFirestore.instance.collection('appointments').add({
                            'date': dataStr,
                            'slot': _orarioSelezionato,
                            'duration': widget.servizioDurata,
                            'barberId': _barbiereSelezionatoId,
                            'barberName': _barbiereSelezionatoNome,
                            'userId': user.uid,
                            'userName': nomeRealeCliente,
                            'userEmail': user.email ?? 'Cliente anonimo',
                            'services': [widget.servizioNome],
                            'totalPrice': prezzoStimato,
                            'createdAt': FieldValue.serverTimestamp(),
                          });

                          try {
                            await NotificationService().pianificaNotificaAppuntamento(
                              idNotifica: docRef.id.hashCode,
                              dataStr: dataStr,
                              slotStr: _orarioSelezionato!,
                              servizi: widget.servizioNome,
                            );
                          } catch (e) {
                            debugPrint("Errore durante la pianificazione locale del promemoria: $e");
                          }

                          if (!context.mounted) return;

                          ScaffoldMessenger.of(context).clearSnackBars();

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Prenotazione effettuata con successo!'),
                              backgroundColor: Colors.green,
                            ),
                          );

                          Navigator.of(context).popUntil((route) => route.isFirst);

                        } catch (e) {
                          if (!context.mounted) return;
                          setState(() => _isSaving = false);

                          ScaffoldMessenger.of(context).clearSnackBars();

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Errore di connessione. Impossibile salvare la prenotazione offline.'),
                              backgroundColor: Colors.red,
                              duration: Duration(seconds: 4),
                            ),
                          );
                        }
                      },
                      child: const Text('Conferma', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
            },
            child: _isSaving
                ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(color: Color(0xFF121212), strokeWidth: 2.5),
            )
                : const Text('Conferma Prenotazione', style: TextStyle(color: Color(0xFF121212), fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}