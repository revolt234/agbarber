import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GestioneOrariScreen extends StatefulWidget {
  const GestioneOrariScreen({super.key});

  @override
  State<GestioneOrariScreen> createState() => _GestioneOrariScreenState();
}

class _GestioneOrariScreenState extends State<GestioneOrariScreen> {
  bool _isLoading = true;

  // Lista per l'interfaccia grafica (User Friendly)
  final List<String> _giorniUi = [
    'Lunedì', 'Martedì', 'Mercoledì', 'Giovedì', 'Venerdì', 'Sabato', 'Domenica'
  ];

  final Map<String, Map<String, dynamic>> _orariSettimanali = {};

  @override
  void initState() {
    super.initState();
    _caricaOrari();
  }

  Future<void> _caricaOrari() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('settings').doc('orari_negozio').get();

      if (doc.exists) {
        final dati = doc.data()!;
        for (var giorno in _giorniUi) {
          String chiaveDb = giorno.toLowerCase();
          if (dati.containsKey(chiaveDb)) {
            _orariSettimanali[giorno] = Map<String, dynamic>.from(dati[chiaveDb]);
          } else {
            // Fallback se manca un singolo giorno nel documento esistente
            _orariSettimanali[giorno] = _generaGiornoDefault(giorno);
          }
        }
      } else {
        // Se il documento non esiste affatto, genera i dati iniziali di default
        for (var giorno in _giorniUi) {
          _orariSettimanali[giorno] = _generaGiornoDefault(giorno);
        }
      }
    } catch (e) {
      debugPrint("Errore nel caricamento orari: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> _generaGiornoDefault(String giorno) {
    bool diBaseAperto = (giorno != 'Lunedì' && giorno != 'Domenica');
    return {
      'isAperto': diBaseAperto,
      'mattina': {'apertura': '09:00', 'chiusura': '13:00'},
      'pomeriggio': {'apertura': '14:30', 'chiusura': '19:30'},
    };
  }

  int _minutiDaStringa(String s) => int.parse(s.split(':')[0]) * 60 + int.parse(s.split(':')[1]);

  Future<void> _selezionaOrario(String giorno, String fascia, bool isApertura) async {
    final String chiaveOrario = isApertura ? 'apertura' : 'chiusura';
    final String orarioAttuale = _orariSettimanali[giorno]![fascia][chiaveOrario] ?? (isApertura ? '09:00' : '13:00');

    final parti = orarioAttuale.split(':');
    final TimeOfDay tempoIniziale = TimeOfDay(hour: int.parse(parti[0]), minute: int.parse(parti[1]));

    final TimeOfDay? tempoScelto = await showTimePicker(
      context: context,
      initialTime: tempoIniziale,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (tempoScelto != null) {
      final int minutiScelti = (tempoScelto.hour * 60) + tempoScelto.minute;
      final int limiteMezzogiorno = 13 * 60; // 13:00 espresso in minuti

      final stringaOra = '${tempoScelto.hour.toString().padLeft(2, '0')}:${tempoScelto.minute.toString().padLeft(2, '0')}';

      // Recuperiamo gli altri orari attuali per fare i controlli incrociati di coerenza
      final String mattInizioStr = _orariSettimanali[giorno]!['mattina']['apertura'] ?? "09:00";
      final String mattFineStr = _orariSettimanali[giorno]!['mattina']['chiusura'] ?? "13:00";
      final String pomInizioStr = _orariSettimanali[giorno]!['pomeriggio']['apertura'] ?? "14:30";
      final String pomFineStr = _orariSettimanali[giorno]!['pomeriggio']['chiusura'] ?? "19:30";

      String? messaggioErrore;

      // --- LOGICA DI VALIDAZIONE RIGIDA ---
      if (fascia == 'mattina') {
        if (isApertura) {
          if (minutiScelti >= _minutiDaStringa(mattFineStr)) {
            messaggioErrore = "L'apertura della mattina deve precedere l'orario di chiusura ($mattFineStr).";
          }
        } else {
          if (minutiScelti > limiteMezzogiorno) {
            messaggioErrore = "Il turno di mattina deve tassativamente chiudere entro le ore 13:00.";
          } else if (minutiScelti <= _minutiDaStringa(mattInizioStr)) {
            messaggioErrore = "La chiusura della mattina deve seguire l'orario di apertura ($mattInizioStr).";
          }
        }
      } else if (fascia == 'pomeriggio') {
        if (isApertura) {
          if (minutiScelti < limiteMezzogiorno) {
            messaggioErrore = "Il turno del pomeriggio non può aprire prima delle ore 13:00.";
          } else if (minutiScelti >= _minutiDaStringa(pomFineStr)) {
            messaggioErrore = "L'apertura del pomeriggio deve precedere l'orario di chiusura ($pomFineStr).";
          }
        } else {
          if (minutiScelti <= _minutiDaStringa(pomInizioStr)) {
            messaggioErrore = "La chiusura del pomeriggio deve seguire l'orario di apertura ($pomInizioStr).";
          }
        }
      }

      if (messaggioErrore != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(messaggioErrore), backgroundColor: Colors.orange),
          );
        }
        return; // Interrompe l'aggiornamento perché l'orario non è valido
      }

      setState(() {
        _orariSettimanali[giorno]![fascia][chiaveOrario] = stringaOra;
      });
    }
  }

  Future<void> _salvaOrari() async {
    setState(() => _isLoading = true);
    try {
      final Map<String, dynamic> datiDaSalvare = {};
      _orariSettimanali.forEach((giorno, mappaDati) {
        datiDaSalvare[giorno.toLowerCase()] = mappaDati;
      });

      await FirebaseFirestore.instance.collection('settings').doc('orari_negozio').set(datiDaSalvare);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Orari updated con successo!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore nel salvataggio: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildOrarioTile(String giorno, String fascia, bool isApertura, Color coloreTesto) {
    final String orario = _orariSettimanali[giorno]![fascia][isApertura ? 'apertura' : 'chiusura'] ?? '--:--';

    return InkWell(
      onTap: () => _selezionaOrario(giorno, fascia, isApertura),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
                isApertura ? Icons.access_time : Icons.access_time_filled,
                color: const Color(0xFFE2B13C),
                size: 20
            ),
            const SizedBox(width: 6),
            Text(
              orario,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: coloreTesto),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color coloreTesto = isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Orari Lavorativi', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF164638),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.save, size: 28),
              onPressed: _salvaOrari,
            )
        ],
      ),
      // MODIFICATO: Avvolto il body in un SafeArea per evitare che la fine della lista scorra sotto i tasti di navigazione
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: _giorniUi.length,
          itemBuilder: (context, index) {
            final giorno = _giorniUi[index];
            final infoGiorno = _orariSettimanali[giorno]!;
            final bool isAperto = infoGiorno['isAperto'] ?? false;

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          giorno,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: coloreTesto),
                        ),
                        Switch(
                          activeThumbColor: const Color(0xFFE2B13C),
                          value: isAperto,
                          onChanged: (valore) {
                            setState(() {
                              _orariSettimanali[giorno]!['isAperto'] = valore;
                            });
                          },
                        ),
                      ],
                    ),
                    if (isAperto) ...[
                      const Divider(),
                      const SizedBox(height: 4),

                      // FASCIA MATTUTINA
                      const Text(
                          "Turno Mattina",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey)
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildOrarioTile(giorno, 'mattina', true, coloreTesto),
                          Icon(Icons.arrow_forward, color: coloreTesto.withValues(alpha: 0.5), size: 18),
                          _buildOrarioTile(giorno, 'mattina', false, coloreTesto),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // FASCIA POMERIDIANA
                      const Text(
                          "Turno Pomeriggio",
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.grey)
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildOrarioTile(giorno, 'pomeriggio', true, coloreTesto),
                          Icon(Icons.arrow_forward, color: coloreTesto.withValues(alpha: 0.5), size: 18),
                          _buildOrarioTile(giorno, 'pomeriggio', false, coloreTesto),
                        ],
                      ),
                    ] else ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                            'Chiuso',
                            style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)
                        ),
                      )
                    ]
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}