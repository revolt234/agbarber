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

  // Struttura oraria predefinita per le aperture straordinarie
  Map<String, dynamic> _orariStraordinari = {
    'mattina': {'apertura': '09:00', 'chiusura': '13:00'},
    'pomeriggio': {'apertura': '14:30', 'chiusura': '19:30'},
  };

  @override
  void dispose() {
    _notaController.dispose();
    super.dispose();
  }

  Future<void> _selezionaGiornoEccezione() async {
    final DateTime? dataScelta = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (dataScelta != null) {
      final String dataFormattata = "${dataScelta.year}-${dataScelta.month.toString().padLeft(2, '0')}-${dataScelta.day.toString().padLeft(2, '0')}";
      _mostraDialogConfiguraGiorno(dataFormattata);
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
      final stringaOra = '${tempoScelto.hour.toString().padLeft(2, '0')}:${tempoScelto.minute.toString().padLeft(2, '0')}';
      setDialogState(() {
        _orariStraordinari[fascia][tipo] = stringaOra;
      });
    }
  }

  void _mostraDialogConfiguraGiorno(String dataFormattata) {
    _notaController.clear();
    _statusScelto = 'chiuso';
    // Reset orari predefiniti ad ogni apertura dialogo
    _orariStraordinari = {
      'mattina': {'apertura': '09:00', 'chiusura': '13:00'},
      'pomeriggio': {'apertura': '14:30', 'chiusura': '19:30'},
    };

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Configura Giorno ($dataFormattata)'),
          content: SingleChildScrollView(
            child: Column(
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
                if (_statusScelto == 'aperto') ...[
                  const SizedBox(height: 16),
                  const Text("Orari Apertura Straordinaria", style: TextStyle(fontWeight: FontWeight.bold)),
                  const Divider(),
                  // Mattina
                  const Text("Turno Mattina", style: TextStyle(fontSize: 12, color: Colors.grey)),
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
                  // Pomeriggio
                  const Text("Turno Pomeriggio", style: TextStyle(fontSize: 12, color: Colors.grey)),
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
      final Map<String, dynamic> mappaSalvataggio = {
        'date': dataFormattata,
        'status': _statusScelto,
        'nota': _notaController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Se è aperto, includiamo gli orari inseriti nel pop-up dentro il documento
      if (_statusScelto == 'aperto') {
        mappaSalvataggio['mattina'] = _orariStraordinari['mattina'];
        mappaSalvataggio['pomeriggio'] = _orariStraordinari['pomeriggio'];
      }

      await FirebaseFirestore.instance
          .collection('calendar_exceptions')
          .doc(dataFormattata)
          .set(mappaSalvataggio);

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