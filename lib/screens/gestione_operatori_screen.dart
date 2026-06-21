import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class GestioneOperatoriScreen extends StatefulWidget {
  const GestioneOperatoriScreen({super.key});

  @override
  State<GestioneOperatoriScreen> createState() => _GestioneOperatoriScreenState();
}

class _GestioneOperatoriScreenState extends State<GestioneOperatoriScreen> {
  final _nomeController = TextEditingController();

  @override
  void dispose() {
    _nomeController.dispose();
    super.dispose();
  }

  void _mostraDialogAggiungiOperatore() {
    _nomeController.clear();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aggiungi Operatore'),
        content: TextField(
          controller: _nomeController,
          decoration: const InputDecoration(
            labelText: 'Nome dell\'operatore (es. Gerardo)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF164638)),
            onPressed: _aggiungiOperatoreFirebase,
            child: const Text('Salva', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _aggiungiOperatoreFirebase() async {
    final nome = _nomeController.text.trim();

    if (nome.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Inserisci un nome valido!'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('barbers').add({
        'name': nome,
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _eliminaOperatore(String docId) async {
    await FirebaseFirestore.instance.collection('barbers').doc(docId).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestisci Operatori', style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF164638),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('barbers').orderBy('createdAt', descending: false).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Nessun operatore inserito. Clicca sul + in basso!'));
          }

          final operatori = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(16.0),
            itemCount: operatori.length,
            itemBuilder: (context, index) {
              final operatoreDoc = operatori[index];
              final dati = operatoreDoc.data() as Map<String, dynamic>;
              final String nome = dati['name'] ?? 'Senza nome';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFF164638),
                    child: Icon(Icons.person, color: Color(0xFFE2B13C)),
                  ),
                  title: Text(nome, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _eliminaOperatore(operatoreDoc.id),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF164638),
        onPressed: _mostraDialogAggiungiOperatore,
        child: const Icon(Icons.add, color: Colors.white, size: 30),
      ),
    );
  }
}