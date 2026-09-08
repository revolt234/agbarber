import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart'; // AGGIUNTO
import 'package:flutter/foundation.dart' show kIsWeb;

class GestioneOperatoriScreen extends StatefulWidget {
  const GestioneOperatoriScreen({super.key});

  @override
  State<GestioneOperatoriScreen> createState() => _GestioneOperatoriScreenState();
}

class _GestioneOperatoriScreenState extends State<GestioneOperatoriScreen> {
  final _nomeController = TextEditingController();
  final _nomeFocusNode = FocusNode(); // AGGIUNTO

  @override
  void dispose() {
    _nomeController.dispose();
    _nomeFocusNode.dispose(); // AGGIUNTO
    super.dispose();
  }

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

  // Metodo helper per resettare la selezione del testo (come in GestionePeriodicoScreen)
  void _resettaSelezioneTesto(TextEditingController controller) {
    final text = controller.text;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  void _mostraDialogAggiungiOperatore() {
    _nomeController.clear();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Aggiungi Operatore'),
        content: TextField(
          controller: _nomeController,
          focusNode: _nomeFocusNode, // AGGIUNTO
          onTap: () => _resettaSelezioneTesto(_nomeController), // AGGIUNTO
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

  Future<void> _confermaEliminaOperatore(String docId, String nome) async {
    bool isEliminazioneInCorso = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: !isEliminazioneInCorso,
              child: AlertDialog(
                title: const Text('Conferma eliminazione'),
                content: Text('Sei sicuro di voler eliminare l\'operatore "$nome"?'),
                actions: [
                  TextButton(
                    onPressed: isEliminazioneInCorso ? null : () => Navigator.pop(dialogContext),
                    child: const Text('Annulla'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: isEliminazioneInCorso
                        ? null
                        : () async {
                      setDialogState(() {
                        isEliminazioneInCorso = true;
                      });

                      // Verifica connessione ad Internet reale
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
                        // Eliminazione bloccante che attende il completamento reale sul server
                        await FirebaseFirestore.instance
                            .collection('barbers')
                            .doc(docId)
                            .delete();

                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext);
                        }

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Operatore eliminato con successo.'),
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
                        : const Text('Elimina', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
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
                    onPressed: () => _confermaEliminaOperatore(operatoreDoc.id, nome),
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