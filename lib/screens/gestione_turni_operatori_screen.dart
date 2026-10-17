import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class GestioneTurniOperatoriScreen extends StatefulWidget {
  const GestioneTurniOperatoriScreen({super.key});

  @override
  State<GestioneTurniOperatoriScreen> createState() =>
      _GestioneTurniOperatoriScreenState();
}

class _GestioneTurniOperatoriScreenState
    extends State<GestioneTurniOperatoriScreen> {
  String? _barbiereSelezionatoId;
  String? _barbiereSelezionatoNome;
  String _tipoEccezione = 'assente'; // assente o mezza_giornata
  String _fasciaOraria = 'mattina'; // mattina o pomeriggio

  // Helper per verificare la presenza di una connessione Internet reale
  Future<bool> _controllaConnessioneReale() async {
    if (kIsWeb) return true;
    try {
      final risultato = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      return risultato.isNotEmpty && risultato[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // Apre il calendario per scegliere la data dell'eccezione
  Future<void> _selezionaDataEccezione() async {
    if (_barbiereSelezionatoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleziona prima un operatore o Tutti gli operatori!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final DateTime? dataScelta = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('it', 'IT'),
      builder: (context, child) {
        return Theme(
          data: isDarkMode
              ? ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFFE2B13C),
              onPrimary: Colors.black,
              surface: Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Color(0xFF1E1E1E)),
          )
              : ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF164638),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
            dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
          ),
          child: child!,
        );
      },
    );

    if (dataScelta != null) {
      final String dataFormattata =
          "${dataScelta.year}-${dataScelta.month.toString().padLeft(2, '0')}-${dataScelta.day.toString().padLeft(2, '0')}";
      _mostraConfermaImpostazioneRegola(dataFormattata);
    }
  }

  // Mostra dialogo di conferma prima di impostare la regola e cancellare le prenotazioni
  void _mostraConfermaImpostazioneRegola(String dataFormattata) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    String tipoDesc = _tipoEccezione == 'assente'
        ? 'Assente tutto il giorno'
        : 'Mezza giornata (Solo $_fasciaOraria)';

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text(
            'Conferma Impostazione Regola',
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Stai impostando "$tipoDesc" per il giorno $dataFormattata.\n\nAttenzione: questa operazione cancellerà tutte le eventuali prenotazioni dei clienti presenti in quel periodo. Vuoi procedere?',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Annulla', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF164638)),
              onPressed: () {
                Navigator.pop(dialogContext);
                _salvaEccezioneOperatore(dataFormattata);
              },
              child: const Text('Conferma', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // Salva l'eccezione dell'operatore su Firestore e rimuove le prenotazioni conflittuali
  Future<void> _salvaEccezioneOperatore(String dataFormattata) async {
    try {
      List<String> barberIdsToUpdate = [];
      if (_barbiereSelezionatoId == 'tutti') {
        final barbersSnap = await FirebaseFirestore.instance.collection('barbers').get();
        for (var doc in barbersSnap.docs) {
          barberIdsToUpdate.add(doc.id);
        }
      } else if (_barbiereSelezionatoId != null) {
        barberIdsToUpdate.add(_barbiereSelezionatoId!);
      }

      if (barberIdsToUpdate.isEmpty) return;

      WriteBatch batch = FirebaseFirestore.instance.batch();

      for (String bId in barberIdsToUpdate) {
        final String docId = "${dataFormattata}_$bId";
        final docRef = FirebaseFirestore.instance.collection('barber_exceptions').doc(docId);

        batch.set(docRef, {
          'barberId': bId,
          'barberName': _barbiereSelezionatoId == 'tutti' ? 'Tutti gli operatori' : _barbiereSelezionatoNome,
          'date': dataFormattata,
          'type': _tipoEccezione,
          'fascia': _tipoEccezione == 'mezza_giornata' ? _fasciaOraria : null,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      // Chiama la funzione per eliminare le prenotazioni dei clienti presenti nell'arco temporale
      await _eliminaPrenotazioniConflittuali(dataFormattata, barberIdsToUpdate);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Turno operatore modificato e prenotazioni conflittuali eliminate!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Funzione per eliminare le prenotazioni dei clienti presenti nell'arco temporale interessato
  Future<void> _eliminaPrenotazioniConflittuali(String dataFormattata, List<String> barberIds) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('appointments')
          .where('date', isEqualTo: dataFormattata)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      int countDeleted = 0;

      for (var doc in query.docs) {
        final dataApp = doc.data();
        final String? bId = dataApp['barberId'];
        final String? slot = dataApp['slot'];

        if (bId == null || !barberIds.contains(bId)) continue;

        bool daEliminare = false;

        if (_tipoEccezione == 'assente') {
          daEliminare = true;
        } else if (_tipoEccezione == 'mezza_giornata' && slot != null) {
          int minutiSlot = _minutiDaStringa(slot);
          if (_fasciaOraria == 'mattina') {
            if (minutiSlot >= 13 * 60) {
              daEliminare = true;
            }
          } else if (_fasciaOraria == 'pomeriggio') {
            if (minutiSlot < 13 * 60) {
              daEliminare = true;
            }
          }
        }

        if (daEliminare) {
          batch.delete(doc.reference);
          countDeleted++;
        }
      }

      if (countDeleted > 0) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint("Errore eliminazione prenotazioni: $e");
    }
  }

  int _minutiDaStringa(String s) {
    try {
      final parti = s.split(':');
      return int.parse(parti[0]) * 60 + int.parse(parti[1]);
    } catch (_) {
      return 0;
    }
  }

  // Mostra dialogo di conferma prima dell'eliminazione dell'eccezione singola
  void _mostraConfermaEliminazione(String docId, String nomeOperatore, String data) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool isEliminazioneInCorso = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: !isEliminazioneInCorso,
              child: AlertDialog(
                backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                title: Text(
                  'Conferma Eliminazione',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                content: Text(
                  'Sei sicuro di voler rimuovere la modifica al turno per $nomeOperatore in data $data?',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white70 : Colors.black87,
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isEliminazioneInCorso ? null : () => Navigator.pop(dialogContext),
                    child: const Text(
                      'Annulla',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                    ),
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
                            .collection('barber_exceptions')
                            .doc(docId)
                            .delete();

                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Eccezione turno rimossa con successo.'),
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
                              content: Text('Errore durante l\'eliminazione: $e'),
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
                        : const Text(
                      'Elimina',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Funzione per eliminare tutte le eccezioni globali associate a una data specifica
  Future<void> _eliminaTutteEccezioniGiorno(String data) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('barber_exceptions')
          .where('date', isEqualTo: data)
          .where('barberName', isEqualTo: 'Tutti gli operatori')
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in query.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Eccezione globale rimossa con successo.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Errore eliminazione multipla: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color coloreTesto = isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Turni Operatori',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF164638),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // 1. Menu a tendina per scegliere l'operatore (con opzione Tutti gli operatori)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: StreamBuilder<QuerySnapshot>(
              stream:
              FirebaseFirestore.instance.collection('barbers').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final barbieri = snapshot.data!.docs;

                List<DropdownMenuItem<String>> items = [
                  const DropdownMenuItem<String>(
                    value: 'tutti',
                    child: Text(
                      'Tutti gli operatori',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ];

                for (var doc in barbieri) {
                  final dati = doc.data() as Map<String, dynamic>;
                  items.add(
                    DropdownMenuItem<String>(
                      value: doc.id,
                      child: Text(
                        dati['name'] ?? '',
                        style: TextStyle(color: coloreTesto),
                      ),
                    ),
                  );
                }

                return DropdownButtonFormField<String>(
                  hint: Text(
                    'Seleziona Operatore',
                    style: TextStyle(color: coloreTesto),
                  ),
                  dropdownColor:
                  isDarkMode ? Colors.grey.shade900 : Colors.white,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                  initialValue: _barbiereSelezionatoId,
                  items: items,
                  onChanged: (idScelto) {
                    if (idScelto == null) return;
                    if (idScelto == 'tutti') {
                      setState(() {
                        _barbiereSelezionatoId = 'tutti';
                        _barbiereSelezionatoNome = 'Tutti gli operatori';
                      });
                    } else {
                      final docScelto =
                      barbieri.firstWhere((d) => d.id == idScelto);
                      setState(() {
                        _barbiereSelezionatoId = idScelto;
                        _barbiereSelezionatoNome = (docScelto.data()
                        as Map<String, dynamic>)['name'];
                      });
                    }
                  },
                );
              },
            ),
          ),

          // 2. Configurazione eccezione (Assente / Mezza giornata)
          if (_barbiereSelezionatoId != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      RadioGroup<String>(
                        groupValue: _tipoEccezione,
                        onChanged: (val) {
                          if (val != null) setState(() => _tipoEccezione = val);
                        },
                        child: Column(
                          children: [
                            RadioListTile<String>(
                              title: const Text('Assente tutto il giorno'),
                              value: 'assente',
                            ),
                            RadioListTile<String>(
                              title: const Text('Lavora Mezza Giornata (Turno)'),
                              value: 'mezza_giornata',
                            ),
                          ],
                        ),
                      ),
                      if (_tipoEccezione == 'mezza_giornata') ...[
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            ChoiceChip(
                              label: const Text('Solo Mattina'),
                              selected: _fasciaOraria == 'mattina',
                              onSelected: (sec) {
                                if (sec) {
                                  setState(() => _fasciaOraria = 'mattina');
                                }
                              },
                            ),
                            ChoiceChip(
                              label: const Text('Solo Pomeriggio'),
                              selected: _fasciaOraria == 'pomeriggio',
                              onSelected: (sec) {
                                if (sec) {
                                  setState(() => _fasciaOraria = 'pomeriggio');
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF164638),
                        ),
                        onPressed: _selezionaDataEccezione,
                        icon: const Icon(
                          Icons.calendar_month,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Scegli Giorno sul Calendario',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const Padding(
            padding: EdgeInsets.only(top: 16.0, left: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Eccezioni Attive:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),

          // 3. Elenco delle eccezioni degli operatori attive (con raggruppamento visivo)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('barber_exceptions')
                  .orderBy('date')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('Nessuna eccezione impostata per lo staff.'),
                  );
                }

                final tuttiIdocs = snapshot.data!.docs;

                Map<String, DocumentSnapshot> eccezioniUniche = {};
                for (var doc in tuttiIdocs) {
                  final dati = doc.data() as Map<String, dynamic>;
                  final data = dati['date'] ?? '';
                  final tipo = dati['type'] ?? '';
                  final barberName = dati['barberName'] ?? '';

                  if (barberName == 'Tutti gli operatori') {
                    eccezioniUniche['tutti_${data}_$tipo'] = doc;
                  } else {
                    eccezioniUniche[doc.id] = doc;
                  }
                }

                final eccezioni = eccezioniUniche.values.toList();

                return ListView.builder(
                  itemCount: eccezioni.length,
                  itemBuilder: (context, index) {
                    final doc = eccezioni[index];
                    final dati = doc.data() as Map<String, dynamic>;

                    final String nome = dati['barberName'] ?? '';
                    final String data = dati['date'] ?? '';
                    final String tipo = dati['type'] ?? '';
                    final String? fascia = dati['fascia'];

                    String dettaglioText =
                    tipo == 'assente'
                        ? 'Assente'
                        : 'Lavora solo di $fascia';

                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: const Icon(
                          Icons.person_off,
                          color: Colors.orange,
                        ),
                        title: Text(
                          '$nome - $data',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          dettaglioText,
                          style: TextStyle(
                            color: tipo == 'assente' ? Colors.red : Colors.blue,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.grey),
                          onPressed: () {
                            if (nome == 'Tutti gli operatori') {
                              _eliminaTutteEccezioniGiorno(data);
                            } else {
                              _mostraConfermaEliminazione(doc.id, nome, data);
                            }
                          },
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}