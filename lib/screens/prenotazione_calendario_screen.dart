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
  final String? clienteId;   // Opzionale: ID del cliente selezionato
  final String? clienteNome; // Opzionale: Nome del cliente selezionato

  const PrenotazioneCalendarioScreen({
    super.key,
    required this.servizioId,
    required this.servizioNome,
    required this.servizioDurata,
    required this.servizioPrezzo,
    this.clienteId,
    this.clienteNome,
  });

  @override
  State<PrenotazioneCalendarioScreen> createState() => _PrenotazioneCalendarioScreenState();
}

class _PrenotazioneCalendarioScreenState extends State<PrenotazioneCalendarioScreen> {
  late DateTime _meseCorrente;
  final List<DateTime> _mesiSelezionabili = [];
  int _indiceMeseSelezionato = 0;

  late DateTime _giornoSelezionato;
  late DateTime _dataInizialeAnchor;
  late PageController _pageController;

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

  // Colore Oro uniforme per tutte le selezioni
  final Color _coloreOro = const Color(0xFFD4AF37);

  @override
  void initState() {
    super.initState();
    _preparaMesi();
    _meseCorrente = _mesiSelezionabili[_indiceMeseSelezionato];

    // Ancoraggio per la gestione dell'indice del PageView
    _dataInizialeAnchor = DateTime.now();
    _giornoSelezionato = DateTime.now();
    _pageController = PageController(initialPage: 1000, viewportFraction: 0.35);

    _inizializzaDati();
    _avviaTimerLegenda();
  }

  @override
  void dispose() {
    _timerLegenda?.cancel();
    _pageController.dispose();
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

  void _sincronizzaMeseConGiorno(DateTime giorno) {
    for (int i = 0; i < _mesiSelezionabili.length; i++) {
      if (_mesiSelezionabili[i].year == giorno.year && _mesiSelezionabili[i].month == giorno.month) {
        if (_indiceMeseSelezionato != i) {
          _indiceMeseSelezionato = i;
          _meseCorrente = _mesiSelezionabili[i];
          _precaricaDisponibilitaMese();
        }
        break;
      }
    }
  }

  Future<void> _selezionaDataDaCalendario() async {
    final DateTime? dataScelta = await showDatePicker(
      context: context,
      initialDate: _giornoSelezionato,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      locale: const Locale('it', 'IT'),
    );

    if (dataScelta != null) {
      int differenzaGiorni = DateUtils.dateOnly(dataScelta).difference(DateUtils.dateOnly(_dataInizialeAnchor)).inDays;
      int targetPage = 1000 + differenzaGiorni;

      setState(() {
        _giornoSelezionato = dataScelta;
      });
      _pageController.animateToPage(targetPage, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      _sincronizzaMeseConGiorno(dataScelta);
    }
  }

  void _cambiaGiorno(int offset) {
    _pageController.animateToPage(
      _pageController.page!.round() + offset,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
    );
  }

  Color _calcolaColoreGiorno(DateTime giorno, bool isDarkMode) {
    String loopDataStr = _formattaData(giorno);
    bool isPassato = giorno.isBefore(DateTime.now().subtract(const Duration(days: 1))) &&
        _formattaData(giorno) != _formattaData(DateTime.now());
    bool isChiusoGiorno = _isChiuso(giorno);
    int slotDisponibili = _conteggioSlotPerGiorno[loopDataStr] ?? 0;
    bool isSoldOut = !isChiusoGiorno && slotDisponibili == 0 && !isPassato;

    if (isPassato) {
      return isDarkMode ? Colors.white24 : Colors.black26;
    } else if (isChiusoGiorno) {
      return const Color(0xFFE55B5B);
    } else if (isSoldOut) {
      return isDarkMode ? Colors.white30 : Colors.grey;
    } else {
      if (slotDisponibili > 15) {
        return const Color(0xFF52C47A);
      } else if (slotDisponibili > 10) {
        return _coloreOro;
      } else {
        return Colors.red;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final Color coloreSfondoPagina = isDarkMode ? const Color(0xFF0A0A0A) : const Color(0xFFF4F6F5);
    final Color coloreSfondoContenitoreGiorni = isDarkMode ? const Color(0xFF1C1C1E) : Colors.white;
    final Color coloreTestoPrimario = isDarkMode ? Colors.white : Colors.black87;
    final Color coloreTestoSecondario = isDarkMode ? Colors.white70 : Colors.black54;

    Color coloreNumeroLegenda = Colors.black;
    String testoLegendaDinamico = '';

    if (_statoLegendaCorrente == 0) {
      coloreNumeroLegenda = const Color(0xFF52C47A);
      testoLegendaDinamico = 'Salone libero';
    } else if (_statoLegendaCorrente == 1) {
      coloreNumeroLegenda = _coloreOro;
      testoLegendaDinamico = 'Salone mediamente affollato';
    } else if (_statoLegendaCorrente == 2) {
      coloreNumeroLegenda = Colors.red;
      testoLegendaDinamico = 'Salone affollato';
    } else {
      coloreNumeroLegenda = isDarkMode ? Colors.white30 : Colors.grey;
      testoLegendaDinamico = 'Nessun posto disponibile';
    }

    String loopDataStr = _formattaData(_giornoSelezionato);
    bool isPassato = _giornoSelezionato.isBefore(DateTime.now().subtract(const Duration(days: 1))) &&
        _formattaData(_giornoSelezionato) != _formattaData(DateTime.now());
    bool isChiusoGiorno = _isChiuso(_giornoSelezionato);
    int slotDisponibili = _conteggioSlotPerGiorno[loopDataStr] ?? 0;
    bool isSoldOut = !isChiusoGiorno && slotDisponibili == 0 && !isPassato;

    String nomeGiornoInItaliano = DateFormat('EEEE', 'it_IT').format(_giornoSelezionato);

    return Scaffold(
      backgroundColor: coloreSfondoPagina,
      appBar: AppBar(
        title: const Text('Quando?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: const Color(0xFF164638),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoadingConfig
          ? Center(child: CircularProgressIndicator(color: _coloreOro))
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Seleziona un giorno per continuare',
                  style: TextStyle(color: coloreTestoSecondario, fontSize: 16),
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
                          DateTime primaDataMese = DateTime(m.year, m.month, 1);
                          int diff = DateUtils.dateOnly(primaDataMese).difference(DateUtils.dateOnly(_dataInizialeAnchor)).inDays;

                          setState(() {
                            _indiceMeseSelezionato = idx;
                            _meseCorrente = _mesiSelezionabili[idx];
                            _giornoSelezionato = primaDataMese;
                          });
                          _pageController.jumpToPage(1000 + diff);
                          _precaricaDisponibilitaMese();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            color: isSel ? _coloreOro : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: isDarkMode ? null : [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4, offset: const Offset(0, 2))
                            ],
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
              decoration: BoxDecoration(
                color: coloreSfondoContenitoreGiorni,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(32),
                  topRight: Radius.circular(32),
                ),
                boxShadow: isDarkMode ? null : [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -4))
                ],
              ),
              child: _isPreloadingGiorni
                  ? Center(child: CircularProgressIndicator(color: _coloreOro))
                  : SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),

                    // Testo Giorno della settimana
                    Text(
                      nomeGiornoInItaliano.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: coloreTestoSecondario,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Carosello Scorrevole in diretta che segue il dito
                    SizedBox(
                      height: 100,
                      child: Row(
                        children: [
                          IconButton(
                            iconSize: 28,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(Icons.chevron_left, color: coloreTestoPrimario),
                            onPressed: () => _cambiaGiorno(-1),
                          ),
                          Expanded(
                            child: PageView.builder(
                              controller: _pageController,
                              onPageChanged: (index) {
                                int offsetGiorni = index - 1000;
                                DateTime nuovaData = _dataInizialeAnchor.add(Duration(days: offsetGiorni));
                                setState(() {
                                  _giornoSelezionato = nuovaData;
                                });
                                _sincronizzaMeseConGiorno(nuovaData);
                              },
                              itemBuilder: (context, index) {
                                int offsetGiorni = index - 1000;
                                DateTime dataCorrente = _dataInizialeAnchor.add(Duration(days: offsetGiorni));
                                Color coloreGiorno = _calcolaColoreGiorno(dataCorrente, isDarkMode);

                                return AnimatedBuilder(
                                  animation: _pageController,
                                  builder: (context, child) {
                                    double val = 0.0;
                                    if (_pageController.position.haveDimensions) {
                                      val = _pageController.page! - index;
                                    } else {
                                      val = (_pageController.initialPage - index).toDouble();
                                    }

                                    // Calcolo dinamico di opacità e dimensione mentre trascini
                                    double opacity = (1 - (val.abs() * 0.7)).clamp(0.3, 1.0);
                                    double fontSize = (85 - (val.abs() * 49)).clamp(36.0, 85.0);

                                    return Center(
                                      child: GestureDetector(
                                        onTap: () {
                                          if (val.abs() < 0.2) {
                                            _selezionaDataDaCalendario();
                                          } else {
                                            _pageController.animateToPage(
                                              index,
                                              duration: const Duration(milliseconds: 250),
                                              curve: Curves.easeInOut,
                                            );
                                          }
                                        },
                                        child: Opacity(
                                          opacity: opacity,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Text(
                                              '${dataCorrente.day}',
                                              textAlign: TextAlign.center,
                                              textScaler: TextScaler.noScaling,
                                              style: TextStyle(
                                                color: coloreGiorno,
                                                fontWeight: FontWeight.bold,
                                                fontSize: fontSize,
                                                height: 1.0,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                          IconButton(
                            iconSize: 28,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(Icons.chevron_right, color: coloreTestoPrimario),
                            onPressed: () => _cambiaGiorno(1),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Bottone per procedere alla schermata orari se disponibile
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _coloreOro,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: isPassato || isChiusoGiorno || isSoldOut
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
                                dataInizialeSelezionata: _giornoSelezionato,
                                clienteId: widget.clienteId,
                                clienteNome: widget.clienteNome,
                              ),
                            ),
                          );
                        },
                        child: const Text(
                          'Conferma Giorno',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Legenda', style: TextStyle(color: coloreTestoPrimario, fontSize: 22, fontWeight: FontWeight.bold)),
                    ),
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
                              color: coloreNumeroLegenda,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(testoLegendaDinamico, style: TextStyle(color: coloreTestoSecondario, fontSize: 16)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE55B5B),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text('Salone chiuso', style: TextStyle(color: coloreTestoSecondario, fontSize: 16)),
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

class IntervalloAppuntamento {
  final int inizio;
  final int fine;
  IntervalloAppuntamento({required this.inizio, required this.fine});
}