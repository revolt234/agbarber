import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class GestioneClientiScreen extends StatefulWidget {
  const GestioneClientiScreen({super.key});

  @override
  State<GestioneClientiScreen> createState() => _GestioneClientiScreenState();
}

class _GestioneClientiScreenState extends State<GestioneClientiScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = "";
  bool _isProcessingAction = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _mostraConfermaEliminazione(String uid, String nomeCliente) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text(
            'Elimina Cliente Definitivamente',
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Sei sicuro di voler eliminare l\'account di "$nomeCliente"? Questa azione rimuoverà l\'utente e tutte le sue eventuali prenotazioni.',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Annulla',
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(context);
                await _eliminaClienteTramiteCloudFunction(uid);
              },
              child: const Text(
                'Elimina',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _mostraConfermaBlocco(String email, String nomeCliente) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text(
            'Blocca Accesso',
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Vuoi vietare l\'accesso all\'app per l\'indirizzo email "$email"? Il cliente non potrà più connettersi.',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Annulla',
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade900,
              ),
              onPressed: () async {
                Navigator.pop(context);
                await _bloccaEmail(email);
              },
              child: const Text(
                'Blocca Email',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _mostraConfermaSblocco(String email, String nomeCliente) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text(
            'Sblocca Accesso',
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            'Vuoi consentire nuovamente l\'accesso all\'app per l\'indirizzo email "$email"?',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black87,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Annulla',
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                Navigator.pop(context);
                await _sbloccaEmail(email);
              },
              child: const Text(
                'Sblocca Email',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _eliminaClienteTramiteCloudFunction(String uid) async {
    setState(() => _isProcessingAction = true);
    try {
      final FirebaseFunctions functions = FirebaseFunctions.instanceFor(region: 'us-central1');

      final HttpsCallable callable = functions.httpsCallable(
        'eliminaUtenteCompleto',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      await callable.call(<String, dynamic>{
        'uid': uid,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account rimosso definitivamente dal database',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore Cloud Function: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingAction = false);
    }
  }

  Future<void> _bloccaEmail(String email) async {
    if (email.trim().isEmpty) return;
    try {
      String docId = email.trim().toLowerCase();
      await FirebaseFirestore.instance
          .collection('banned_emails')
          .doc(docId)
          .set({
        'email': docId,
        'bannedAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Email $email inserita nella lista nera.'),
            backgroundColor: Colors.orange.shade900,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante il blocco: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _sbloccaEmail(String email) async {
    if (email.trim().isEmpty) return;
    try {
      String docId = email.trim().toLowerCase();
      await FirebaseFirestore.instance
          .collection('banned_emails')
          .doc(docId)
          .delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Email $email sbloccata con successo.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore durante lo sblocco: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final Color coloreSfondoSchermata =
    isDarkMode ? const Color(0xFF121212) : const Color(0xFFF4F6F5);
    final Color coloreTestoTitoli = isDarkMode ? Colors.white : Colors.black87;
    final Color coloreSfondoCard =
    isDarkMode ? const Color(0xFF1C2824) : Colors.white;
    final Color coloreInputSfondo =
    isDarkMode ? const Color(0xFF1C1C1E) : Colors.white;

    return GestureDetector(
      onTap: () => _searchFocusNode.unfocus(),
      child: Scaffold(
        backgroundColor: coloreSfondoSchermata,
        appBar: AppBar(
          title: const Text(
            'Gestione Clienti',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: const Color(0xFF164638),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      maxLength: 45,
                      style: TextStyle(color: coloreTestoTitoli),
                      decoration: InputDecoration(
                        hintText: 'Cerca cliente per nome...',
                        counterText: "",
                        hintStyle: TextStyle(
                          color: isDarkMode ? Colors.white54 : Colors.black45,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color:
                          isDarkMode
                              ? Colors.white70
                              : Colors.grey.shade600,
                        ),
                        filled: true,
                        fillColor: coloreInputSfondo,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color:
                            isDarkMode
                                ? Colors.white12
                                : Colors.grey.shade300,
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value.trim().toLowerCase();
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      stream:
                      FirebaseFirestore.instance
                          .collection('banned_emails')
                          .snapshots(),
                      builder: (context, bannedSnapshot) {
                        final Set<String> emailBannate = {};
                        if (bannedSnapshot.hasData) {
                          for (var doc in bannedSnapshot.data!.docs) {
                            emailBannate.add(doc.id.toLowerCase());
                          }
                        }

                        return StreamBuilder<QuerySnapshot>(
                          stream:
                          FirebaseFirestore.instance
                              .collection('users')
                              .orderBy('name', descending: false)
                              .snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFFE2B13C),
                                ),
                              );
                            }
                            if (!snapshot.hasData ||
                                snapshot.data!.docs.isEmpty) {
                              return Center(
                                child: Text(
                                  'Nessun cliente registrato nel database.',
                                  style: TextStyle(
                                    color:
                                    isDarkMode
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              );
                            }

                            final tuttiIDocs = snapshot.data!.docs;
                            final docsFiltrati =
                            tuttiIDocs.where((doc) {
                              final dati =
                              doc.data() as Map<String, dynamic>;
                              final String nomeCompleto =
                              (dati['name'] ?? '').toString()
                                  .toLowerCase();
                              return nomeCompleto.contains(_searchQuery);
                            }).toList();

                            if (docsFiltrati.isEmpty) {
                              return Center(
                                child: Text(
                                  'Nessun risultato corrispondente alla ricerca.',
                                  style: TextStyle(
                                    color:
                                    isDarkMode
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              );
                            }

                            return ListView.builder(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 4.0,
                              ),
                              itemCount: docsFiltrati.length,
                              itemBuilder: (context, index) {
                                final userDoc = docsFiltrati[index];
                                final dati =
                                userDoc.data() as Map<String, dynamic>;

                                final String uid = userDoc.id;
                                final String nome =
                                    dati['name'] ?? 'Cliente Anonimo';
                                final String email =
                                    dati['email'] ?? 'Nessuna Email';
                                final String telefono =
                                    dati['phone'] ??
                                        dati['phoneNumber'] ??
                                        'Nessun telefono';

                                final bool isBannato = emailBannate.contains(
                                  email.trim().toLowerCase(),
                                );

                                return Card(
                                  color: coloreSfondoCard,
                                  elevation: isDarkMode ? 0 : 2,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    leading: CircleAvatar(
                                      backgroundColor: const Color(0xFF164638),
                                      child: Text(
                                        nome.isNotEmpty
                                            ? nome
                                            .substring(0, 1)
                                            .toUpperCase()
                                            : 'C',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      nome,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                        color: coloreTestoTitoli,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Column(
                                        crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Email: $email',
                                            style: TextStyle(
                                              color:
                                              isDarkMode
                                                  ? Colors.white70
                                                  : Colors.black87,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Tel: $telefono',
                                            style: TextStyle(
                                              color:
                                              isDarkMode
                                                  ? Colors.white54
                                                  : Colors.black54,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        isBannato
                                            ? IconButton(
                                          icon: const Icon(
                                            Icons.lock_open,
                                            color: Colors.green,
                                          ),
                                          tooltip: 'Sblocca email',
                                          onPressed:
                                              () => _mostraConfermaSblocco(
                                            email,
                                            nome,
                                          ),
                                        )
                                            : IconButton(
                                          icon: const Icon(
                                            Icons.block,
                                            color: Colors.orange,
                                          ),
                                          tooltip: 'Blocca email',
                                          onPressed:
                                              () => _mostraConfermaBlocco(
                                            email,
                                            nome,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete_forever,
                                            color: Colors.red,
                                          ),
                                          tooltip: 'Elimina account',
                                          onPressed:
                                              () => _mostraConfermaEliminazione(
                                            uid,
                                            nome,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              if (_isProcessingAction)
                Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: const Center(
                    child: CircularProgressIndicator(color: Color(0xFFE2B13C)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}