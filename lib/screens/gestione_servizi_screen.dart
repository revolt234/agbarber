import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; // AGGIUNTO

class GestioneServiziScreen extends StatefulWidget {
  const GestioneServiziScreen({super.key});

  @override
  State<GestioneServiziScreen> createState() => _GestioneServiziScreenState();
}

class _GestioneServiziScreenState extends State<GestioneServiziScreen> {
  final _nomeController = TextEditingController();
  final _prezzoController = TextEditingController();

  // NUOVI FocusNode per i campi di testo
  final _nomeFocusNode = FocusNode();
  final _prezzoFocusNode = FocusNode();

  int? _durataSelezionata;
  String _coloreSelezionatoHex = '164638'; // Colore default (Verde AG)

  // Palette di 15 colori ben distinti per i differenti servizi
  final List<String> _paletteColoriHex = const [
    '164638', // Verde AG Barber
    '1E88E5', // Blu Brillante
    'D81B60', // Rosa Ciclame
    '8E24AA', // Viola Chiaro
    'F57C00', // Arancione
    '004D40', // Verde Smeraldo
    '00ACC1', // Turchese
    '3949AB', // Indaco
    'C0392B', // Rosso Scuro
    '2E7D32', // Verde Bosco
    '6D4C41', // Marrone
    '00838F', // Otterraneo
    'AD1457', // Magenta
    '283593', // Blu Notte
    '558B2F', // Verde Oliva
  ];

  final List<int> _opzioniDurata = List<int>.generate(
    ((120 - 30) ~/ 10) + 1,
        (index) => 30 + (index * 10),
  );

  @override
  void dispose() {
    _nomeController.dispose();
    _prezzoController.dispose();
    _nomeFocusNode.dispose();   // AGGIUNTO
    _prezzoFocusNode.dispose(); // AGGIUNTO
    super.dispose();
  }

  // Metodo helper per resettare la selezione del testo (come in GestionePeriodicoScreen)
  void _resettaSelezioneTesto(TextEditingController controller) {
    final text = controller.text;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  void _mostraDialogServizio({String? docId, String? nomeIniziale, double? prezzoIniziale, int? durataIniziale, String? coloreInizialeHex}) {
    if (docId != null) {
      _nomeController.text = nomeIniziale ?? '';
      _prezzoController.text = prezzoIniziale?.toStringAsFixed(2) ?? '';
      _durataSelezionata = _opzioniDurata.contains(durataIniziale) ? durataIniziale : 30;
      _coloreSelezionatoHex = (coloreInizialeHex != null && coloreInizialeHex.isNotEmpty)
          ? coloreInizialeHex
          : _paletteColoriHex.first;
    } else {
      _nomeController.clear();
      _prezzoController.clear();
      _durataSelezionata = 30;
      _coloreSelezionatoHex = _paletteColoriHex.first;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(docId == null ? 'Aggiungi Nuovo Servizio' : 'Modifica Servizio'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _nomeController,
                      focusNode: _nomeFocusNode,           // AGGIUNTO
                      onTap: () => _resettaSelezioneTesto(_nomeController), // AGGIUNTO
                      decoration: const InputDecoration(
                        labelText: 'Nome Servizio',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _prezzoController,
                      focusNode: _prezzoFocusNode,         // AGGIUNTO
                      onTap: () => _resettaSelezioneTesto(_prezzoController), // AGGIUNTO
                      decoration: const InputDecoration(
                        labelText: 'Prezzo (€)',
                        border: OutlineInputBorder(),
                        prefixText: '€ ',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                    const SizedBox(height: 12),

                    DropdownButtonFormField<int>(
                      initialValue: _durataSelezionata,
                      decoration: const InputDecoration(
                        labelText: 'Durata stimata',
                        border: OutlineInputBorder(),
                      ),
                      items: _opzioniDurata.map((int minuti) {
                        return DropdownMenuItem<int>(
                          value: minuti,
                          child: Text('$minuti min'),
                        );
                      }).toList(),
                      onChanged: (int? nuovoValore) {
                        setDialogState(() {
                          _durataSelezionata = nuovoValore;
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // SELEZIONE COLORE ASSOCIATO AL SERVIZIO
                    const Text(
                      'Colore Badge Servizio:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _paletteColoriHex.map((hexColor) {
                        final color = Color(int.parse('FF$hexColor', radix: 16));
                        final bool isSelected = _coloreSelezionatoHex == hexColor;

                        return GestureDetector(
                          onTap: () {
                            setDialogState(() {
                              _coloreSelezionatoHex = hexColor;
                            });
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected ? Colors.black : Colors.transparent,
                                width: isSelected ? 3 : 1,
                              ),
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, size: 18, color: Colors.white)
                                : null,
                          ),
                        );
                      }).toList(),
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
                  onPressed: () => _salvaServizioFirebase(docId),
                  child: const Text('Salva', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          }
      ),
    );
  }

  Future<void> _salvaServizioFirebase(String? docId) async {
    final nome = _nomeController.text.trim();
    final prezzoSetted = double.tryParse(_prezzoController.text.trim());
    final durataSetted = _durataSelezionata;

    if (nome.isEmpty || prezzoSetted == null || durataSetted == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compila tutti i campi con valori validi!'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      final datiServizio = {
        'name': nome,
        'price': prezzoSetted,
        'duration': durataSetted,
        'colorHex': _coloreSelezionatoHex, // SALVATAGGIO COLORE SU FIRESTORE
      };

      if (docId == null) {
        datiServizio['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('services').add(datiServizio);
      } else {
        await FirebaseFirestore.instance.collection('services').doc(docId).update(datiServizio);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore durante il salvataggio: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _mostraConfermaEliminazione(String docId, String nomeServizio) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Conferma Eliminazione'),
          content: Text('Sei sicuro di voler eliminare il servizio "$nomeServizio"? L\'azione non può essere annullata.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annulla'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(context);
                await _eliminaServizio(docId);
              },
              child: const Text('Elimina', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _eliminaServizio(String docId) async {
    try {
      await FirebaseFirestore.instance.collection('services').doc(docId).delete();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante l\'eliminazione: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestisci Servizi', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF164638),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('services').orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nessun servizio inserito. Clicca sul + in basso!'));
          }

          final servizi = snapshot.data!.docs;

          return SafeArea(
            child: ListView.builder(
              padding: const EdgeInsets.only(left: 16.0, top: 16.0, right: 16.0, bottom: 80.0),
              itemCount: servizi.length,
              itemBuilder: (context, index) {
                final servizioDoc = servizi[index];
                final dati = servizioDoc.data() as Map<String, dynamic>;

                final String nome = dati['name'] ?? 'Senza nome';
                final double prezzo = (dati['price'] ?? 0.0).toDouble();
                final int durata = dati['duration'] ?? 0;
                final String colorHex = dati['colorHex'] ?? '164638';
                final Color coloreBadge = Color(int.parse('FF$colorHex', radix: 16));

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 2,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: coloreBadge,
                      radius: 18,
                      child: const Icon(Icons.content_cut, color: Colors.white, size: 20),
                    ),
                    title: Text(nome, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text(
                      'Durata: $durata min',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${prezzo.toStringAsFixed(2)} €', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _mostraDialogServizio(
                            docId: servizioDoc.id,
                            nomeIniziale: nome,
                            prezzoIniziale: prezzo,
                            durataIniziale: durata,
                            coloreInizialeHex: colorHex,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _mostraConfermaEliminazione(servizioDoc.id, nome),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF164638),
        onPressed: () => _mostraDialogServizio(),
        child: const Icon(Icons.add, color: Colors.white, size: 30),
      ),
    );
  }
}