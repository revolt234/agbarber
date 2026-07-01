import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';

class PrenotazioneDataScreen extends StatefulWidget {
  final String servizioId;
  final String servizioNome;
  final int servizioDurata;
  final double servizioPrezzo;
  final DateTime dataInizialeSelezionata;

  const PrenotazioneDataScreen({
    super.key,
    required this.servizioId,
    required this.servizioNome,
    required this.servizioDurata,
    required this.servizioPrezzo,
    required this.dataInizialeSelezionata,
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
  late DateTime _dataSelezionata;
  String? _barbiereSelezionatoId;
  String? _barbiereSelezionatoNome;
  String? _orarioSelezionato;

  bool _isLoadingSlot = false;
  bool _isLoadingConfig = true;
  bool _isSaving = false;
  bool _isPreloadingGiorni = false;

  Map<String, dynamic> _orariNegozioBase = {};
  Map<String, dynamic> _eccezioniCalendario = {};
  List<String> _slotOrariCalcolati = [];
  List<IntervalloAppuntamento> _appuntamentiOccupati = [];

  // Striscia dei giorni intelligenti filtrati e relativo controller per l'autocentramento
  List<DateTime> _giorniFiltratiVisibili = [];
  final Map<String, int> _conteggioSlotPerGiorno = {};
  final ScrollController _scrollControllerGiorni = ScrollController();

  final List<String> _giorniSettimana = [
    'domenica', 'lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato'
  ];

  @override
  void initState() {
    super.initState();
    _dataSelezionata = widget.dataInizialeSelezionata;
    _inizializzaDati();
  }

  @override
  void dispose() {
    _scrollControllerGiorni.dispose();
    super.dispose();
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

      await _precaricaDisponibilitaStrisciaGiorni();

      setState(() => _isLoadingConfig = false);

      // Centra il giorno selezionato inizialmente dopo il rendering del primo frame grafico
      WidgetsBinding.instance.addPostFrameCallback((_) => _centraGiornoSelezionato(animato: false));
    } catch (e) {
      debugPrint("Errore inizializzazione: $e");
      setState(() => _isLoadingConfig = false);
    }
  }

  void _centraGiornoSelezionato({bool animato = true}) {
    if (!_scrollControllerGiorni.hasClients || _giorniFiltratiVisibili.isEmpty) return;

    String targetStr = _formattaData(_dataSelezionata);
    int index = _giorniFiltratiVisibili.indexWhere((g) => _formattaData(g) == targetStr);
    if (index == -1) return;

    // Ogni card ha un width fisso di 140 ed un margin horizontal di 6 (quindi occupa 140 + 6 + 6 = 152 pixel in totale)
    const double larghezzaElemento = 152.0;
    final double larghezzaSchermo = MediaQuery.of(context).size.width;

    // Calcolo della coordinata per fare in modo che l'elemento si posizioni al centro esatto dello schermo
    double offsetDestinazione = (index * larghezzaElemento) - (larghezzaSchermo / 2) + (larghezzaElemento / 2) + 12; // +12 tiene conto del padding iniziale

    // Vincola l'offset entro i limiti di scorrimento minimi e massimi possibili
    if (offsetDestinazione < 0) offsetDestinazione = 0;
    if (offsetDestinazione > _scrollControllerGiorni.position.maxScrollExtent) {
      offsetDestinazione = _scrollControllerGiorni.position.maxScrollExtent;
    }

    if (animato) {
      _scrollControllerGiorni.animateTo(
        offsetDestinazione,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _scrollControllerGiorni.jumpTo(offsetDestinazione);
    }
  }

  Future<void> _precaricaDisponibilitaStrisciaGiorni() async {
    setState(() => _isPreloadingGiorni = true);
    _conteggioSlotPerGiorno.clear();
    _giorniFiltratiVisibili.clear();

    try {
      final barbersSnap = await FirebaseFirestore.instance.collection('barbers').get();
      final barbieri = barbersSnap.docs;

      List<DateTime> tuttiIGiorniPotenziali = [];
      DateTime oggi = DateTime.now();
      DateTime oggiMezzanotte = DateTime(oggi.year, oggi.month, oggi.day);

      // MODIFICATO: Allarghiamo il raggio di generazione (es. 25 giorni prima e 35 giorni dopo)
      // per essere sicuri di trovare abbastanza giorni validi (aperti e non pieni) anche nei mesi futuri.
      DateTime dataInizioCalcolo = widget.dataInizialeSelezionata.subtract(const Duration(days: 25));

      for (int i = 0; i < 60; i++) {
        DateTime giornoRiferimento = dataInizioCalcolo.add(Duration(days: i));

        if (giornoRiferimento.isBefore(oggiMezzanotte)) {
          continue;
        }
        tuttiIGiorniPotenziali.add(giornoRiferimento);
      }

      Map<String, int> contatoriTemporanei = {};
      List<Future<void>> compitiDiCaricamento = [];

      for (var giorno in tuttiIGiorniPotenziali) {
        String dataStr = _formattaData(giorno);

        if (_isChiuso(giorno)) {
          contatoriTemporanei[dataStr] = 0;
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

            final bool haAperturaStraordinaria = _eccezioniCalendario[dataStr]?['status'] == 'aperto';
            if (haAperturaStraordinaria) {
              orariGiorno = {
                'isAperto': true,
                'mattina': _eccezioniCalendario[dataStr]?['mattina'],
                'pomeriggio': _eccezioniCalendario[dataStr]?['pomeriggio'],
              };
            }

            if (orariGiorno != null && orariGiorno['isAperto'] == true) {
              if (orariGiorno.containsKey('mattina') && orariGiorno['mattina'] != null) {
                slotLiberiTotaliGiorno += _contaSlotLiberiFascia(orariGiorno['mattina'], dataEx, giorno, occupatiBarbiere);
              }
              if (orariGiorno.containsKey('pomeriggio') && orariGiorno['pomeriggio'] != null) {
                slotLiberiTotaliGiorno += _contaSlotLiberiFascia(orariGiorno['pomeriggio'], dataEx, giorno, occupatiBarbiere);
              }
            }
          }

          contatoriTemporanei[dataStr] = slotLiberiTotaliGiorno;
        }());
      }

      await Future.wait(compitiDiCaricamento);
      _conteggioSlotPerGiorno.addAll(contatoriTemporanei);

      // Lista "pulita" contenente SOLO i giorni effettivamente aperti e con posti disponibili
      List<DateTime> giorniApertiEDisponibili = tuttiIGiorniPotenziali.where((g) {
        String key = _formattaData(g);
        bool chiuso = _isChiuso(g);
        int posti = _conteggioSlotPerGiorno[key] ?? 0;
        return !chiuso && posti > 0;
      }).toList();

      String dataTargetStr = _formattaData(_dataSelezionata);
      int indexTarget = giorniApertiEDisponibili.indexWhere((g) => _formattaData(g) == dataTargetStr);

      if (indexTarget != -1) {
        // MODIFICATO: Prendiamo ESATTAMENTE fino a 7 elementi validi precedenti (a sinistra)
        int startIdx = indexTarget - 7;
        if (startIdx < 0) startIdx = 0;

        // MODIFICATO: Prendiamo ESATTAMENTE fino a 7 elementi validi successivi (a destra)
        int endIdx = indexTarget + 7;
        if (endIdx >= giorniApertiEDisponibili.length) endIdx = giorniApertiEDisponibili.length - 1;

        // Popoliamo la striscia finale prendendo l'intervallo esatto di elementi validi
        for (int k = startIdx; k <= endIdx; k++) {
          _giorniFiltratiVisibili.add(giorniApertiEDisponibili[k]);
        }
      } else {
        _giorniFiltratiVisibili = giorniApertiEDisponibili.take(14).toList();
      }

    } catch (e) {
      debugPrint("Errore nel filtraggio intelligente dei giorni: $e");
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

      final bool haAperturaStraordinaria = _eccezioniCalendario[dataStr]?['status'] == 'aperto';
      if (haAperturaStraordinaria) {
        orariGiorno = {
          'isAperto': true,
          'mattina': _eccezioniCalendario[dataStr]?['mattina'],
          'pomeriggio': _eccezioniCalendario[dataStr]?['pomeriggio'],
        };
      }

      if (orariGiorno != null && orariGiorno['isAperto'] == true) {
        if (orariGiorno.containsKey('mattina') && orariGiorno['mattina'] != null) {
          _calcolaSlotPerFascia(orariGiorno['mattina'], dataEx);
        }
        if (orariGiorno.containsKey('pomeriggio') && orariGiorno['pomeriggio'] != null) {
          _calcolaSlotPerFascia(orariGiorno['pomeriggio'], dataEx);
        }
      }
    } catch (e) {
      debugPrint("Errore aggiornamento slot: $e");
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

  bool _isChiuso(DateTime d) {
    final stringaGiorno = _formattaData(d);
    if (_eccezioniCalendario.containsKey(stringaGiorno)) {
      return _eccezioniCalendario[stringaGiorno]?['status'] == 'chiuso';
    }
    return _orariNegozioBase[_giorniSettimana[d.weekday % 7]]?['isAperto'] == false;
  }

  int _minutiDaStringa(String s) => int.parse(s.split(':')[0]) * 60 + int.parse(s.split(':')[1]);
  String _formattaData(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  @override
  Widget build(BuildContext context) {
    if (_isLoadingConfig || _isPreloadingGiorni) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(child: CircularProgressIndicator(color: Color(0xFFE2B13C))),
      );
    }

    final String dataStr = _formattaData(_dataSelezionata);
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final Color coloreSfondoSchermata = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF4F6F5);
    final Color coloreTestoTitoli = isDarkMode ? Colors.white : Colors.black87;
    final Color coloreSfondoCardSpenta = isDarkMode ? const Color(0xFF1C2824) : Colors.white;
    final Color coloreTestoCardSpenta = isDarkMode ? Colors.white : Colors.black87;

    final Color coloreSfondoButtonGiorno = isDarkMode ? const Color(0xFF1C1C1E) : Colors.white;
    final Color coloreTestoPrimarioGiorno = isDarkMode ? Colors.white : Colors.black;
    final Color coloreTestoSecondarioGiorno = isDarkMode ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: coloreSfondoSchermata,
      appBar: AppBar(
        title: const Text('Scegli un operatore', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: const Color(0xFF164638),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // STRISCIA GIORNI ORIZZONTALE ADATTIVA E INTELLIGENTE
            SizedBox(
              height: 105,
              child: ListView.builder(
                controller: _scrollControllerGiorni, // Collegato per gestire il centraggio automatico
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                itemCount: _giorniFiltratiVisibili.length,
                itemBuilder: (context, i) {
                  DateTime d = _giorniFiltratiVisibili[i];
                  String loopDataStr = _formattaData(d);
                  bool sel = loopDataStr == dataStr;

                  int slotDisponibili = _conteggioSlotPerGiorno[loopDataStr] ?? 0;

                  Color colorePallino = const Color(0xFF52C47A);
                  if (slotDisponibili <= 10) {
                    colorePallino = Colors.red;
                  } else if (slotDisponibili <= 15) {
                    colorePallino = const Color(0xFFE2B13C);
                  }

                  String giornoMeseTesto = DateFormat('dd MMM', 'it_IT').format(d).toLowerCase();
                  String giornoSettimanaTesto = DateFormat('EEEE', 'it_IT').format(d).toLowerCase().substring(0, 3);

                  return GestureDetector(
                    onTap: _isSaving
                        ? null
                        : () {
                      setState(() {
                        _dataSelezionata = d;
                        _orarioSelezionato = null;
                      });
                      _aggiornaSlotOrari();
                      _centraGiornoSelezionato(); // Centra l'elemento cliccato dall'utente
                    },
                    child: Container(
                      width: 140,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        color: coloreSfondoButtonGiorno,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: sel ? const Color(0xFFE2B13C) : Colors.transparent,
                          width: sel ? 3.0 : 0,
                        ),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withAlpha(20), blurRadius: 4, offset: const Offset(0, 2))
                        ],
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            giornoMeseTesto,
                            style: TextStyle(color: coloreTestoPrimarioGiorno, fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: colorePallino,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0x3D000000),
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                giornoSettimanaTesto,
                                style: TextStyle(color: coloreTestoSecondarioGiorno, fontSize: 15, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // 1. SELEZIONE OPERATORE
            Padding(
              padding: const EdgeInsets.only(left: 20.0, top: 12, bottom: 8),
              child: Text('Scegli chi ti guiderà:', style: TextStyle(color: coloreTestoTitoli, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 110,
              child: StreamBuilder<QuerySnapshot>(
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
                            color: sel ? const Color(0xFFE2B13C).withAlpha(38) : coloreSfondoCardSpenta,
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

            // 2. GRIGLIA ORARI DINAMICI
            Padding(
              padding: const EdgeInsets.only(left: 20.0, top: 16, bottom: 8),
              child: Text('Orari disponibili:', style: TextStyle(color: coloreTestoTitoli, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: _barbiereSelezionatoId == null
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
              ))),
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
            onPressed: (_barbiereSelezionatoId == null || _orarioSelezionato == null || _isSaving)
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
                              'totalPrice': widget.servizioPrezzo,
                              'createdAt': FieldValue.serverTimestamp(),
                            });

                            return nuovoDocRef.id;
                          });

                          if (risultatoIncastroId == null) throw 'SLOT_OCCUPATO';

                          try {
                            await NotificationService().pianificaNotificaAppuntamento(
                              idNotifica: risultatoIncastroId.hashCode,
                              dataStr: dataStr,
                              slotStr: _orarioSelezionato!,
                              servizi: widget.servizioNome,
                            );
                          } catch (e) {
                            debugPrint("Errore notifiche: $e");
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
                      child: const Text('Conferma Prenotazione', style: TextStyle(fontWeight: FontWeight.bold)),
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