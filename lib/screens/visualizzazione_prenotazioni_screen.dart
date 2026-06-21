import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class VisualizzazionePrenotazioniScreen extends StatefulWidget {
  const VisualizzazionePrenotazioniScreen({super.key});

  @override
  State<VisualizzazionePrenotazioniScreen> createState() => _VisualizzazionePrenotazioniScreenState();
}

class _VisualizzazionePrenotazioniScreenState extends State<VisualizzazionePrenotazioniScreen> {
  DateTime _dataSelezionata = DateTime.now();
  String? _operatoreSelezionato; // null significa "Tutti"

  // Colori del brand AG Barber
  final Color agVerde = const Color(0xFF164638);
  final Color agOro = const Color(0xFFE2B13C);

  // Formatta la data per Firestore (es: "2026-06-21")
  String get _dataString => DateFormat('yyyy-MM-dd').format(_dataSelezionata);

  Future<void> _selezionaData(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dataSelezionata,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _dataSelezionata) {
      setState(() {
        _dataSelezionata = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AGENDA APPUNTAMENTI',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1, color: Colors.white),
        ),
        backgroundColor: agVerde,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 1. SELETTORE DATA GIORNALIERA
          Container(
            // Nuova riga corretta:
            color: agVerde.withValues(alpha: 0.05),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(Icons.chevron_left, color: agVerde, size: 30),
                  onPressed: () {
                    setState(() => _dataSelezionata = _dataSelezionata.subtract(const Duration(days: 1)));
                  },
                ),
                TextButton.icon(
                  onPressed: () => _selezionaData(context),
                  icon: Icon(Icons.calendar_today, color: agOro),
                  label: Text(
                    DateFormat('EEEE d MMMM yyyy', 'it_IT').format(_dataSelezionata).toUpperCase(),
                    style: TextStyle(color: agVerde, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right, color: agVerde, size: 30),
                  onPressed: () {
                    setState(() => _dataSelezionata = _dataSelezionata.add(const Duration(days: 1)));
                  },
                ),
              ],
            ),
          ),

          // 2. FILTRO OPERATORI (ORIZZONTALE)
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('barbers').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final barbieri = snapshot.data!.docs;

              return Container(
                height: 60,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: barbieri.length + 1,
                  itemBuilder: (context, index) {
                    final bool isTutti = index == 0;
                    final String label = isTutti ? "Tutti" : barbieri[index - 1]['name'];
                    final String? idFiltro = isTutti ? null : barbieri[index - 1].id;
                    final bool isSelected = _operatoreSelezionato == idFiltro;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        selectedColor: agOro,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        backgroundColor: agVerde,
                        onSelected: (selected) {
                          setState(() => _operatoreSelezionato = idFiltro);
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),

          const Divider(height: 1),

          // 3. LISTA DELLE PRENOTAZIONI IN TEMPO REALE
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _costruisciStreamPrenotazioni(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Nessuna prenotazione per questa giornata.',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                final prenotazioni = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: prenotazioni.length,
                  itemBuilder: (context, index) {
                    final data = prenotazioni[index].data() as Map<String, dynamic>;

                    // Estrazione dettagli sicura
                    final String ora = data['slot'] ?? '--:--';
                    final String clienteEmail = data['userEmail'] ?? 'Cliente';
                    final String operatoreNome = data['barberName'] ?? 'Qualsiasi';
                    final List servizi = data['services'] ?? [];
                    final int prezzoTotale = data['totalPrice'] ?? 0;

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            // Blocco Orario Evidenziato
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: agVerde,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                ora,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Dettagli appuntamento
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    clienteEmail,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Taglio con: $operatoreNome',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Servizi: ${servizi.join(", ")}',
                                    style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
                                  ),
                                ],
                              ),
                            ),
                            // Prezzo
                            Text(
                              '€$prezzoTotale',
                              style: TextStyle(
                                color: agVerde,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
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
        ],
      ),
    );
  }

  // Costruisce la query dinamicamente in base a data e filtri selezionati
  Stream<QuerySnapshot> _costruisciStreamPrenotazioni() {
    Query query = FirebaseFirestore.instance
        .collection('appointments')
        .where('date', isEqualTo: _dataString);

    if (_operatoreSelezionato != null) {
      query = query.where('barberId', isEqualTo: _operatoreSelezionato);
    }

    // Ordina i risultati cronologicamente per orario di slot
    return query.orderBy('slot').snapshots();
  }
}