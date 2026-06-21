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

  Future<void> _selezionaOrario(String giorno, String fascia, bool isApertura) async {
    final String chiaveOrario = isApertura ? 'apertura' : 'chiusura';
    final String orarioAttuale = _orariSettimanali[giorno]![fascia][chiaveOrario] ?? (isApertura ? '09:00' : '13:00');

    final parti = orarioAttuale.split(':');
    final TimeOfDay tempoIniziale = TimeOfDay(hour: int.parse(parti[0]), minute: int.parse(parti[1]));

    final TimeOfDay? tempoScelto = await showTimePicker(
      context: context,
      initialTime: tempoIniziale,
    );

    if (tempoScelto != null) {
      final stringaOra = '${tempoScelto.hour.toString().padLeft(2, '0')}:${tempoScelto.minute.toString().padLeft(2, '0')}';
      setState(() {
        _orariSettimanali[giorno]![fascia][chiaveOrario] = stringaOra;
      });
    }
  }

  Future<void> _salvaOrari() async {
    setState(() => _isLoading = true);
    try {
      // Convertiamo la mappa con le chiavi in minuscolo prima di salvare su Firestore
      final Map<String, dynamic> datiDaSalvare = {};
      _orariSettimanali.forEach((giorno, mappaDati) {
        datiDaSalvare[giorno.toLowerCase()] = mappaDati;
      });

      await FirebaseFirestore.instance.collection('settings').doc('orari_negozio').set(datiDaSalvare);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Orari aggiornati con successo!'), backgroundColor: Colors.green),
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
      body: _isLoading
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
    );
  }
}