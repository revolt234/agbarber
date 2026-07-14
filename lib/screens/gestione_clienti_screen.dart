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

  void _mostraPannelloImpostazioniCliente({
    required String uid,
    required String nome,
    required String email,
    required int appuntamentiSaltati,
    required bool isBannato,
  }) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color agOro = const Color(0xFFE2B13C);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (bottomSheetContext) {
        final Color coloreTestoDettaglio = isDarkMode ? Colors.white : Colors.black87;

        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'OPZIONI GESTIONE UTENTE',
                        style: TextStyle(color: coloreTestoDettaglio, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5),
                      ),
                      Divider(color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300, height: 24),

                      Text('Cliente: ${nome.toUpperCase()}', style: TextStyle(color: coloreTestoDettaglio, fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text('Email: $email', style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black54, fontSize: 14)),

                      Divider(color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300, height: 24),

                      // INFORMAZIONE APPUNTAMENTI SALTATI
                      Row(
                        children: [
                          Icon(Icons.event_busy, color: appuntamentiSaltati > 0 ? Colors.red : agOro, size: 22),
                          const SizedBox(width: 10),
                          Text(
                            'Appuntamenti saltati: ',
                            style: TextStyle(color: coloreTestoDettaglio, fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '$appuntamentiSaltati',
                            style: TextStyle(
                              color: appuntamentiSaltati > 0 ? Colors.red : Colors.green,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      // PRIMO BOTTONE: DISABILITA / ABILITA UTENTE
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isBannato ? Colors.green : Colors.orange.shade900,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: Icon(isBannato ? Icons.lock_open : Icons.block, size: 20),
                          label: Text(
                            isBannato ? 'SBLOCCA ACCESSO EMAIL' : 'BLOCCA ACCESSO EMAIL',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          onPressed: () {
                            Navigator.pop(bottomSheetContext);
                            if (isBannato) {
                              _mostraConfermaSblocco(email, nome);
                            } else {
                              _mostraConfermaBlocco(email, nome);
                            }
                          },
                        ),
                      ),

                      const SizedBox(height: 12),

                      // SECONDO BOTTONE: RIMUOVI ACCOUNT
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.delete_forever, size: 20),
                          label: const Text(
                            'ELIMINA ACCOUNT DEFINITIVAMENTE',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          onPressed: () {
                            Navigator.pop(bottomSheetContext);
                            _mostraConfermaEliminazione(uid, nome);
                          },
                        ),
                      ),

                      const SizedBox(height: 20),
                      Divider(color: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade300, height: 1),
                      const SizedBox(height: 16),

                      // TERZO BOTTONE: CHIUDI PANNELLO
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade400, width: 1.5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            foregroundColor: isDarkMode ? Colors.white70 : Colors.black87,
                          ),
                          onPressed: () => Navigator.pop(bottomSheetContext),
                          child: const Text('CHIUDI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
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
      final FirebaseFunctions functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

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

                              // Escludi gli utenti che hanno ruolo "barbiere"
                              final String ruolo = (dati['role'] ?? '').toString();
                              if (ruolo == 'barbiere') {
                                return false;
                              }

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
                                        'Nessun cellulare';

                                // Lettura dinamica del contatore appuntamenti saltati
                                final int appuntamentiSaltati =
                                    dati['appuntamentisaltati'] ?? 0;

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
                                            'Cell: $telefono',
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
                                    // MODIFICATO: Sostituiti i vecchi bottoni con l'icona impostazioni singola
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.settings,
                                        color: Color(0xFFE2B13C),
                                      ),
                                      tooltip: 'Impostazioni cliente',
                                      onPressed: () => _mostraPannelloImpostazioniCliente(
                                        uid: uid,
                                        nome: nome,
                                        email: email,
                                        appuntamentiSaltati: appuntamentiSaltati,
                                        isBannato: isBannato,
                                      ),
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