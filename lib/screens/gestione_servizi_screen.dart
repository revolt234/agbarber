import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GestioneServiziScreen extends StatefulWidget {
  const GestioneServiziScreen({super.key});

  @override
  State<GestioneServiziScreen> createState() => _GestioneServiziScreenState();
}

class _GestioneServiziScreenState extends State<GestioneServiziScreen> {
  final _nomeController = TextEditingController();
  final _prezzoController = TextEditingController();
  final _durataController = TextEditingController();

  @override
  void dispose() {
    _nomeController.dispose();
    _prezzoController.dispose();
    _durataController.dispose();
    super.dispose();
  }

  // Mostra il pop-up (funziona sia per NUOVI servizi sia per MODIFICARE quelli esistenti)
  void _mostraDialogServizio({String? docId, String? nomeIniziale, double? prezzoIniziale, int? durataIniziale}) {
    if (docId != null) {
      // Se passiamo un docId, siamo in modalità MODIFICA: precompiliamo i campi
      _nomeController.text = nomeIniziale ?? '';
      _prezzoController.text = prezzoIniziale?.toString() ?? '';
      _durataController.text = durataIniziale?.toString() ?? '';
    } else {
      // Altrimenti siamo in modalità INSERIMENTO: svuotiamo i campi
      _nomeController.clear();
      _prezzoController.clear();
      _durataController.clear();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(docId == null ? 'Aggiungi Nuovo Servizio' : 'Modifica Servizio'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nomeController,
                decoration: const InputDecoration(
                  labelText: 'Nome Servizio',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _prezzoController,
                decoration: const InputDecoration(
                  labelText: 'Prezzo (€)',
                  border: OutlineInputBorder(),
                  prefixText: '€ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _durataController,
                decoration: const InputDecoration(
                  labelText: 'Durata stimata (in minuti)',
                  border: OutlineInputBorder(),
                  suffixText: ' min',
                ),
                keyboardType: TextInputType.number,
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
      ),
    );
  }

  // Gestisce sia il salvataggio del nuovo servizio che l'aggiornamento
  Future<void> _salvaServizioFirebase(String? docId) async {
    final nome = _nomeController.text.trim();
    final prezzoSetted = double.tryParse(_prezzoController.text.trim());
    final durataSetted = int.tryParse(_durataController.text.trim());

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
      };

      if (docId == null) {
        // CREAZIONE di un nuovo documento
        datiServizio['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('services').add(datiServizio);
      } else {
        // AGGIORNAMENTO di un documento esistente
        await FirebaseFirestore.instance.collection('services').doc(docId).update(datiServizio);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore durante il salvataggio: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _eliminaServizio(String docId) async {
    await FirebaseFirestore.instance.collection('services').doc(docId).delete();
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

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: servizi.length,
            itemBuilder: (context, index) {
              final servizioDoc = servizi[index];
              final dati = servizioDoc.data() as Map<String, dynamic>;

              final String nome = dati['name'] ?? 'Senza nome';
              final double prezzo = (dati['price'] ?? 0.0).toDouble();
              final int durata = dati['duration'] ?? 0;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.content_cut, color: Color(0xFFE2B13C)),
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
                      // NUOVO: Pulsante Modifica (Matita)
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _mostraDialogServizio(
                          docId: servizioDoc.id,
                          nomeIniziale: nome,
                          prezzoIniziale: prezzo,
                          durataIniziale: durata,
                        ),
                      ),
                      // Pulsante Elimina (Cestino)
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _eliminaServizio(servizioDoc.id),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF164638),
        onPressed: () => _mostraDialogServizio(), // Apre vuoto per inserimento
        child: const Icon(Icons.add, color: Colors.white, size: 30),
      ),
    );
  }
}