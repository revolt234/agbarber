import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GestioneCalendarioScreen extends StatefulWidget {
  const GestioneCalendarioScreen({super.key});

  @override
  State<GestioneCalendarioScreen> createState() => _GestioneCalendarioScreenState();
}

class _GestioneCalendarioScreenState extends State<GestioneCalendarioScreen> {
  final _notaController = TextEditingController();
  String _statusScelto = 'chiuso';

  @override
  void dispose() {
    _notaController.dispose();
    super.dispose();
  }

  // Mostra il DatePicker nativo per scegliere il giorno esatto sul calendario
  Future<void> _selezionaGiornoEccezione() async {
    final DateTime? dataScelta = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(), // Non ha senso bloccare giorni passati
      lastDate: DateTime.now().add(const Duration(days: 365)), // Fino a un anno avanti
    );

    if (dataScelta != null) {
      // Formattiamo la data come stringa YYYY-MM-DD per usarla come ID del documento
      final String dataFormattata = "${dataScelta.year}-${dataScelta.month.toString().padLeft(2, '0')}-${dataScelta.day.toString().padLeft(2, '0')}";
      _mostraDialogConfiguraGiorno(dataFormattata);
    }
  }

  // Pop-up per decidere se il giorno scelto è Chiuso o Aperto con una nota
  void _mostraDialogConfiguraGiorno(String dataFormattata) {
    _notaController.clear();
    _statusScelto = 'chiuso';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Configura Giorno ($dataFormattata)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _statusScelto,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'chiuso', child: Text('Chiuso tutto il giorno')),
                  DropdownMenuItem(value: 'aperto', child: Text('Apertura Straordinaria')),
                ],
                onChanged: (valore) {
                  if (valore != null) {
                    setDialogState(() => _statusScelto = valore);
                  }
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _notaController,
                decoration: const InputDecoration(
                  labelText: 'Motivazione (es. Ferie, Santo Patrono)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF164638)),
              onPressed: () => _salvaEccezioneFirebase(dataFormattata),
              child: const Text('Salva', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _salvaEccezioneFirebase(String dataFormattata) async {
    try {
      await FirebaseFirestore.instance
          .collection('calendar_exceptions')
          .doc(dataFormattata)
          .set({
        'date': dataFormattata,
        'status': _statusScelto,
        'nota': _notaController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _rimuoviEccezione(String docId) async {
    await FirebaseFirestore.instance.collection('calendar_exceptions').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color coloreTesto = isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Eccezioni Calendario', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF164638),
        iconTheme: const IconThemeData(color: Colors.white),
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
                  'Nessuna eccezione impostata.\nUsa il pulsante in basso per bloccare giorni specifici sul calendario.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final eccezioni = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: eccezioni.length,
            itemBuilder: (context, index) {
              final doc = eccezioni[index];
              final dati = doc.data() as Map<String, dynamic>;

              final String data = dati['date'] ?? '';
              final String status = dati['status'] ?? 'chiuso';
              final String nota = dati['nota'] ?? '';
              final bool isChiuso = status == 'chiuso';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isChiuso ? Colors.red.shade100 : Colors.green.shade100,
                    child: Icon(
                      isChiuso ? Icons.block : Icons.event_available,
                      color: isChiuso ? Colors.red : Colors.green,
                    ),
                  ),
                  title: Text(
                      data,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: coloreTesto)
                  ),
                  subtitle: Text(
                    '${isChiuso ? "CHIUSO" : "APERTURA STRAORDINARIA"} ${nota.isNotEmpty ? "- $nota" : ""}',
                    style: TextStyle(color: isChiuso ? Colors.red : Colors.green, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.grey),
                    onPressed: () => _rimuoviEccezione(doc.id),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF164638),
        onPressed: _selezionaGiornoEccezione,
        icon: const Icon(Icons.calendar_today, color: Colors.white),
        label: const Text('Gestisci Singolo Giorno', style: TextStyle(color: Colors.white)),
      ),
    );
  }
}