import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';

class PrenotazioneDataScreen extends StatefulWidget {
  final String servizioId;
  final String servizioNome;
  final int servizioDurata;
  final double servizioPrezzo; // AGGIUNTO: Parametro per ricevere il prezzo reale dalla schermata precedente

  const PrenotazioneDataScreen({
    super.key,
    required this.servizioId,
    required this.servizioNome,
    required this.servizioDurata,
    required this.servizioPrezzo, // AGGIUNTO: Richiesto nel costruttore
  });

  @override
  State<PrenotazioneDataScreen> createState() => _PrenotazioneDataScreenState();
}

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

  final Map<String, int> _conteggioSlotPerGiorno = {};
  bool _isPreloadingGiorni = false;

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

      await _precaricaDisponibilitaGiorni();

      setState(() => _isLoadingConfig = false);
    } catch (e) {
      debugPrint("Errore inizializzazione: $e");
      setState(() => _isLoadingConfig = false);
    }
  }

  Future<void> _precaricaDisponibilitaGiorni() async {
    setState(() => _isPreloadingGiorni = true);

    try {
      final barbersSnap = await FirebaseFirestore.instance.collection('barbers').get();
      final barbieri = barbersSnap.docs;

      List<Future<void>> compitiDiCaricamento = [];

      for (int i = 0; i < 14; i++) {
        DateTime giorno = DateTime.now().add(Duration(days: i));
        String dataStr = _formattaData(giorno);

        if (_isChiuso(giorno)) {
          _conteggioSlotPerGiorno[dataStr] = 0;
          continue;
        }

        compitiDiCaricamento.add(() async {
          int slotLiberiTotaliGiorno = 0;

          final appuntamentiGiornoSnap = await FirebaseFirestore.instance
              .collection('appointments')
              .where('date', isEqualTo: dataStr)
              .get(const GetOptions(source: Source.server));

          List<Future<DocumentSnapshot>> richiesteEccezioni = [];
          for (var bDoc in barbieri) {
            richiesteEccezioni.add(
                FirebaseFirestore.instance
                    .collection('barber_exceptions')
                    .doc("${dataStr}_${bDoc.id}")
                    .get(const GetOptions(source: Source.server))
            );
          }

          final risultatiEccezioni = await Future.wait(richiesteEccezioni);

          for (int index = 0; index < barbieri.length; index++) {
            final bDoc = barbieri[index];
            final String bId = bDoc.id;
            final barberExDoc = risultatiEccezioni[index];

            final dataEx = barberExDoc.exists ? barberExDoc.data() as Map<String, dynamic>? : null;
            if (dataEx != null && dataEx['type'] == 'assente') continue;

            List<IntervalloAppuntamento> occupatiBarbiere = [];
            for (var doc in appuntamentiGiornoSnap.docs) {
              final datiApp = doc.data();
              if (datiApp['barberId'] == bId && datiApp.containsKey('slot') && datiApp['slot'] != null) {
                int inizioMinuti = _minutiDaStringa(datiApp['slot']);
                int durataApp = datiApp['duration'] ?? datiApp['totalDuration'] ?? datiApp['services_duration'] ?? 30;
                occupatiBarbiere.add(IntervalloAppuntamento(inizio: inizioMinuti, fine: inizioMinuti + durataApp));
              }
            }

            String nomeGiorno = _giorniSettimana[giorno.weekday % 7];
            var orariGiorno = _orariNegozioBase[nomeGiorno];

            if (orariGiorno != null && orariGiorno['isAperto'] == true) {
              if (orariGiorno.containsKey('mattina')) {
                slotLiberiTotaliGiorno += _contaSlotLiberiFascia(orariGiorno['mattina'], dataEx, giorno, occupatiBarbiere);
              }
              if (orariGiorno.containsKey('pomeriggio')) {
                slotLiberiTotaliGiorno += _contaSlotLiberiFascia(orariGiorno['pomeriggio'], dataEx, giorno, occupatiBarbiere);
              }
            }
          }

          _conteggioSlotPerGiorno[dataStr] = slotLiberiTotaliGiorno;
        }());
      }

      await Future.wait(compitiDiCaricamento);

    } catch (e) {
      debugPrint("Errore nel precaricamento parallelo dei contatori giorni: $e");
    } finally {
      setState(() => _isPreloadingGiorni = false);
    }
  }

  int _contaSlotLiberiFascia(Map<String, dynamic> fasciaData, Map<String, dynamic>? dataEx, DateTime giorno, List<IntervalloAppuntamento> occupati) {
    int start = _minutiDaStringa(fasciaData['apertura'] ?? "09:00");
    int end = _minutiDaStringa(fasciaData['chiusura'] ?? "13:00");

    final adesso = DateTime.now();
    final bool isOggi = _formattaData(giorno) == _formattaData(adesso);
    final int minutesAttuali = (adesso.hour * 60) + adesso.minute;

    int contatore = 0;

    for (int m = start; m + widget.servizioDurata <= end; m += 10) {
      if (isOggi && m <= minutesAttuali) continue;

      int ora = m ~/ 60;
      if (dataEx != null && dataEx['type'] == 'mezza_giornata') {
        if (dataEx['fascia'] == 'mattina' && ora >= 13) continue;
        if (dataEx['fascia'] == 'pomeriggio' && ora < 13) continue;
      }

      int fineSlot = m + widget.servizioDurata;
      bool siSovrappone = false;
      for (var app in occupati) {
        if (m < app.fine && fineSlot > app.inizio) {
          siSovrappone = true;
          break;
        }
      }
      if (siSovrappone) continue;

      bool eIncastroValido = (m == start);
      if (!eIncastroValido) {
        for (var app in occupati) {
          if (m == app.fine) {
            eIncastroValido = true;
            break;
          }
        }
      }
      if (!eIncastroValido) {
        int ultimoPuntoRiferimento = start;
        for (var app in occupati) {
          if (app.fine <= m) {
            ultimoPuntoRiferimento = app.fine;
          }
        }
        if ((m - ultimoPuntoRiferimento) % widget.servizioDurata == 0) {
          eIncastroValido = true;
        }
      }

      if (eIncastroValido) contatore++;
    }
    return contatore;
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
          int durataAppuntamento = datiApp['duration'] ?? datiApp['totalDuration'] ?? datiApp['services_duration'] ?? 30;
          int fineMinuti = inizioMinuti + durataAppuntamento;

          _appuntamentiOccupati.add(IntervalloAppuntamento(inizio: inizioMinuti, fine: fineMinuti));
        }
      }

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

  void _calcolaSlotPerFascia(Map<String, dynamic> fasciaData, Map<String, dynamic>? dataEx) {
    int start = _minutiDaStringa(fasciaData['apertura'] ?? "09:00");
    int end = _minutiDaStringa(fasciaData['chiusura'] ?? "13:00");

    final adesso = DateTime.now();
    final bool isOggi = _formattaData(_dataSelezionata) == _formattaData(adesso);
    final int minutesAttuali = (adesso.hour * 60) + adesso.minute;

    for (int m = start; m + widget.servizioDurata <= end; m += 10) {
      if (isOggi && m <= minutesAttuali) continue;

      int ora = m ~/ 60;
      if (dataEx != null && dataEx['type'] == 'mezza_giornata') {
        if (dataEx['fascia'] == 'mattina' && ora >= 13) continue;
        if (dataEx['fascia'] == 'pomeriggio' && ora < 13) continue;
      }

      int fineSlot = m + widget.servizioDurata;
      bool siSovrappone = false;
      for (var app in _appuntamentiOccupati) {
        if (m < app.fine && fineSlot > app.inizio) {
          siSovrappone = true;
          break;
        }
      }
      if (siSovrappone) continue;

      bool eIncastroValido = (m == start);

      if (!eIncastroValido) {
        for (var app in _appuntamentiOccupati) {
          if (m == app.fine) {
            eIncastroValido = true;
            break;
          }
        }
      }

      if (!eIncastroValido) {
        int ultimoPuntoRiferimento = start;
        for (var app in _appuntamentiOccupati) {
          if (app.fine <= m) {
            ultimoPuntoRiferimento = app.fine;
          }
        }
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
    if (_isLoadingConfig || _isPreloadingGiorni) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE2B13C))),
      );
    }

    final String dataStr = _formattaData(_dataSelezionata);
    final bool giornoCorrenteChiuso = _isChiuso(_dataSelezionata);
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Colori adattivi
    final Color coloreSfondoSchermata = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF4F6F5);
    final Color coloreTestoTitoli = isDarkMode ? Colors.white : Colors.black87;
    final Color coloreSfondoCardSpenta = isDarkMode ? const Color(0xFF1C2824) : Colors.white;
    final Color coloreTestoCardSpenta = isDarkMode ? Colors.white : Colors.black87;
    // ----------------------------

    return Scaffold(
      backgroundColor: coloreSfondoSchermata,
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
            Padding(
              padding: const EdgeInsets.only(left: 20.0, top: 16, bottom: 8),
              child: Text('Seleziona il giorno:', style: TextStyle(color: coloreTestoTitoli, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 95,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 14,
                itemBuilder: (ctx, i) {
                  DateTime d = DateTime.now().add(Duration(days: i));
                  String loopDataStr = _formattaData(d);
                  bool isChiusoGiorno = _isChiuso(d);
                  bool sel = loopDataStr == dataStr;

                  int slotDisponibili = _conteggioSlotPerGiorno[loopDataStr] ?? 0;
                  bool isSoldOut = !isChiusoGiorno && slotDisponibili == 0;

                  Color coloreSfondoCard;
                  if (isChiusoGiorno) {
                    coloreSfondoCard = Colors.red.withAlpha(51);
                  } else if (isSoldOut) {
                    coloreSfondoCard = const Color(0xFF0A0A0A);
                  } else if (slotDisponibili > 15) {
                    coloreSfondoCard = const Color(0xFF1B4D2A);
                  } else if (slotDisponibili > 10 && slotDisponibili <= 15) {
                    coloreSfondoCard = const Color(0xFF8A7300);
                  } else {
                    coloreSfondoCard = const Color(0xFFB25E00);
                  }

                  final List<String> settimanaAbbr = ['Dom', 'Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab'];
                  String nomeGiorno = settimanaAbbr[d.weekday % 7];

                  return GestureDetector(
                    onTap: isChiusoGiorno || isSoldOut || _isSaving
                        ? null
                        : () {
                      setState(() {
                        _dataSelezionata = d;
                        _orarioSelezionato = null;
                      });
                      _aggiornaSlotOrari();
                    },
                    child: Container(
                      width: 70,
                      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFFE2B13C) : coloreSfondoCard,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: sel
                              ? Colors.white
                              : (isSoldOut ? Colors.red.shade900 : (isChiusoGiorno ? Colors.red.shade800 : Colors.transparent)),
                          width: sel || isSoldOut || isChiusoGiorno ? 1.5 : 0,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                              nomeGiorno,
                              style: TextStyle(
                                  color: sel ? Colors.black : (isChiusoGiorno || isSoldOut ? Colors.red.shade300 : (isDarkMode ? Colors.white70 : Colors.black54)),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500
                              )
                          ),
                          const SizedBox(height: 2),
                          Text(
                              '${d.day}',
                              style: TextStyle(
                                  color: sel ? Colors.black : (isChiusoGiorno || isSoldOut ? Colors.red.shade300 : (isDarkMode ? Colors.white : Colors.black87)),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold
                              )
                          ),
                          if (isSoldOut) ...[
                            const SizedBox(height: 2),
                            const Text(
                              'SOLD OUT',
                              style: TextStyle(color: Colors.red, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.4),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // 2. SELEZIONE OPERATORE
            Padding(
              padding: const EdgeInsets.only(left: 20.0, top: 16, bottom: 8),
              child: Text('Scegli chi ti guiderà:', style: TextStyle(color: coloreTestoTitoli, fontSize: 14, fontWeight: FontWeight.bold)),
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
                            color: sel ? const Color(0xFFE2B13C).withValues(alpha: 0.15) : coloreSfondoCardSpenta,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: sel ? const Color(0xFFE2B13C) : (isDarkMode ? Colors.transparent : Colors.grey.shade300),
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                backgroundColor: sel ? const Color(0xFFE2B13C) : const Color(0xFF164638),
                                child: Icon(Icons.person, color: sel ? Colors.black : Colors.white),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                nome,
                                style: TextStyle(
                                  color: sel ? const Color(0xFFE2B13C) : coloreTestoCardSpenta,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
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

            // 3. GRIGLIA ORARI DINAMICI
            Padding(
              padding: const EdgeInsets.only(left: 20.0, top: 20, bottom: 8),
              child: Text('Orari disponibili:', style: TextStyle(color: coloreTestoTitoli, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: giornoCorrenteChiuso
                  ? const SizedBox.shrink()
                  : (_barbiereSelezionatoId == null
                  ? Center(child: Text('Seleziona un operatore per vedere gli orari.', style: TextStyle(color: isDarkMode ? Colors.grey : Colors.black54)))
                  : (_isLoadingSlot
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFE2B13C)))
                  : (_slotOrariCalcolati.isEmpty
                  ? const Center(child: Text('Nessun orario disponibile o operatore fuori turno.', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)))
                  : GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
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
                        color: sel ? const Color(0xFFE2B13C) : coloreSfondoCardSpenta,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: sel ? Colors.white : (isDarkMode ? Colors.transparent : Colors.grey.shade300),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          ora,
                          style: TextStyle(
                            color: sel ? Colors.black : coloreTestoCardSpenta,
                            fontWeight: FontWeight.bold,
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
                  backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                  title: Text('Conferma Prenotazione', style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87)),
                  content: Text(
                    'Servizio: ${widget.servizioNome}\nData: $dataStr\nOra: $_orarioSelezionato\nCon: $_barbiereSelezionatoNome',
                    style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black87),
                  ),
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

                          int nuovoInizioMinuti = _minutiDaStringa(_orarioSelezionato!);
                          int nuovoFineMinuti = nuovoInizioMinuti + widget.servizioDurata;

                          String? risultatoIncastroId = await FirebaseFirestore.instance.runTransaction<String?>((transaction) async {
                            final querySnapshot = await FirebaseFirestore.instance
                                .collection('appointments')
                                .where('date', isEqualTo: dataStr)
                                .where('barberId', isEqualTo: _barbiereSelezionatoId)
                                .get(const GetOptions(source: Source.server));

                            for (var doc in querySnapshot.docs) {
                              final datiApp = doc.data();
                              if (datiApp.containsKey('slot') && datiApp['slot'] != null) {
                                int appInizio = _minutiDaStringa(datiApp['slot']);
                                int appDurata = datiApp['duration'] ?? datiApp['totalDuration'] ?? datiApp['services_duration'] ?? 30;
                                int appFine = appInizio + appDurata;

                                if (nuovoInizioMinuti < appFine && nuovoFineMinuti > appInizio) {
                                  return null;
                                }
                              }
                            }

                            final nuovoDocRef = FirebaseFirestore.instance.collection('appointments').doc();
                            transaction.set(nuovoDocRef, {
                              'date': dataStr,
                              'slot': _orarioSelezionato,
                              'duration': widget.servizioDurata,
                              'barberId': _barbiereSelezionatoId,
                              'barberName': _barbiereSelezionatoNome,
                              'userId': user.uid,
                              'userName': nomeRealeCliente,
                              'userEmail': user.email ?? 'Cliente anonimo',
                              'services': [widget.servizioNome],
                              // MODIFICA QUESTA RIGA: Rimuovi il .round() per salvare il prezzo esatto come double decimale
                              'totalPrice': widget.servizioPrezzo,
                              'createdAt': FieldValue.serverTimestamp(),
                            });

                            return nuovoDocRef.id; // Corretto con la "u": ora punta a 'nuovoDocRef'
                          });

                          if (risultatoIncastroId == null) {
                            throw 'SLOT_OCCUPATO';
                          }

                          try {
                            await NotificationService().pianificaNotificaAppuntamento(
                              idNotifica: risultatoIncastroId.hashCode,
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

                          String messaggioErrore = 'Errore di connessione. Impossibile salvare la prenotazione.';
                          Color coloreSfondo = Colors.red;

                          if (e == 'SLOT_OCCUPATO') {
                            messaggioErrore = 'Spiacenti! Questo orario è stato appena prenotato da un altro cliente. Scegli un altro slot.';
                            coloreSfondo = Colors.orange.shade900;
                            _aggiornaSlotOrari();
                          }

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(messaggioErrore),
                              backgroundColor: coloreSfondo,
                              duration: const Duration(seconds: 5),
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