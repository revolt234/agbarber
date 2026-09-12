import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class GestioneCalendarioScreen extends StatefulWidget {
  const GestioneCalendarioScreen({super.key});

  @override
  State<GestioneCalendarioScreen> createState() => _GestioneCalendarioScreenState();
}

class _GestioneCalendarioScreenState extends State<GestioneCalendarioScreen> {
  final _notaController = TextEditingController();
  final _notaFocusNode = FocusNode();
  String _statusScelto = 'chiuso';

  bool _turnoMattinaAttivo = true;
  bool _turnoPomeriggioAttivo = true;

  // Set per gestire la selezione multipla degli elementi da eliminare
  final Set<String> _elementiSelezionati = {};
  bool _isModalitaSelezione = false;

  Map<String, dynamic> _orariStraordinari = {
    'mattina': {'apertura': '09:00', 'chiusura': '13:00'},
    'pomeriggio': {'apertura': '14:30', 'chiusura': '19:30'},
  };

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _notaController.dispose();
    _notaFocusNode.dispose();
    super.dispose();
  }

  Future<bool> _controllaConnessioneReale() async {
    if (kIsWeb) return true;
    try {
      final risultato = await FirebaseFirestore.instance.enableNetwork().then((_) => true).catchError((_) => false);
      return risultato;
    } catch (_) {
      return false;
    }
  }

  void _resettaSelezioneTesto(TextEditingController controller) {
    final text = controller.text;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    if (!kIsWeb) {
      SystemChannels.textInput.invokeMethod('TextInput.show');
    }
  }

  // 1. SELEZIONE SINGOLO GIORNO
  Future<void> _selezionaSingoloGiorno() async {
    final DateTime ora = DateTime.now();
    final DateTime? giornoScelto = await showDatePicker(
      context: context,
      initialDate: ora,
      firstDate: ora,
      lastDate: ora.add(const Duration(days: 365)),
      helpText: 'SELEZIONA SINGOLO GIORNO',
      cancelText: 'ANNULLA',
      confirmText: 'OK',
    );

    if (giornoScelto != null) {
      _mostraDialogConfiguraGiorno(DateTimeRange(start: giornoScelto, end: giornoScelto));
    }
  }

  // 2. SELEZIONE PERIODO
  Future<void> _selezionaPeriodo() async {
    final DateTime ora = DateTime.now();
    final DateTimeRange? intervalloScelto = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: ora,
        end: ora.add(const Duration(days: 1)),
      ),
      firstDate: ora,
      lastDate: ora.add(const Duration(days: 365)),
      helpText: 'SELEZIONA UN PERIODO',
      cancelText: 'ANNULLA',
      confirmText: 'CONFERMA',
      saveText: 'OK',
    );

    if (intervalloScelto != null) {
      _mostraDialogConfiguraGiorno(intervalloScelto);
    }
  }

  Future<void> _cambiaOrarioStraordinario(BuildContext context, StateSetter setDialogState, String fascia, String tipo) async {
    final stringaAttuale = _orariStraordinari[fascia][tipo];
    final parti = stringaAttuale.split(':');
    final tempoIniziale = TimeOfDay(hour: int.parse(parti[0]), minute: int.parse(parti[1]));

    final TimeOfDay? tempoScelto = await showTimePicker(
      context: context,
      initialTime: tempoIniziale,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );

    if (tempoScelto != null) {
      setDialogState(() {
        final int minutiScelti = tempoScelto.hour * 60 + tempoScelto.minute;

        if (tipo == 'apertura') {
          final partiChiusura = _orariStraordinari[fascia]['chiusura'].split(':');
          final int minutiChiusuraAttuali = int.parse(partiChiusura[0]) * 60 + int.parse(partiChiusura[1]);

          _orariStraordinari[fascia]['apertura'] = '${tempoScelto.hour.toString().padLeft(2, '0')}:${tempoScelto.minute.toString().padLeft(2, '0')}';

          if (minutiScelti >= minutiChiusuraAttuali) {
            final int nuoviMinutiChiusura = (minutiScelti + 30).clamp(0, 1439);
            final int nuovaOraChiusura = nuoviMinutiChiusura ~/ 60;
            final int nuoviMinutiRestanti = nuoviMinutiChiusura % 60;
            _orariStraordinari[fascia]['chiusura'] = '${nuovaOraChiusura.toString().padLeft(2, '0')}:${nuoviMinutiRestanti.toString().padLeft(2, '0')}';
          }

          if (fascia == 'pomeriggio' && _turnoMattinaAttivo) {
            final partiChiusuraMattina = _orariStraordinari['mattina']['chiusura'].split(':');
            final int minutiChiusuraMattina = int.parse(partiChiusuraMattina[0]) * 60 + int.parse(partiChiusuraMattina[1]);

            if (minutiScelti <= minutiChiusuraMattina) {
              final int nuoviMinutiMattina = (minutiScelti - 30).clamp(0, 1439);
              final int oraM = nuoviMinutiMattina ~/ 60;
              final int minM = nuoviMinutiMattina % 60;
              _orariStraordinari['mattina']['chiusura'] = '${oraM.toString().padLeft(2, '0')}:${minM.toString().padLeft(2, '0')}';
            }
          }
        } else {
          final partiApertura = _orariStraordinari[fascia]['apertura'].split(':');
          final int minutiAperturaAttuali = int.parse(partiApertura[0]) * 60 + int.parse(partiApertura[1]);

          if (minutiScelti <= minutiAperturaAttuali) {
            final int nuoviMinutiChiusura = (minutiAperturaAttuali + 30).clamp(0, 1439);
            final int nuovaOraChiusura = nuoviMinutiChiusura ~/ 60;
            final int nuoviMinutiRestanti = nuoviMinutiChiusura % 60;
            _orariStraordinari[fascia]['chiusura'] = '${nuovaOraChiusura.toString().padLeft(2, '0')}:${nuoviMinutiRestanti.toString().padLeft(2, '0')}';
          } else {
            _orariStraordinari[fascia]['chiusura'] = '${tempoScelto.hour.toString().padLeft(2, '0')}:${tempoScelto.minute.toString().padLeft(2, '0')}';
          }

          if (fascia == 'mattina' && _turnoPomeriggioAttivo) {
            final int minutiChiusuraMattinaEffettivi = int.parse(_orariStraordinari['mattina']['chiusura'].split(':')[0]) * 60 + int.parse(_orariStraordinari['mattina']['chiusura'].split(':')[1]);
            final partiAperturaPomeriggio = _orariStraordinari['pomeriggio']['apertura'].split(':');
            final int minutiAperturaPomeriggio = int.parse(partiAperturaPomeriggio[0]) * 60 + int.parse(partiAperturaPomeriggio[1]);

            if (minutiChiusuraMattinaEffettivi >= minutiAperturaPomeriggio) {
              final int nuoviMinutiPomeriggio = (minutiChiusuraMattinaEffettivi + 30).clamp(0, 1439);
              final int oraP = nuoviMinutiPomeriggio ~/ 60;
              final int minP = nuoviMinutiPomeriggio % 60;
              _orariStraordinari['pomeriggio']['apertura'] = '${oraP.toString().padLeft(2, '0')}:${minP.toString().padLeft(2, '0')}';
            }
          }
        }
      });
    }
  }

  void _mostraDialogConfiguraGiorno(DateTimeRange intervallo) {
    _notaController.clear();
    _statusScelto = 'chiuso';
    _turnoMattinaAttivo = true;
    _turnoPomeriggioAttivo = true;
    _orariStraordinari = {
      'mattina': {'apertura': '09:00', 'chiusura': '13:00'},
      'pomeriggio': {'apertura': '14:30', 'chiusura': '19:30'},
    };

    final String inizioFormattato = "${intervallo.start.day.toString().padLeft(2, '0')}/${intervallo.start.month.toString().padLeft(2, '0')}/${intervallo.start.year}";
    final String fineFormattata = "${intervallo.end.day.toString().padLeft(2, '0')}/${intervallo.end.month.toString().padLeft(2, '0')}/${intervallo.end.year}";

    final bool eSingoloGiorno = intervallo.start.year == intervallo.end.year &&
        intervallo.start.month == intervallo.end.month &&
        intervallo.start.day == intervallo.end.day;

    final String titoloDialog = eSingoloGiorno
        ? 'Configura Giorno ($inizioFormattato)'
        : 'Configura Periodo ($inizioFormattato - $fineFormattata)';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(titoloDialog, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _statusScelto,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                      value: 'chiuso',
                      child: Text('Chiuso (es. Ferie/Festa)', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'aperto',
                      child: Text('Apertura Straordinaria', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  onChanged: (valore) {
                    if (valore != null) {
                      setDialogState(() => _statusScelto = valore);
                    }
                  },
                ),
                if (_statusScelto == 'aperto') ...[
                  const SizedBox(height: 16),
                  const Text("Orari Apertura Straordinaria", style: TextStyle(fontWeight: FontWeight.bold)),
                  const Divider(),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Turno Mattina", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    value: _turnoMattinaAttivo,
                    activeColor: const Color(0xFF164638),
                    onChanged: (val) {
                      setDialogState(() {
                        if (!val && !_turnoPomeriggioAttivo) {
                          _turnoPomeriggioAttivo = true;
                        }
                        _turnoMattinaAttivo = val;
                      });
                    },
                  ),
                  if (_turnoMattinaAttivo)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () => _cambiaOrarioStraordinario(context, setDialogState, 'mattina', 'apertura'),
                          child: Text(_orariStraordinari['mattina']['apertura'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        const Icon(Icons.arrow_forward, size: 16),
                        TextButton(
                          onPressed: () => _cambiaOrarioStraordinario(context, setDialogState, 'mattina', 'chiusura'),
                          child: Text(_orariStraordinari['mattina']['chiusura'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),

                  const SizedBox(height: 8),

                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Turno Pomeriggio", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    value: _turnoPomeriggioAttivo,
                    activeColor: const Color(0xFF164638),
                    onChanged: (val) {
                      setDialogState(() {
                        if (!val && !_turnoMattinaAttivo) {
                          _turnoMattinaAttivo = true;
                        }
                        _turnoPomeriggioAttivo = val;
                      });
                    },
                  ),
                  if (_turnoPomeriggioAttivo)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton(
                          onPressed: () => _cambiaOrarioStraordinario(context, setDialogState, 'pomeriggio', 'apertura'),
                          child: Text(_orariStraordinari['pomeriggio']['apertura'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                        const Icon(Icons.arrow_forward, size: 16),
                        TextButton(
                          onPressed: () => _cambiaOrarioStraordinario(context, setDialogState, 'pomeriggio', 'chiusura'),
                          child: Text(_orariStraordinari['pomeriggio']['chiusura'], style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _notaController,
                  focusNode: _notaFocusNode,
                  onTap: () => _resettaSelezioneTesto(_notaController),
                  decoration: const InputDecoration(
                    labelText: 'Motivazione (es. Ferie, Santo Patrono)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF164638)),
              onPressed: () => _salvaEccezioneFirebaseIntervallo(intervallo),
              child: const Text('Salva', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _salvaEccezioneFirebaseIntervallo(DateTimeRange intervallo) async {
    try {
      final String startDateStr = "${intervallo.start.year}-${intervallo.start.month.toString().padLeft(2, '0')}-${intervallo.start.day.toString().padLeft(2, '0')}";
      final String endDateStr = "${intervallo.end.year}-${intervallo.end.month.toString().padLeft(2, '0')}-${intervallo.end.day.toString().padLeft(2, '0')}";

      final bool isPeriodo = startDateStr != endDateStr;
      final String docId = isPeriodo ? "${startDateStr}_$endDateStr" : startDateStr;

      final Map<String, dynamic> mappaSalvataggio = {
        'startDate': startDateStr,
        'endDate': endDateStr,
        'date': isPeriodo ? "$startDateStr -> $endDateStr" : startDateStr,
        'isPeriod': isPeriodo,
        'status': _statusScelto,
        'nota': _notaController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (_statusScelto == 'aperto') {
        mappaSalvataggio['mattina'] = _turnoMattinaAttivo ? _orariStraordinari['mattina'] : null;
        mappaSalvataggio['pomeriggio'] = _turnoPomeriggioAttivo ? _orariStraordinari['pomeriggio'] : null;
      }

      await FirebaseFirestore.instance
          .collection('calendar_exceptions')
          .doc(docId)
          .set(mappaSalvataggio);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore durante il salvataggio: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confermaEliminazioneSelezionati() async {
    if (_elementiSelezionati.isEmpty) return;

    final int conteggio = _elementiSelezionati.length;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Conferma eliminazione'),
        content: Text('Sei sicuro di voler rimuovere $conteggio eccezioni selezionate?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogContext);

              final bool connessionePresente = await _controllaConnessioneReale();
              if (!connessionePresente) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Impossibile eliminare: connessione internet assente o instabile.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                return;
              }

              try {
                final WriteBatch batch = FirebaseFirestore.instance.batch();
                for (String docId in _elementiSelezionati) {
                  final DocumentReference ref = FirebaseFirestore.instance.collection('calendar_exceptions').doc(docId);
                  batch.delete(ref);
                }
                await batch.commit();

                setState(() {
                  _elementiSelezionati.clear();
                  _isModalitaSelezione = false;
                });

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Eccezioni rimosse con successo.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Errore durante la rimozione: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Elimina', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _confermaRimuoviEccezione(String docId, String data) async {
    bool isEliminazioneInCorso = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: !isEliminazioneInCorso,
              child: AlertDialog(
                title: const Text('Conferma eliminazione'),
                content: Text('Sei sicuro di voler rimuovere l\'eccezione per $data?'),
                actions: [
                  TextButton(
                    onPressed: isEliminazioneInCorso ? null : () => Navigator.pop(dialogContext),
                    child: const Text('Annulla'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: isEliminazioneInCorso
                        ? null
                        : () async {
                      setDialogState(() {
                        isEliminazioneInCorso = true;
                      });

                      final bool connessionePresente = await _controllaConnessioneReale();
                      if (!connessionePresente) {
                        setDialogState(() {
                          isEliminazioneInCorso = false;
                        });

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Impossibile eliminare: connessione internet assente o instabile.'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                        return;
                      }

                      try {
                        await FirebaseFirestore.instance
                            .collection('calendar_exceptions')
                            .doc(docId)
                            .delete();

                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Eccezione rimossa con successo.'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        setDialogState(() {
                          isEliminazioneInCorso = false;
                        });

                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Errore durante la rimozione: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    child: isEliminazioneInCorso
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : const Text('Elimina', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color coloreTesto = isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isModalitaSelezione ? '${_elementiSelezionati.length} Selezionati' : 'Eccezioni Calendario',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF164638),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isModalitaSelezione) ...[
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.white),
              onPressed: _confermaEliminazioneSelezionati,
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                setState(() {
                  _isModalitaSelezione = false;
                  _elementiSelezionati.clear();
                });
              },
            ),
          ]
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('calendar_exceptions').orderBy('date', descending: false).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                  'Nessuna eccezione impostata.\nUsa i pulsanti in basso per gestire i singoli giorni o i periodi.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final eccezioni = snapshot.data!.docs;
          final bool tuttiSelezionati = _elementiSelezionati.length == eccezioni.length;

          return Column(
            children: [
              Container(
                color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.grey.shade200,
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  children: [
                    Checkbox(
                      value: tuttiSelezionati,
                      activeColor: const Color(0xFF164638),
                      onChanged: (bool? checked) {
                        setState(() {
                          if (checked == true) {
                            _isModalitaSelezione = true;
                            _elementiSelezionati.clear();
                            for (var doc in eccezioni) {
                              _elementiSelezionati.add(doc.id);
                            }
                          } else {
                            _elementiSelezionati.clear();
                            _isModalitaSelezione = false;
                          }
                        });
                      },
                    ),
                    Text(
                      'Seleziona Tutti (${eccezioni.length})',
                      style: TextStyle(fontWeight: FontWeight.bold, color: coloreTesto),
                    ),
                    const Spacer(),
                    if (_elementiSelezionati.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.delete_sweep, color: Colors.red),
                        onPressed: _confermaEliminazioneSelezionati,
                      ),
                  ],
                ),
              ),

              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: eccezioni.length,
                  itemBuilder: (context, index) {
                    final doc = eccezioni[index];
                    final dati = doc.data() as Map<String, dynamic>;

                    final String dataText = dati['date'] ?? dati['startDate'] ?? '';
                    final String status = dati['status'] ?? 'chiuso';
                    final String nota = dati['nota'] ?? '';
                    final bool isChiuso = status == 'chiuso';
                    final bool isSelezionato = _elementiSelezionati.contains(doc.id);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      color: isSelezionato ? (isDarkMode ? const Color(0xFF2C3E35) : Colors.green.shade50) : null,
                      child: ListTile(
                        leading: _isModalitaSelezione
                            ? Checkbox(
                          value: isSelezionato,
                          activeColor: const Color(0xFF164638),
                          onChanged: (bool? val) {
                            setState(() {
                              if (val == true) {
                                _elementiSelezionati.add(doc.id);
                              } else {
                                _elementiSelezionati.remove(doc.id);
                                if (_elementiSelezionati.isEmpty) {
                                  _isModalitaSelezione = false;
                                }
                              }
                            });
                          },
                        )
                            : CircleAvatar(
                          backgroundColor: isChiuso ? Colors.red.shade100 : Colors.green.shade100,
                          child: Icon(
                            isChiuso ? Icons.block : Icons.event_available,
                            color: isChiuso ? Colors.red : Colors.green,
                          ),
                        ),
                        title: Text(
                          dataText,
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: coloreTesto),
                        ),
                        subtitle: Text(
                          '${isChiuso ? "CHIUSO" : "APERTURA STRAORDINARIA"} ${nota.isNotEmpty ? "- $nota" : ""}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: isChiuso ? Colors.red : Colors.green, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        onLongPress: () {
                          setState(() {
                            _isModalitaSelezione = true;
                            _elementiSelezionati.add(doc.id);
                          });
                        },
                        trailing: !_isModalitaSelezione
                            ? IconButton(
                          icon: const Icon(Icons.delete, color: Colors.grey),
                          onPressed: () => _confermaRimuoviEccezione(doc.id, dataText),
                        )
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      // PULSANTI SEPARATI PER SINGOLO GIORNO E PERIODO
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'btnSingolo',
            backgroundColor: const Color(0xFF164638),
            onPressed: _selezionaSingoloGiorno,
            icon: const Icon(Icons.today, color: Colors.white),
            label: const Text('Singolo Giorno', style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'btnPeriodo',
            backgroundColor: const Color(0xFF164638),
            onPressed: _selezionaPeriodo,
            icon: const Icon(Icons.date_range, color: Colors.white),
            label: const Text('Periodo', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}