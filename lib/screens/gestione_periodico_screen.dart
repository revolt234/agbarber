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
  TimeOfDay _orarioSelezionato = const TimeOfDay(hour: 15, minute: 30);
  int _numeroSettimanetot = 4; // Default: 4 settimane

  bool _isAnalizzando = false;
  bool _isCreando = false;
  List<_EsitoPrenotazione> _analisiRisultati = [];

  final constColorVerde = const Color(0xFF164638);
  final constColorOro = const Color(0xFFE2B13C);

  String _formattaData(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
  String _formattaOra(TimeOfDay t) => "${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}";

  int _minutiDaStringa(String s) {
    final parti = s.split(':');
    return int.parse(parti[0]) * 60 + int.parse(parti[1]);
  }

  // Pulisce interamente il form e lo riporta allo stato iniziale
  void _resetForm() {
    setState(() {
      _clienteSelezionatoId = null;
      _barbiereSelezionatoId = null;
      _servizioSelezionatoId = null;
      _barbiereData = null;
      _servizioData = null;
      _dataInizio = DateTime.now();
      _orarioSelezionato = const TimeOfDay(hour: 15, minute: 30);
      _numeroSettimanetot = 4;
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

      List<_EsitoPrenotazione> tempRisultati = [];

      for (int i = 0; i < _numeroSettimanetot; i++) {
        DateTime giornoCorrente = _dataInizio.add(Duration(days: i * 7));
        String dataStr = _formattaData(giornoCorrente);

        // 0. CONTROLLO ORARIO GIÀ PASSATO (Se è la data di oggi ed è già trascorso l'orario)
        if (dataStr == oggiDataStr && inizioNuovoMinuti <= minutiAttuali) {
          tempRisultati.add(_EsitoPrenotazione(
              data: giornoCorrente,
              slot: slotStr,
              isOccupato: true,
              motivo: "Orario già passato"
          ));
          continue;
        }

        // 1. Controlla eccezioni calendario o chiusure
        final eccezioneDoc = await db.collection('calendar_exceptions').doc(dataStr).get();
        if (eccezioneDoc.exists && eccezioneDoc.data()?['status'] == 'chiuso') {
          tempRisultati.add(_EsitoPrenotazione(data: giornoCorrente, slot: slotStr, isChiuso: true, motivo: "Giorno festivo/chiuso"));
          continue;
        }

        // 2. Controlla se il barbiere è assente in quel giorno
        final barberExDoc = await db.collection('barber_exceptions').doc("${dataStr}_$barberId").get();
        if (barberExDoc.exists && barberExDoc.data()?['type'] == 'assente') {
          tempRisultati.add(_EsitoPrenotazione(data: giornoCorrente, slot: slotStr, isChiuso: true, motivo: "Operatore assente"));
          continue;
        }

        // 3. Controlla sovrapposizione con appuntamenti esistenti su Firestore
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

      // Formatta le date non riuscite per la lettura umana
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
                    _resetForm(); // Pulisce la schermata e la riporta allo stato iniziale
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
                    _resetForm(); // Pulisce la schermata e la riporta allo stato iniziale
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

    return Scaffold(
      backgroundColor: coloreSfondo,
      appBar: AppBar(
        title: const Text('PROGRAMMA PERIODICO', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 18)),
        backgroundColor: constColorVerde,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. SELEZIONE CLIENTE
            Text('1. Seleziona Cliente:', style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').where('role', isNotEqualTo: 'barbiere').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator(color: Color(0xFFE2B13C));
                final clienti = snapshot.data!.docs;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(color: coloreCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade400)),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      hint: Text('Scegli un cliente', style: TextStyle(color: isDarkMode ? Colors.white60 : Colors.black54)),
                      value: _clienteSelezionatoId,
                      items: clienti.map((doc) {
                        final d = doc.data() as Map<String, dynamic>;
                        return DropdownMenuItem<String>(
                          value: doc.id,
                          child: Text("${d['name'] ?? d['nome'] ?? 'Senza Nome'} (${d['email'] ?? 'No email'})", style: TextStyle(color: coloreTesto)),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _clienteSelezionatoId = val;
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

            // 2. SELEZIONE OPERATORE & SERVIZIO
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('3. Servizio:', style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 6),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('services').snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) return const SizedBox.shrink();
                          final servizi = snapshot.data!.docs;

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(color: coloreCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade400)),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                isExpanded: true,
                                hint: const Text('Servizio'),
                                value: _servizioSelezionatoId,
                                items: servizi.map((doc) {
                                  final d = doc.data() as Map<String, dynamic>;
                                  return DropdownMenuItem<String>(
                                    value: doc.id,
                                    child: Text("${d['name']} (${d['duration']}m)", style: TextStyle(color: coloreTesto)),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    final selectedDoc = servizi.firstWhere((element) => element.id == val);
                                    setState(() {
                                      _servizioSelezionatoId = val;
                                      _servizioData = selectedDoc.data() as Map<String, dynamic>;
                                      _analisiRisultati.clear();
                                    });
                                  }
                                },
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // 3. REGOLAZIONE DATA INIZIO, ORA E SETTIMANE
            Card(
              color: coloreCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      title: Text('Data prima seduta', style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold)),
                      subtitle: Text(DateFormat('EEEE dd MMMM yyyy', 'it_IT').format(_dataInizio)),
                      trailing: Icon(Icons.calendar_month, color: constColorOro),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _dataInizio,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 180)),
                        );
                        if (picked != null) {
                          setState(() {
                            _dataInizio = picked;
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
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Durata ricorrenza:', style: TextStyle(color: coloreTesto, fontWeight: FontWeight.bold)),
                          DropdownButton<int>(
                            value: _numeroSettimanetot,
                            dropdownColor: coloreCard,
                            items: [2, 3, 4, 6, 8, 12, 16, 24].map((num) {
                              return DropdownMenuItem<int>(
                                value: num,
                                child: Text('$num settimane', style: TextStyle(color: coloreTesto)),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _numeroSettimanetot = val;
                                  _analisiRisultati.clear();
                                });
                              }
                            },
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
    );
  }
}