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
  bool _isChangingMonthManually = false; // Flag per bloccare loop tra PageView e freccette

  Map<String, dynamic> _orariNegozioBase = {};
  Map<String, dynamic> _eccezioniCalendario = {};
  final Map<String, int> _conteggioSlotPerGiorno = {};
  final Set<String> _mesiGiaCaricati = {}; // Registra i mesi già elaborati per evitare ricaricamenti

  final List<String> _giorniSettimanaNome = [
    'domenica', 'lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato'
  ];

  // Variabili per la gestione del carosello dinamico nella legenda (3 stati)
  Timer? _timerLegenda;
  int _statoLegendaCorrente = 0;

  // Colore Oro e Verde Foresta
  final Color _coloreOro = const Color(0xFFD4AF37);
  final Color _coloreVerdeForesta = const Color(0xFF164638);

  @override
  void initState() {
    super.initState();
    _preparaMesi();
    _meseCorrente = _mesiSelezionabili[_indiceMeseSelezionato];

    // Ancoraggio per la gestione dell'indice del PageView (Oggi corrisponde alla pagina 1000)
    DateTime oggi = DateTime.now();
    _dataInizialeAnchor = DateTime(oggi.year, oggi.month, oggi.day);
    _giornoSelezionato = _dataInizialeAnchor;
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
          _statoLegendaCorrente = (_statoLegendaCorrente + 1) % 3; // Alterna strettamente tra 0, 1 e 2
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

      await _precaricaDisponibilitaMeseSilenzioso(_meseCorrente);
    } catch (e) {
      // Gestione silenziosa o errore generico
    } finally {
      setState(() => _isLoadingConfig = false);
    }
  }

  // Precarica i dati del mese in background SENZA azzerare la vista o mostrare il loader a tutto schermo
  Future<void> _precaricaDisponibilitaMeseSilenzioso(DateTime meseTarget) async {
    String chiaveMese = "${meseTarget.year}_${meseTarget.month}";
    if (_mesiGiaCaricati.contains(chiaveMese)) return; // Evita di ricaricare se già presente
    _mesiGiaCaricati.add(chiaveMese);

    try {
      final barbersSnap = await FirebaseFirestore.instance.collection('barbers').get();
      final barbieri = barbersSnap.docs;

      int anno = meseTarget.year;
      int mese = meseTarget.month;
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
      if (mounted) setState(() {}); // Aggiorna graficamente solo i conteggi slot
    } catch (e) {
      // Gestione silenziosa
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
    if (_isChangingMonthManually) return; // Se stiamo cambiando mese da freccia, non interferire!

    for (int i = 0; i < _mesiSelezionabili.length; i++) {
      if (_mesiSelezionabili[i].year == giorno.year && _mesiSelezionabili[i].month == giorno.month) {
        if (_indiceMeseSelezionato != i) {
          setState(() {
            _indiceMeseSelezionato = i;
            _meseCorrente = _mesiSelezionabili[i];
          });
          _precaricaDisponibilitaMeseSilenzioso(_mesiSelezionabili[i]);
        }
        break;
      }
    }
  }

  // Funzione ausiliaria per calcolare l'indice esatto nel PageController usando UTC puro
  int _calcolaPaginaPerData(DateTime target) {
    DateTime anchorUtc = DateTime.utc(_dataInizialeAnchor.year, _dataInizialeAnchor.month, _dataInizialeAnchor.day);
    DateTime targetUtc = DateTime.utc(target.year, target.month, target.day);
    int diffGiorni = targetUtc.difference(anchorUtc).inDays;
    return 1000 + diffGiorni;
  }

  void _cambiaMeseManuale(int offset) {
    int nuovoIndice = _indiceMeseSelezionato + offset;
    if (nuovoIndice >= 0 && nuovoIndice < _mesiSelezionabili.length) {
      _isChangingMonthManually = true; // Attiva il blocco di sicurezza

      DateTime nuovoMese = _mesiSelezionabili[nuovoIndice];

      // Target di destinazione tassativo: sempre il 1° giorno del nuovo mese
      DateTime targetData = DateTime(nuovoMese.year, nuovoMese.month, 1);

      // Se il 1° del mese è antecedente ad oggi (es. se fossimo a metà del primo mese), usa oggi
      DateTime oggiDateOnly = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
      if (targetData.isBefore(oggiDateOnly)) {
        targetData = oggiDateOnly;
      }

      int targetPage = _calcolaPaginaPerData(targetData);

      setState(() {
        _indiceMeseSelezionato = nuovoIndice;
        _meseCorrente = nuovoMese;
        _giornoSelezionato = targetData;
      });

      _pageController.jumpToPage(targetPage);
      _precaricaDisponibilitaMeseSilenzioso(nuovoMese);

      // Sblocca il listener dopo che la transizione sul PageController si è stabilizzata
      Future.delayed(const Duration(milliseconds: 150), () {
        _isChangingMonthManually = false;
      });
    }
  }

  Future<void> _selezionaDataDaCalendario() async {
    final DateTime? dataScelta = await showDatePicker(
      context: context,
      initialDate: _giornoSelezionato,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
      locale: const Locale('it', 'IT'),
      builder: (context, child) {
        final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return Theme(
          data: isDarkMode
              ? ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFFD4AF37),
              onPrimary: Colors.black,
              surface: Color(0xFFFDFBF7),
              onSurface: Color(0xFF211D1A),
            ), dialogTheme: DialogThemeData(backgroundColor: const Color(0xFFFDFBF7)),
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

    if (dataScelta != null) {
      int targetPage = _calcolaPaginaPerData(dataScelta);

      setState(() {
        _giornoSelezionato = DateTime(dataScelta.year, dataScelta.month, dataScelta.day);
      });
      _pageController.animateToPage(targetPage, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      _sincronizzaMeseConGiorno(dataScelta);
    }
  }

  void _cambiaGiorno(int offset) {
    int paginaAttuale = _pageController.page!.round();
    int nuovaPagina = paginaAttuale + offset;

    // Impedisce di navigare oltre la data odierna (pagina 1000) andando all'indietro
    if (nuovaPagina < 1000) return;

    _pageController.animateToPage(
      nuovaPagina,
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
      return isDarkMode ? const Color(0xFFA8A099) : Colors.black26;
    } else if (isChiusoGiorno) {
      return const Color(0xFFE55B5B);
    } else if (isSoldOut) {
      return isDarkMode ? const Color(0xFF6B635E) : Colors.grey;
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

    final Color coloreSfondoPagina = isDarkMode ? const Color(0xFFF5F2EB) : const Color(0xFFF4F6F5);
    final Color coloreTestoPrimario = isDarkMode ? const Color(0xFF211D1A) : Colors.black87;
    final Color coloreTestoSecondario = isDarkMode ? const Color(0xFF6B635E) : Colors.black54;

    Color coloreNumeroLegenda;
    String testoLegendaDinamico;

    // Controllo dei 3 stati per la legenda
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
      coloreNumeroLegenda = const Color(0xFF52C47A);
      testoLegendaDinamico = 'Salone libero';
    }

    String loopDataStr = _formattaData(_giornoSelezionato);
    bool isPassato = _giornoSelezionato.isBefore(DateTime.now().subtract(const Duration(days: 1))) &&
        _formattaData(_giornoSelezionato) != _formattaData(DateTime.now());
    bool isChiusoGiorno = _isChiuso(_giornoSelezionato);
    int slotDisponibili = _conteggioSlotPerGiorno[loopDataStr] ?? 0;
    bool isSoldOut = !isChiusoGiorno && slotDisponibili == 0 && !isPassato;

    String nomeGiornoInItaliano = DateFormat('EEEE', 'it_IT').format(_giornoSelezionato);
    String nomeMeseInItaliano = DateFormat('MMMM', 'it_IT').format(_giornoSelezionato);

    // Blocco per verificare se siamo al giorno odierno
    bool eOggi = DateUtils.isSameDay(_giornoSelezionato, DateTime.now());

    return Scaffold(
      backgroundColor: coloreSfondoPagina,
      appBar: AppBar(
        title: const Text('Giorno?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
        backgroundColor: const Color(0xFF164638),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoadingConfig
          ? Center(child: CircularProgressIndicator(color: _coloreOro))
          : SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 10),

              // Selector Mese Scorribile con Freccette
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back_ios_new,
                      size: 18,
                      color: _indiceMeseSelezionato > 0 ? _coloreOro : Colors.grey.withAlpha(76),
                    ),
                    onPressed: _indiceMeseSelezionato > 0 ? () => _cambiaMeseManuale(-1) : null,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Text(
                      nomeMeseInItaliano.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _coloreOro,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.arrow_forward_ios,
                      size: 18,
                      color: _indiceMeseSelezionato < _mesiSelezionabili.length - 1 ? _coloreOro : Colors.grey.withAlpha(76),
                    ),
                    onPressed: _indiceMeseSelezionato < _mesiSelezionabili.length - 1 ? () => _cambiaMeseManuale(1) : null,
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Testo Giorno della settimana
              Text(
                nomeGiornoInItaliano.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: coloreTestoSecondario,
                  fontSize: 18,
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
                      icon: Icon(
                        Icons.chevron_left,
                        color: eOggi ? Colors.grey.withAlpha(76) : coloreTestoPrimario,
                      ),
                      onPressed: eOggi ? null : () => _cambiaGiorno(-1),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        onPageChanged: (index) {
                          if (_isChangingMonthManually) return; // Salta aggiornamenti se attivata la freccia manuale

                          // Se lo scorrimento manuale prova ad andare a una data passata, forza la pagina odierna
                          if (index < 1000) {
                            _pageController.jumpToPage(1000);
                            return;
                          }
                          int offsetGiorni = index - 1000;

                          DateTime nuovaData = DateTime(
                            _dataInizialeAnchor.year,
                            _dataInizialeAnchor.month,
                            _dataInizialeAnchor.day + offsetGiorni,
                          );

                          setState(() {
                            _giornoSelezionato = nuovaData;
                          });

                          // Sincronizza dinamicamente il mese man mano che si scorre in maniera fluida
                          _sincronizzaMeseConGiorno(nuovaData);
                        },
                        itemBuilder: (context, index) {
                          int offsetGiorni = index - 1000;

                          DateTime dataCorrente = DateTime(
                            _dataInizialeAnchor.year,
                            _dataInizialeAnchor.month,
                            _dataInizialeAnchor.day + offsetGiorni,
                          );

                          Color coloreGiorno = _calcolaColoreGiorno(dataCorrente, isDarkMode);
                          bool isChiuso = _isChiuso(dataCorrente);

                          String dataCurrStr = _formattaData(dataCorrente);
                          bool isPassatoLoop = dataCorrente.isBefore(DateTime.now().subtract(const Duration(days: 1))) &&
                              dataCurrStr != _formattaData(DateTime.now());
                          int slotDispLoop = _conteggioSlotPerGiorno[dataCurrStr] ?? 0;
                          bool isSoldOutLoop = !isChiuso && slotDispLoop == 0 && !isPassatoLoop;

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
                                    if (dataCorrente.isBefore(DateUtils.dateOnly(DateTime.now()))) return;

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
                                      child: isChiuso
                                          ? Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // Numero del giorno chiuso (colore primario del testo)
                                          Text(
                                            '${dataCorrente.day}',
                                            textAlign: TextAlign.center,
                                            textScaler: TextScaler.noScaling,
                                            style: TextStyle(
                                              color: coloreTestoPrimario,
                                              fontWeight: FontWeight.bold,
                                              fontSize: fontSize,
                                              height: 1.0,
                                            ),
                                          ),
                                          // Timbro "CLOSED" in diagonale
                                          Transform.rotate(
                                            angle: -0.2,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.65),
                                                border: Border.all(
                                                  color: const Color(0xFFE55B5B),
                                                  width: 2.0,
                                                ),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'CLOSED',
                                                style: TextStyle(
                                                  color: Color(0xFFE55B5B),
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 14,
                                                  letterSpacing: 1.5,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                          : isSoldOutLoop
                                          ? Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // Numero del giorno per sold out pulito (senza bordo scuro)
                                          Text(
                                            '${dataCorrente.day}',
                                            textAlign: TextAlign.center,
                                            textScaler: TextScaler.noScaling,
                                            style: TextStyle(
                                              fontSize: fontSize,
                                              height: 1.0,
                                              fontWeight: FontWeight.bold,
                                              color: coloreTestoPrimario,
                                            ),
                                          ),
                                          // Timbro "SOLD OUT" color oro con testo verde foresta
                                          Transform.rotate(
                                            angle: -0.2,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: _coloreOro,
                                                border: Border.all(
                                                  color: _coloreVerdeForesta,
                                                  width: 2.0,
                                                ),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'SOLD OUT',
                                                style: TextStyle(
                                                  color: _coloreVerdeForesta,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 13,
                                                  letterSpacing: 1.2,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      )
                                          : Stack(
                                        children: [
                                          // Testo di sfondo per lo stroke (solo contorno colorato)
                                          Text(
                                            '${dataCorrente.day}',
                                            textAlign: TextAlign.center,
                                            textScaler: TextScaler.noScaling,
                                            style: TextStyle(
                                              fontSize: fontSize,
                                              height: 1.0,
                                              fontWeight: FontWeight.bold,
                                              foreground: Paint()
                                                ..style = PaintingStyle.stroke
                                                ..strokeWidth = 3.5
                                                ..color = coloreGiorno,
                                            ),
                                          ),
                                          // Testo di primo piano (riempimento colore primario testo)
                                          Text(
                                            '${dataCorrente.day}',
                                            textAlign: TextAlign.center,
                                            textScaler: TextScaler.noScaling,
                                            style: TextStyle(
                                              fontSize: fontSize,
                                              height: 1.0,
                                              fontWeight: FontWeight.bold,
                                              color: coloreTestoPrimario,
                                            ),
                                          ),
                                        ],
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

              // 1ª Riga Legenda: Carosello dinamico disponibilità (libero, medio, affollato)
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Row(
                  key: ValueKey<int>(_statoLegendaCorrente),
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: Colors.black, // Interno nero
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: coloreNumeroLegenda, // Solo contorno colorato
                          width: 2.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(testoLegendaDinamico, style: TextStyle(color: coloreTestoSecondario, fontSize: 16)),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2ª Riga Legenda: Timbro SOLD OUT fissa con larghezza uniforme
              Row(
                children: [
                  Transform.rotate(
                    angle: -0.15,
                    child: Container(
                      width: 58,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _coloreOro,
                        border: Border.all(
                          color: _coloreVerdeForesta,
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: Text(
                        'SOLD OUT',
                        style: TextStyle(
                          color: _coloreVerdeForesta,
                          fontWeight: FontWeight.w900,
                          fontSize: 8.5,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text('Nessun posto disponibile', style: TextStyle(color: coloreTestoSecondario, fontSize: 16)),
                ],
              ),
              const SizedBox(height: 12),

              // 3ª Riga Legenda: Timbro CLOSED fissa con larghezza uniforme
              Row(
                children: [
                  Transform.rotate(
                    angle: -0.15,
                    child: Container(
                      width: 58,
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        border: Border.all(
                          color: const Color(0xFFE55B5B),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'CLOSED',
                        style: TextStyle(
                          color: Color(0xFFE55B5B),
                          fontWeight: FontWeight.w900,
                          fontSize: 8.5,
                          letterSpacing: 0.5,
                        ),
                      ),
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
    );
  }
}

class IntervalloAppuntamento {
  final int inizio;
  final int fine;
  IntervalloAppuntamento({required this.inizio, required this.fine});
}