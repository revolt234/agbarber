import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  // Apre il calendario per scegliere la data dell'eccezione
  Future<void> _selezionaDataEccezione() async {
    if (_barbiereSelezionatoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seleziona prima un operatore!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final DateTime? dataScelta = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (dataScelta != null) {
      final String dataFormattata =
          "${dataScelta.year}-${dataScelta.month.toString().padLeft(2, '0')}-${dataScelta.day.toString().padLeft(2, '0')}";
      _salvaEccezioneOperatore(dataFormattata);
    }
  }

  // Salva l'eccezione dell'operatore su Firestore
  Future<void> _salvaEccezioneOperatore(String dataFormattata) async {
    // Generiamo un ID univoco combinando Data e ID Barbiere
    final String docId = "${dataFormattata}_$_barbiereSelezionatoId";

    try {
      await FirebaseFirestore.instance
          .collection('barber_exceptions')
          .doc(docId)
          .set({
        'barberId': _barbiereSelezionatoId,
        'barberName': _barbiereSelezionatoNome,
        'date': dataFormattata,
        'type': _tipoEccezione,
        'fascia': _tipoEccezione == 'mezza_giornata' ? _fasciaOraria : null,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Turno operatore modificato!'),
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

  Future<void> _eliminaEccezione(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('barber_exceptions')
          .doc(docId)
          .delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante l\'eliminazione: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color coloreTesto = isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Turni Singolo Operatore',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF164638),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // 1. Menu a tendina per scegliere l'operatore (caricati dinamicamente da Firestore)
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: StreamBuilder<QuerySnapshot>(
              stream:
              FirebaseFirestore.instance.collection('barbers').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final barbieri = snapshot.data!.docs;

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
                  value: _barbiereSelezionatoId,
                  items: barbieri.map((doc) {
                    final dati = doc.data() as Map<String, dynamic>;
                    return DropdownMenuItem<String>(
                      value: doc.id,
                      child: Text(
                        dati['name'] ?? '',
                        style: TextStyle(color: coloreTesto),
                      ),
                    );
                  }).toList(),
                  onChanged: (idScelto) {
                    if (idScelto == null) return;
                    final docScelto =
                    barbieri.firstWhere((d) => d.id == idScelto);
                    setState(() {
                      _barbiereSelezionatoId = idScelto;
                      _barbiereSelezionatoNome = (docScelto.data()
                      as Map<String, dynamic>)['name'];
                    });
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
                      RadioListTile<String>(
                        title: const Text('Assente tutto il giorno'),
                        value: 'assente',
                        groupValue: _tipoEccezione,
                        onChanged: (val) => setState(() => _tipoEccezione = val!),
                      ),
                      RadioListTile<String>(
                        title: const Text('Lavora Mezza Giornata (Turno)'),
                        value: 'mezza_giornata',
                        groupValue: _tipoEccezione,
                        onChanged: (val) => setState(() => _tipoEccezione = val!),
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

          // 3. Elenco delle eccezioni degli operatori attive
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

                final eccezioni = snapshot.data!.docs;

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
                          onPressed: () => _eliminaEccezione(doc.id),
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