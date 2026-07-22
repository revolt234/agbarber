import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:intl/intl.dart';

class GestionePeriodicoScreen extends StatefulWidget {
  const GestionePeriodicoScreen({super.key});

  @override
  State<GestionePeriodicoScreen> createState() => _GestionePeriodicoScreenState();
}

class _EsitoPrenotazione {
  final DateTime data;
  final String slot;
  final bool isOccupato;
  final bool isChiuso;
  final String? motivo;

  _EsitoPrenotazione({
    required this.data,
    required this.slot,
    this.isOccupato = false,
    this.isChiuso = false,
    this.motivo,
  });
}

class _GestionePeriodicoScreenState extends State<GestionePeriodicoScreen> {
  // Salviamo gli ID anziché l'intero DocumentSnapshot per evitare errori di uguaglianza oggetti
  String? _clienteSelezionatoId;
  String? _barbiereSelezionatoId;
  String? _servizioSelezionatoId;

  Map<String, dynamic>? _barbiereData;
  Map<String, dynamic>? _servizioData;

  DateTime _dataInizio = DateTime.now();
  // Data di fine periodico impostata di default a 2 mesi dopo
  DateTime _dataFine = DateTime.now().add(const Duration(days: 60));
  TimeOfDay _orarioSelezionato = const TimeOfDay(hour: 15, minute: 30);

  // Cadenza (ogni quante settimane)
  int _cadenzaSettimane = 2; // Default: Ogni 2 settimane

  bool _isAnalizzando = false;
  bool _isCreando = false;
  List<_EsitoPrenotazione> _analisiRisultati = [];

  // Mappe per gli orari del negozio e le eccezioni del calendario
  Map<String, dynamic> _orariNegozioBase = {};
  bool _isLoadingConfig = true;

  // Controller dedicati alla ricerca testuale di cliente e servizio
  final TextEditingController _clienteTextController = TextEditingController();
  final TextEditingController _servizioTextController = TextEditingController();

  final List<String> _giorniSettimana = [
    'domenica', 'lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato'
  ];

  final constColorVerde = const Color(0xFF164638);
  final constColorOro = const Color(0xFFE2B13C);

  String _formattaData(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  String _formattaOra(TimeOfDay t) => "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";

  int _minutiDaStringa(String s) {
    final parti = s.split(':');
    return int.parse(parti[0]) * 60 + int.parse(parti[1]);
  }

  @override
  void initState() {
    super.initState();
    _caricaOrariNegozio();
  }

  @override
  void dispose() {
    _clienteTextController.dispose();
    _servizioTextController.dispose();
    super.dispose();
  }

  // Recupera la configurazione degli orari dal salone
  Future<void> _caricaOrariNegozio() async {
    try {
      final orariDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('orari_negozio')
          .get(const GetOptions(source: Source.server));

      if (orariDoc.exists) {
        _orariNegozioBase = orariDoc.data() ?? {};
      }
    } catch (e) {
      debugPrint("Errore caricamento orari negozio: $e");
    } finally {
      if (mounted) setState(() => _isLoadingConfig = false);
    }
  }

  // Pulisce interamente il form e lo riporta allo stato iniziale
  void _resetForm() {
    setState(() {
      _clienteSelezionatoId = null;
      _clienteTextController.clear();
      _barbiereSelezionatoId = null;
      _servizioSelezionatoId = null;
      _servizioTextController.clear();
      _barbiereData = null;
      _servizioData = null;
      _dataInizio = DateTime.now();
      _dataFine = DateTime.now().add(const Duration(days: 60));
      _orarioSelezionato = const TimeOfDay(hour: 15, minute: 30);
      _cadenzaSettimane = 2;
      _analisiRisultati.clear();
    });
  }

  // Scansione di sicurezza per verificare sovrapposizioni e aperture prima del salvataggio
  Future<void> _analizzaDisponibilita() async {
    if (_clienteSelezionatoId == null || _barbiereSelezionatoId == null || _servizioSelezionatoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona cliente, operatore e servizio per procedere.')),
      );
      return;
    }

    if (_dataFine.isBefore(_dataInizio)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La data di fine non può essere uguale alla data di inizio.')),
      );
      return;
    }

    setState(() {
      _isAnalizzando = true;
      _analisiRisultati.clear();
    });

    try {
      final db = FirebaseFirestore.instance;
      final barberId = _barbiereSelezionatoId!;
      final int durataServizio = _servizioData?['duration'] ?? 30;
      final String slotStr = _formattaOra(_orarioSelezionato);
      final int inizioNuovoMinuti = _minutiDaStringa(slotStr);
      final int fineNuovoMinuti = inizioNuovoMinuti + durataServizio;

      final adesso = DateTime.now();
      final String oggiDataStr = _formattaData(adesso);
      final int minutiAttuali = (adesso.hour * 60) + adesso.minute;

      // Normalizza la data di fine per includere interamente la giornata fino alle 23:59:59
      final DateTime dataFineLimite = DateTime(_dataFine.year, _dataFine.month, _dataFine.day, 23, 59, 59);

      List<_EsitoPrenotazione> tempRisultati = [];
      DateTime giornoCorrente = DateTime(_dataInizio.year, _dataInizio.month, _dataInizio.day);

      // Ciclo preciso basato sulla Data di Fine scelta
      while (giornoCorrente.isBefore(dataFineLimite) || giornoCorrente.isAtSameMomentAs(dataFineLimite)) {
        String dataStr = _formattaData(giornoCorrente);

        // 0. CONTROLLO ORARIO GIÀ PASSATO (Se è la data di oggi ed è già trascorso l'orario)
        if (dataStr == oggiDataStr && inizioNuovoMinuti <= minutiAttuali) {
          tempRisultati.add(_EsitoPrenotazione(
              data: giornoCorrente,
              slot: slotStr,
              isOccupato: true,
              motivo: "Orario già passato"
          ));
          giornoCorrente = giornoCorrente.add(Duration(days: _cadenzaSettimane * 7));
          continue;
        }

        // 1. CONTROLLO ECCEZIONI CALENDARIO (Aperture/Chiusure straordinarie)
        final eccezioneDoc = await db.collection('calendar_exceptions').doc(dataStr).get();
        bool haAperturaStraordinaria = false;
        Map<String, dynamic>? orariGiorno;

        if (eccezioneDoc.exists) {
          final dataExCal = eccezioneDoc.data();
          if (dataExCal != null && dataExCal['status'] == 'chiuso') {
            tempRisultati.add(_EsitoPrenotazione(data: giornoCorrente, slot: slotStr, isChiuso: true, motivo: "Salone chiuso"));
            giornoCorrente = giornoCorrente.add(Duration(days: _cadenzaSettimane * 7));
            continue;
          } else if (dataExCal != null && dataExCal['status'] == 'aperto') {
            haAperturaStraordinaria = true;
            orariGiorno = {
              'isAperto': true,
              'mattina': dataExCal['mattina'],
              'pomeriggio': dataExCal['pomeriggio'],
            };
          }
        }

        // 2. CONTROLLO CHIUSURA SETTIMANALE BASE (es. Domenica / Lunedì)
        if (!haAperturaStraordinaria) {
          String nomeGiorno = _giorniSettimana[giornoCorrente.weekday % 7];
          orariGiorno = _orariNegozioBase[nomeGiorno];

          if (orariGiorno == null || orariGiorno['isAperto'] == false) {
            tempRisultati.add(_EsitoPrenotazione(data: giornoCorrente, slot: slotStr, isChiuso: true, motivo: "Salone chiuso"));
            giornoCorrente = giornoCorrente.add(Duration(days: _cadenzaSettimane * 7));
            continue;
          }
        }

        // 3. CONTROLLO ORARIO DENTRO LE FASCE D'APERTURA (Mattina / Pomeriggio)
        bool orarioNeiLimitiDiApertura = false;

        void verificaFascia(Map<String, dynamic>? fascia) {
          if (fascia == null) return;
          final String? ap = fascia['apertura'];
          final String? ch = fascia['chiusura'];
          if (ap != null && ch != null) {
            int inApertura = _minutiDaStringa(ap);
            int inChiusura = _minutiDaStringa(ch);
            if (inizioNuovoMinuti >= inApertura && fineNuovoMinuti <= inChiusura) {
              orarioNeiLimitiDiApertura = true;
            }
          }
        }

        if (orariGiorno != null) {
          verificaFascia(orariGiorno['mattina']);
          verificaFascia(orariGiorno['pomeriggio']);
        }

        if (!orarioNeiLimitiDiApertura) {
          tempRisultati.add(_EsitoPrenotazione(data: giornoCorrente, slot: slotStr, isChiuso: true, motivo: "Salone chiuso a quest'ora"));
          giornoCorrente = giornoCorrente.add(Duration(days: _cadenzaSettimane * 7));
          continue;
        }

        // 4. CONTROLLO ECCEZIONE OPERATORE (Assente / Mezza giornata)
        final barberExDoc = await db.collection('barber_exceptions').doc("${dataStr}_$barberId").get();
        final dataExBarber = barberExDoc.exists ? barberExDoc.data() : null;

        if (dataExBarber != null) {
          if (dataExBarber['type'] == 'assente') {
            tempRisultati.add(_EsitoPrenotazione(data: giornoCorrente, slot: slotStr, isChiuso: true, motivo: "Operatore assente"));
            giornoCorrente = giornoCorrente.add(Duration(days: _cadenzaSettimane * 7));
            continue;
          } else if (dataExBarber['type'] == 'mezza_giornata') {
            int ora = inizioNuovoMinuti ~/ 60;
            if (dataExBarber['fascia'] == 'mattina' && ora >= 13) {
              tempRisultati.add(_EsitoPrenotazione(data: giornoCorrente, slot: slotStr, isChiuso: true, motivo: "Operatore non di turno"));
              giornoCorrente = giornoCorrente.add(Duration(days: _cadenzaSettimane * 7));
              continue;
            }
            if (dataExBarber['fascia'] == 'pomeriggio' && ora < 13) {
              tempRisultati.add(_EsitoPrenotazione(data: giornoCorrente, slot: slotStr, isChiuso: true, motivo: "Operatore non di turno"));
              giornoCorrente = giornoCorrente.add(Duration(days: _cadenzaSettimane * 7));
              continue;
            }
          }
        }

        // 5. CONTROLLO SOVRAPPOSIZIONE CON PRENOTAZIONI ESISTENTI
        final appSnap = await db.collection('appointments')
            .where('date', isEqualTo: dataStr)
            .where('barberId', isEqualTo: barberId)
            .get();

        bool conflitto = false;
        for (var doc in appSnap.docs) {
          final datiApp = doc.data();
          if (datiApp.containsKey('slot') && datiApp['slot'] != null) {
            int appInizio = _minutiDaStringa(datiApp['slot']);
            int appDurata = datiApp['duration'] ?? datiApp['totalDuration'] ?? 30;
            int appFine = appInizio + appDurata;

            if (inizioNuovoMinuti < appFine && fineNuovoMinuti > appInizio) {
              conflitto = true;
              break;
            }
          }
        }

        if (conflitto) {
          tempRisultati.add(_EsitoPrenotazione(data: giornoCorrente, slot: slotStr, isOccupato: true, motivo: "Orario già occupato"));
        } else {
          tempRisultati.add(_EsitoPrenotazione(data: giornoCorrente, slot: slotStr));
        }

        // Avanza della cadenza selezionata (es. + 1, 2, 3 o 4 settimane)
        giornoCorrente = giornoCorrente.add(Duration(days: _cadenzaSettimane * 7));
      }

      setState(() {
        _analisiRisultati = tempRisultati;
      });
    } catch (e) {
      debugPrint("Errore analisi disponibilità: $e");
    } finally {
      setState(() => _isAnalizzando = false);
    }
  }

  // Genera le prenotazioni valide chiamando la Cloud Function sicura
  Future<void> _confermaECreaPrenotazioni() async {
    final valide = _analisiRisultati.where((element) => !element.isOccupato && !element.isChiuso).toList();

    if (valide.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nessuna data valida disponibile per completare il periodico.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isCreando = true);

    try {
      final List<String> dateList = valide.map((e) => _formattaData(e.data)).toList();
      final String slotStr = _formattaOra(_orarioSelezionato);

      final HttpsCallable callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('creaPrenotazioniPeriodicheSicure');

      final HttpsCallableResult result = await callable.call(<String, dynamic>{
        'userIdCliente': _clienteSelezionatoId,
        'barberId': _barbiereSelezionatoId,
        'barberName': _barbiereData?['name'] ?? 'Operatore',
        'serviceNome': _servizioData?['name'] ?? 'Servizio',
        'servicePrezzo': (_servizioData?['price'] ?? 0.0).toDouble(),
        'duration': _servizioData?['duration'] ?? 30,
        'dateList': dateList,
        'slot': slotStr,
      });

      final Map<String, dynamic> datiRisposta = Map<String, dynamic>.from(result.data as Map);
      final int createConSuccesso = datiRisposta['createConSuccesso'] ?? 0;
      final int saltateOccupate = datiRisposta['saltateOccupate'] ?? 0;
      final List<dynamic> dateSaltateGrezze = datiRisposta['dateSaltate'] ?? [];

      final List<String> dateSaltateFormattate = dateSaltateGrezze.map((dStr) {
        try {
          final parsed = DateTime.parse(dStr.toString());
          return DateFormat('EEEE dd/MM/yyyy', 'it_IT').format(parsed);
        } catch (_) {
          return dStr.toString();
        }
      }).toList();

      if (mounted) {
        if (saltateOccupate > 0) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Attenzione: Conflitto rilevato!'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Generate con successo $createConSuccesso prenotazioni.\n'),
                    Text('$saltateOccupate data/e NON sono state prenotate perché già occupate:\n', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
                    ...dateSaltateFormattate.map((d) => Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Row(
                        children: [
                          const Icon(Icons.close, color: Colors.redAccent, size: 16),
                          const SizedBox(width: 6),
                          Expanded(child: Text(d, style: const TextStyle(fontWeight: FontWeight.w500))),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _resetForm();
                  },
                  child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            ),
          );
        } else {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              title: const Text('Completato!'),
              content: Text('Generate con successo $createConSuccesso prenotazioni periodiche in agenda.'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _resetForm();
                  },
                  child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante la creazione periodica: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isCreando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color coloreSfondo = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF4F6F5);
    final Color coloreCard = isDarkMode ? const Color(0xFF1C2824) : Colors.white;
    final Color coloreTesto = isDarkMode ? Colors.white : Colors.black87;

    // Calcolo del padding inferiore del sistema (barra a 3 pulsanti / gesture bar)
    final double paddingInBassoSistema = MediaQuery.of(context).padding.bottom;

    if (_isLoadingConfig) {
      return Scaffold(
        backgroundColor: coloreSfondo,
        body: const Center(child: CircularProgressIndicator(color: Color(0xFFE2B13C))),
      );
    }

    return Scaffold(
      backgroundColor: coloreSfondo,
      appBar: AppBar(
        title: const Text('PROGRAMMA PERIODICO', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        backgroundColor: constColorVerde,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      // SafeArea integrata per evitare sovrapposizioni e problemi di sistema
      body: SafeArea(
        child: SingleChildScrollView(
          // Padding calcolato esattamente sulla barra di navigazione del sistema (Pixel / Android / iOS)
          padding: EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0 + paddingInBassoSistema),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. SELEZIONE CLIENTE CON CAMPO DI RICERCA TESTUALE RAPIDA
              Text('1. Seleziona Cliente:', style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 6),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('users').where('role', isNotEqualTo: 'barbiere').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const LinearProgressIndicator(color: Color(0xFFE2B13C));
                  final clientiDocs = snapshot.data!.docs;

                  return RawAutocomplete<QueryDocumentSnapshot>(
                    textEditingController: _clienteTextController,
                    displayStringForOption: (doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      final nome = d['name'] ?? d['nome'] ?? 'Senza Nome';
                      final email = d['email'] ?? '';
                      return email.isNotEmpty ? "$nome ($email)" : nome;
                    },
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return clientiDocs;
                      }
                      final query = textEditingValue.text.toLowerCase();
                      return clientiDocs.where((doc) {
                        final d = doc.data() as Map<String, dynamic>;
                        final nome = (d['name'] ?? d['nome'] ?? '').toString().toLowerCase();
                        final email = (d['email'] ?? '').toString().toLowerCase();
                        return nome.contains(query) || email.contains(query);
                      });
                    },
                    onSelected: (QueryDocumentSnapshot doc) {
                      setState(() {
                        _clienteSelezionatoId = doc.id;
                        _analisiRisultati.clear();
                      });
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        style: TextStyle(color: coloreTesto),
                        decoration: InputDecoration(
                          hintText: 'Cerca cliente per nome o email...',
                          hintStyle: TextStyle(color: isDarkMode ? Colors.white54 : Colors.black45, fontSize: 14),
                          prefixIcon: Icon(Icons.search, color: constColorOro),
                          suffixIcon: controller.text.isNotEmpty
                              ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              controller.clear();
                              _clienteSelezionatoId = null;
                              if (_analisiRisultati.isNotEmpty) {
                                setState(() {
                                  _analisiRisultati.clear();
                                });
                              }
                            },
                          )
                              : null,
                          filled: true,
                          fillColor: coloreCard,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade400),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: constColorOro, width: 2),
                          ),
                        ),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 6,
                          color: coloreCard,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            constraints: const BoxConstraints(maxHeight: 220),
                            width: MediaQuery.of(context).size.width - 32,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (BuildContext context, int index) {
                                final doc = options.elementAt(index);
                                final d = doc.data() as Map<String, dynamic>;
                                final nome = d['name'] ?? d['nome'] ?? 'Senza Nome';
                                final email = d['email'] ?? 'No email';

                                return ListTile(
                                  dense: true,
                                  title: Text(nome, style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold)),
                                  subtitle: Text(email, style: TextStyle(color: isDarkMode ? Colors.white60 : Colors.black54)),
                                  onTap: () => onSelected(doc),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 16),

              // 2. SELEZIONE OPERATORE
              Text('2. Operatore:', style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('barbers').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final barbieri = snapshot.data!.docs;

                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: coloreCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade400)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        hint: const Text('Operatore'),
                        value: _barbiereSelezionatoId,
                        items: barbieri.map((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          return DropdownMenuItem<String>(
                            value: doc.id,
                            child: Text(d['name'] ?? 'Staff', style: TextStyle(color: coloreTesto)),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            final selectedDoc = barbieri.firstWhere((element) => element.id == val);
                            setState(() {
                              _barbiereSelezionatoId = val;
                              _barbiereData = selectedDoc.data() as Map<String, dynamic>;
                              _analisiRisultati.clear();
                            });
                          }
                        },
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 16),

              // 3. SELEZIONE SERVIZIO (RawAutocomplete stile Cliente)
              Text('3. Servizio:', style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 6),
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('services').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const LinearProgressIndicator(color: Color(0xFFE2B13C));
                  final serviziDocs = snapshot.data!.docs;

                  return RawAutocomplete<QueryDocumentSnapshot>(
                    textEditingController: _servizioTextController,
                    displayStringForOption: (doc) {
                      final d = doc.data() as Map<String, dynamic>;
                      final nome = d['name'] ?? 'Servizio';
                      final durata = d['duration'] ?? 30;
                      return "$nome (${durata}m)";
                    },
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return serviziDocs;
                      }
                      final query = textEditingValue.text.toLowerCase();
                      return serviziDocs.where((doc) {
                        final d = doc.data() as Map<String, dynamic>;
                        final nome = (d['name'] ?? '').toString().toLowerCase();
                        return nome.contains(query);
                      });
                    },
                    onSelected: (QueryDocumentSnapshot doc) {
                      setState(() {
                        _servizioSelezionatoId = doc.id;
                        _servizioData = doc.data() as Map<String, dynamic>;
                        _analisiRisultati.clear();
                      });
                    },
                    fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        style: TextStyle(color: coloreTesto),
                        decoration: InputDecoration(
                          hintText: 'Cerca servizio per nome...',
                          hintStyle: TextStyle(color: isDarkMode ? Colors.white54 : Colors.black45, fontSize: 14),
                          prefixIcon: Icon(Icons.content_cut, color: constColorOro),
                          suffixIcon: controller.text.isNotEmpty
                              ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              controller.clear();
                              _servizioSelezionatoId = null;
                              _servizioData = null;
                              if (_analisiRisultati.isNotEmpty) {
                                setState(() {
                                  _analisiRisultati.clear();
                                });
                              }
                            },
                          )
                              : null,
                          filled: true,
                          fillColor: coloreCard,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade400),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: constColorOro, width: 2),
                          ),
                        ),
                      );
                    },
                    optionsViewBuilder: (context, onSelected, options) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 6,
                          color: coloreCard,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            constraints: const BoxConstraints(maxHeight: 220),
                            width: MediaQuery.of(context).size.width - 32,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                            child: ListView.separated(
                              padding: EdgeInsets.zero,
                              shrinkWrap: true,
                              itemCount: options.length,
                              separatorBuilder: (context, index) => const Divider(height: 1),
                              itemBuilder: (BuildContext context, int index) {
                                final doc = options.elementAt(index);
                                final d = doc.data() as Map<String, dynamic>;
                                final nome = d['name'] ?? 'Servizio';
                                final durata = d['duration'] ?? 30;
                                final prezzo = (d['price'] ?? 0.0).toDouble();

                                return ListTile(
                                  dense: true,
                                  title: Text(nome, style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold)),
                                  subtitle: Text("Durata: ${durata}m - Prezzo: € ${prezzo.toStringAsFixed(2).replaceAll('.', ',')}", style: TextStyle(color: isDarkMode ? Colors.white60 : Colors.black54)),
                                  onTap: () => onSelected(doc),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),

              const SizedBox(height: 16),

              // 4. REGOLAZIONE DATE (INIZIO E FINE), ORA E CADENZA
              Card(
                color: coloreCard,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      ListTile(
                        dense: true,
                        title: Text('Data inizio', style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold)),
                        subtitle: Text(DateFormat('EEEE dd MMMM yyyy', 'it_IT').format(_dataInizio)),
                        trailing: Icon(Icons.calendar_month, color: constColorOro),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _dataInizio,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() {
                              _dataInizio = picked;
                              if (_dataFine.isBefore(_dataInizio)) {
                                _dataFine = _dataInizio.add(const Duration(days: 60));
                              }
                              _analisiRisultati.clear();
                            });
                          }
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        dense: true,
                        title: Text('Data fine', style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold)),
                        subtitle: Text(DateFormat('EEEE dd MMMM yyyy', 'it_IT').format(_dataFine)),
                        trailing: Icon(Icons.event, color: constColorOro),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _dataFine.isBefore(_dataInizio) ? _dataInizio : _dataFine,
                            firstDate: _dataInizio,
                            lastDate: _dataInizio.add(const Duration(days: 365)),
                          );
                          if (picked != null) {
                            setState(() {
                              _dataFine = picked;
                              _analisiRisultati.clear();
                            });
                          }
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        dense: true,
                        title: Text('Orario di preferenza', style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold)),
                        subtitle: Text(_formattaOra(_orarioSelezionato)),
                        trailing: Icon(Icons.access_time, color: constColorOro),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: _orarioSelezionato,
                          );
                          if (picked != null) {
                            setState(() {
                              _orarioSelezionato = picked;
                              _analisiRisultati.clear();
                            });
                          }
                        },
                      ),
                      const Divider(height: 1),
                      // Selettore della cadenza messo a capo con layout ampio a tutta larghezza
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cadenza appuntamento:',
                              style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            SizedBox(
                              width: double.infinity,
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  value: _cadenzaSettimane,
                                  isExpanded: true,
                                  dropdownColor: coloreCard,
                                  items: [1, 2, 3, 4].map((num) {
                                    return DropdownMenuItem<int>(
                                      value: num,
                                      child: Text(
                                        num == 1 ? 'Ogni settimana' : 'Ogni $num settimane',
                                        style: TextStyle(color: coloreTesto, fontWeight: FontWeight.w500),
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() {
                                        _cadenzaSettimane = val;
                                        _analisiRisultati.clear();
                                      });
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // BOTTONE VERIFICA CALENDARIO
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: constColorVerde,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isAnalizzando
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.search),
                  label: Text(_isAnalizzando ? 'VERIFICA IN CORSO...' : 'VERIFICA CALENDARIO'),
                  onPressed: _isAnalizzando ? null : _analizzaDisponibilita,
                ),
              ),

              const SizedBox(height: 20),

              // ANTEPRIMA ESITI VERIFICA E CONFERMA FINALE
              if (_analisiRisultati.isNotEmpty) ...[
                Text('Anteprima Date e Conflitti:', style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _analisiRisultati.length,
                  itemBuilder: (context, index) {
                    final item = _analisiRisultati[index];
                    final bool haProblema = item.isOccupato || item.isChiuso;

                    return Card(
                      color: haProblema ? Colors.red.shade900.withValues(alpha: 0.3) : Colors.green.shade900.withValues(alpha: 0.3),
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          haProblema ? Icons.error_outline : Icons.check_circle_outline,
                          color: haProblema ? Colors.redAccent : Colors.greenAccent,
                        ),
                        title: Text(
                          "${DateFormat('EEEE dd/MM/yyyy', 'it_IT').format(item.data)} alle ${item.slot}",
                          style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold),
                        ),
                        subtitle: haProblema ? Text(item.motivo ?? 'Non disponibile', style: const TextStyle(color: Colors.redAccent)) : const Text('Disponibile', style: TextStyle(color: Colors.greenAccent)),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: constColorOro,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _isCreando ? null : _confermaECreaPrenotazioni,
                    child: _isCreando
                        ? const CircularProgressIndicator(color: Colors.black)
                        : const Text('CONFERMA ED INSERISCI PRENOTAZIONI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}