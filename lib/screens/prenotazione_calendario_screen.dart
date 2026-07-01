import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'prenotazione_data_screen.dart'; // Importa il tuo screen originale aggiornato

class PrenotazioneCalendarioScreen extends StatefulWidget {
  final String servizioId;
  final String servizioNome;
  final int servizioDurata;
  final double servizioPrezzo;

  const PrenotazioneCalendarioScreen({
    super.key,
    required this.servizioId,
    required this.servizioNome,
    required this.servizioDurata,
    required this.servizioPrezzo,
  });

  @override
  State<PrenotazioneCalendarioScreen> createState() => _PrenotazioneCalendarioScreenState();
}

class _PrenotazioneCalendarioScreenState extends State<PrenotazioneCalendarioScreen> {
  late DateTime _meseCorrente;
  final List<DateTime> _mesiSelezionabili = [];
  int _indiceMeseSelezionato = 0;

  bool _isLoadingConfig = true;
  bool _isPreloadingGiorni = false;

  Map<String, dynamic> _orariNegozioBase = {};
  Map<String, dynamic> _eccezioniCalendario = {};
  final Map<String, int> _conteggioSlotPerGiorno = {};

  final List<String> _giorniSettimanaNome = [
    'domenica', 'lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato'
  ];

  // Variabili per la gestione del carosello dinamico nella legenda
  Timer? _timerLegenda;
  int _statoLegendaCorrente = 0;

  @override
  void initState() {
    super.initState();
    _preparaMesi();
    _meseCorrente = _mesiSelezionabili[_indiceMeseSelezionato];
    _inizializzaDati();
    _avviaTimerLegenda();
  }

  @override
  void dispose() {
    _timerLegenda?.cancel();
    super.dispose();
  }

  void _avviaTimerLegenda() {
    _timerLegenda = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        setState(() {
          _statoLegendaCorrente = (_statoLegendaCorrente + 1) % 4;
        });
      }
    });
  }

  void _preparaMesi() {
    DateTime adesso = DateTime.now();
    // Generiamo i 3 mesi successivi a partire da adesso gestendo correttamente l'avanzamento dell'anno
    for (int i = 0; i < 3; i++) {
      int annoVariato = adesso.year;
      int meseVariato = adesso.month + i;

      while (meseVariato > 12) {
        meseVariato -= 12;
        annoVariato += 1;
      }
      _mesiSelezionabili.add(DateTime(annoVariato, meseVariato, 1));
    }
  }

  Future<void> _inizializzaDati() async {
    setState(() => _isLoadingConfig = true);
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

      await _precaricaDisponibilitaMese();
    } catch (e) {
      debugPrint("Errore inizializzazione calendario: $e");
    } finally {
      setState(() => _isLoadingConfig = false);
    }
  }

  Future<void> _precaricaDisponibilitaMese() async {
    setState(() => _isPreloadingGiorni = true);
    _conteggioSlotPerGiorno.clear();

    try {
      final barbersSnap = await FirebaseFirestore.instance.collection('barbers').get();
      final barbieri = barbersSnap.docs;

      int anno = _meseCorrente.year;
      int mese = _meseCorrente.month;
      int giorniNelMese = DateTime(anno, mese + 1, 0).day;

      List<Future<void>> compitiDiCaricamento = [];

      for (int giornoId = 1; giornoId <= giorniNelMese; giornoId++) {
        DateTime giorno = DateTime(anno, mese, giornoId);
        String dataStr = _formattaData(giorno);

        // Se il giorno è antecedente a oggi, lo saltiamo
        if (giorno.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
          continue;
        }

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

            String nomeGiorno = _giorniSettimanaNome[giorno.weekday % 7];
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

          _conteggioSlotPerGiorno[dataStr] = slotLiberiTotaliGiorno;
        }());
      }

      await Future.wait(compitiDiCaricamento);
    } catch (e) {
      debugPrint("Errore nel calcolo degli slot mensili: $e");
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

  bool _isChiuso(DateTime d) {
    final stringaGiorno = _formattaData(d);
    if (_eccezioniCalendario.containsKey(stringaGiorno)) {
      return _eccezioniCalendario[stringaGiorno]?['status'] == 'chiuso';
    }
    return _orariNegozioBase[_giorniSettimanaNome[d.weekday % 7]]?['isAperto'] == false;
  }

  int _minutiDaStringa(String s) => int.parse(s.split(':')[0]) * 60 + int.parse(s.split(':')[1]);
  String _formattaData(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  @override
  Widget build(BuildContext context) {
    final int primoGiornoSettimana = DateTime(_meseCorrente.year, _meseCorrente.month, 1).weekday; // 1 = Lun, 7 = Dom
    final int giorniNelMese = DateTime(_meseCorrente.year, _meseCorrente.month + 1, 0).day;

    Color coloreBordoLegenda = Colors.transparent;
    Color coloreSfondoLegenda = Colors.white;
    String testoLegendaDinamico = '';

    if (_statoLegendaCorrente == 0) {
      coloreBordoLegenda = const Color(0xFF52C47A);
      testoLegendaDinamico = 'Salone libero';
    } else if (_statoLegendaCorrente == 1) {
      coloreBordoLegenda = const Color(0xFFE2B13C);
      testoLegendaDinamico = 'Salone mediamente affollato';
    } else if (_statoLegendaCorrente == 2) {
      coloreBordoLegenda = Colors.red;
      testoLegendaDinamico = 'Salone affollato';
    } else {
      coloreSfondoLegenda = Colors.black45;
      testoLegendaDinamico = 'Nessun posto disponibile (Sold out)';
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('Quando?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoadingConfig
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFE2B13C)))
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Seleziona un giorno per continuare',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  height: 55,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _mesiSelezionabili.length,
                    itemBuilder: (ctx, idx) {
                      final m = _mesiSelezionabili[idx];
                      bool isSel = _indiceMeseSelezionato == idx;
                      String nomeMese = DateFormat('MMMM', 'it_IT').format(m);

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _indiceMeseSelezionato = idx;
                            _meseCorrente = _mesiSelezionabili[idx];
                          });
                          _precaricaDisponibilitaMese();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: isSel ? const Color(0xFFE2B13C) : Colors.white,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Center(
                            child: Text(
                              nomeMese,
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              decoration: const BoxDecoration(
                color: Color(0xFF1C1C1E),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
              ),
              child: _isPreloadingGiorni
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFFE2B13C)))
                  : SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: const [
                        Text('LUN', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('MAR', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('MER', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('GIO', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('VEN', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('SAB', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text('DOM', style: TextStyle(color: Colors.white60, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: giorniNelMese + (primoGiornoSettimana - 1),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemBuilder: (context, index) {
                        int offset = primoGiornoSettimana - 1;
                        if (index < offset) return const SizedBox.shrink();

                        int giornoNum = index - offset + 1;
                        DateTime giornoDate = DateTime(_meseCorrente.year, _meseCorrente.month, giornoNum);
                        String loopDataStr = _formattaData(giornoDate);

                        bool isPassato = giornoDate.isBefore(DateTime.now().subtract(const Duration(days: 1))) &&
                            _formattaData(giornoDate) != _formattaData(DateTime.now());
                        bool isChiusoGiorno = _isChiuso(giornoDate);
                        int slotDisponibili = _conteggioSlotPerGiorno[loopDataStr] ?? 0;
                        bool isSoldOut = !isChiusoGiorno && slotDisponibili == 0 && !isPassato;

                        Color coloreBordo = Colors.transparent;
                        Color coloreSfondoCerchio = Colors.white;
                        Color coloreTestoGiorno = Colors.black;

                        if (isPassato) {
                          coloreSfondoCerchio = Colors.transparent;
                          coloreTestoGiorno = Colors.white24;
                        } else if (isChiusoGiorno) {
                          coloreSfondoCerchio = const Color(0xFFE55B5B);
                          coloreTestoGiorno = Colors.white;
                        } else if (isSoldOut) {
                          coloreSfondoCerchio = Colors.black45;
                          coloreTestoGiorno = Colors.white30;
                        } else {
                          if (slotDisponibili > 15) {
                            coloreBordo = const Color(0xFF52C47A);
                          } else if (slotDisponibili > 10) {
                            coloreBordo = const Color(0xFFE2B13C);
                          } else {
                            coloreBordo = Colors.red;
                          }
                        }

                        return GestureDetector(
                          onTap: isPassato || isChiusoGiorno || isSoldOut
                              ? null
                              : () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => PrenotazioneDataScreen(
                                  servizioId: widget.servizioId,
                                  servizioNome: widget.servizioNome,
                                  servizioDurata: widget.servizioDurata,
                                  servizioPrezzo: widget.servizioPrezzo,
                                  dataInizialeSelezionata: giornoDate,
                                ),
                              ),
                            );
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: coloreSfondoCerchio,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: coloreBordo,
                                width: coloreBordo != Colors.transparent ? 3.0 : 0,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                '$giornoNum',
                                style: TextStyle(
                                  color: coloreTestoGiorno,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 40),

                    const Text('Legenda', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),

                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Row(
                        key: ValueKey<int>(_statoLegendaCorrente),
                        children: [
                          Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                  color: coloreSfondoLegenda,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: coloreBordoLegenda,
                                    width: coloreBordoLegenda != Colors.transparent ? 2.5 : 0,
                                  )
                              )
                          ),
                          const SizedBox(width: 12),
                          Text(testoLegendaDinamico, style: const TextStyle(color: Colors.white70, fontSize: 16)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(width: 20, height: 20, decoration: const BoxDecoration(color: Color(0xFFE55B5B), shape: BoxShape.circle)),
                        const SizedBox(width: 12),
                        const Text('Salone chiuso / Passato', style: TextStyle(color: Colors.white70, fontSize: 16)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}