import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart'; // AGGIUNTO: Necessario per avviare il dialer telefonico nativo

class GestioneClientiScreen extends StatefulWidget {
  const GestioneClientiScreen({super.key});

  @override
  State<GestioneClientiScreen> createState() => _GestioneClientiScreenState();
}

enum FiltroOrdinamento { nome, appuntamentiSaltati, debito }

class _GestioneClientiScreenState extends State<GestioneClientiScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = "";
  bool _isProcessingAction = false;
  FiltroOrdinamento _filtroAttivo = FiltroOrdinamento.nome;

  // AGGIUNTO: Variabili persistenti per memorizzare gli Stream in modo che non si ricreino ad ogni setState
  late Stream<QuerySnapshot> _bannedEmailsStream;
  late Stream<QuerySnapshot> _usersStream;

  @override
  void initState() {
    super.initState();
    // Inizializziamo gli stream una volta sola all'avvio del widget
    _bannedEmailsStream = FirebaseFirestore.instance.collection('banned_emails').snapshots();
    _usersStream = FirebaseFirestore.instance.collection('users').snapshots();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  // Metodo di supporto per mostrare il dialogo di modifica del debito
  void _mostraDialogModificaDebito(String uid, double debitoAttuale) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final TextEditingController debitoController = TextEditingController(
      text: debitoAttuale.toStringAsFixed(2).replaceAll('.', ','),
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text(
            'Modifica Debito Cliente',
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Inserisci il nuovo importo del debito:',
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: debitoController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  prefixText: '€ ',
                  prefixStyle: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold),
                  filled: true,
                  fillColor: isDarkMode ? const Color(0xFF2C2C2E) : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
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
                backgroundColor: const Color(0xFF164638),
              ),
              onPressed: () async {
                final String input = debitoController.text.trim().replaceAll(',', '.');
                final double? nuovoDebito = double.tryParse(input);

                if (nuovoDebito == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Inserisci un valore numerico valido.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (nuovoDebito < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Il debito non può essere un valore negativo.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                Navigator.pop(context);

                try {
                  await FirebaseFirestore.instance.collection('users').doc(uid).update({
                    'debito': nuovoDebito,
                  });

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Debito aggiornato a € ${nuovoDebito.toStringAsFixed(2).replaceAll('.', ',')}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Errore durante il salvataggio: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              child: const Text(
                'Salva',
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

                      // CELLULARE SOTTO L'EMAIL (ESTRATTO IN TEMPO REALE)
                      StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
                          builder: (context, userSnap) {
                            String? telefonoValido;
                            if (userSnap.hasData && userSnap.data!.exists && userSnap.data!.data() != null) {
                              final userData = userSnap.data!.data() as Map<String, dynamic>;
                              final String rawPhone = userData['phone'] ?? userData['phoneNumber'] ?? '';
                              if (rawPhone.trim().isNotEmpty && rawPhone.trim() != 'Nessun cellulare') {
                                telefonoValido = rawPhone.trim();
                              }
                            }

                            if (telefonoValido == null) return const SizedBox.shrink();

                            return Padding(
                              padding: const EdgeInsets.only(top: 6.0),
                              child: GestureDetector(
                                onTap: () async {
                                  final String numeroPulito = telefonoValido!.replaceAll(RegExp(r'[^\d+]'), '');
                                  final Uri telUri = Uri(scheme: 'tel', path: numeroPulito);
                                  try {
                                    await launchUrl(telUri, mode: LaunchMode.externalApplication);
                                  } catch (e) {
                                    debugPrint("Errore durante l'apertura del dialer nativo: $e");
                                  }
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Cell: ',
                                      style: TextStyle(
                                        color: isDarkMode ? Colors.white70 : Colors.black54,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Flexible(
                                      child: Text(
                                        telefonoValido,
                                        style: const TextStyle(
                                          color: Colors.blue,
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.open_in_new, color: Colors.blue, size: 14),
                                  ],
                                ),
                              ),
                            );
                          }
                      ),

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

                      const SizedBox(height: 12),

                      // INFORMAZIONE DEBITO TOTALE CON GESTIONE CLICK E MODIFICA DINAMICA
                      StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
                          builder: (context, userSnap) {
                            double debito = 0.0;
                            if (userSnap.hasData && userSnap.data!.exists && userSnap.data!.data() != null) {
                              final userData = userSnap.data!.data() as Map<String, dynamic>;
                              debito = (userData['debito'] ?? 0.0).toDouble();
                            }

                            return InkWell(
                              onTap: () => _mostraDialogModificaDebito(uid, debito),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                child: Row(
                                  children: [
                                    Icon(Icons.monetization_on, color: debito > 0 ? Colors.red : Colors.green, size: 22),
                                    const SizedBox(width: 10),
                                    Text(
                                      'Debito Totale: ',
                                      style: TextStyle(color: coloreTestoDettaglio, fontSize: 15, fontWeight: FontWeight.w500),
                                    ),
                                    Text(
                                      '€ ${debito.toStringAsFixed(2).replaceAll('.', ',')}',
                                      style: TextStyle(
                                        color: debito > 0 ? Colors.red : Colors.green,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(Icons.edit, color: isDarkMode ? Colors.white54 : Colors.black45, size: 16),
                                  ],
                                ),
                              ),
                            );
                          }
                      ),

                      const SizedBox(height: 28),
                      // NUOVO BOTTONE: INVIA NOTIFICA PERSONALIZZATA
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade900,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          icon: const Icon(Icons.send_rounded, size: 20),
                          label: const Text(
                            'INVIA NOTIFICA',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          onPressed: () {
                            Navigator.pop(bottomSheetContext);
                            _mostraDialogInviaNotificaPersonalizzata(uid, nome);
                          },
                        ),
                      ),

                      const SizedBox(height: 12),
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
                            'ELIMINA CLIENTE',
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

  // Metodo di supporto per mostrare il dialogo di inserimento del messaggio e invocazione della Cloud Function
  void _mostraDialogInviaNotificaPersonalizzata(String uid, String nomeCliente) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final TextEditingController messaggioController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          title: Text(
            'Notifica a $nomeCliente',
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Scrivi il testo del messaggio da inviare:',
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black87,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messaggioController,
                maxLength: 150,
                maxLines: 3,
                style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Scrivi qui...',
                  hintStyle: TextStyle(color: isDarkMode ? Colors.white54 : Colors.black45),
                  filled: true,
                  fillColor: isDarkMode ? const Color(0xFF2C2C2E) : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
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
                backgroundColor: const Color(0xFF164638),
              ),
              onPressed: () async {
                final String testo = messaggioController.text.trim();

                if (testo.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Inserisci un messaggio prima di inviare.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                Navigator.pop(context);

                // Richiamo alla funzione ottimizzata senza causare il glitch grafico di ricostruzione degli Stream
                await _inviaNotificaPersonalizzataTramiteCloudFunction(uid, nomeCliente, testo);
              },
              child: const Text(
                'Invia',
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

  Future<void> _inviaNotificaPersonalizzataTramiteCloudFunction(String uid, String nomeCliente, String messaggio) async {
    setState(() => _isProcessingAction = true);
    try {
      final FirebaseFunctions functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

      final HttpsCallable callable = functions.httpsCallable(
        'inviaNotificaPersonalizzataCliente',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );

      await callable.call(<String, dynamic>{
        'userIdCliente': uid,
        'messaggio': messaggio,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notifica inviata con successo a $nomeCliente!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String erroreDettaglio = e is FirebaseFunctionsException
            ? e.message ?? e.toString()
            : e.toString();

        if (erroreDettaglio.contains('failed-precondition')) {
          erroreDettaglio = 'Il cliente non ha abilitato le notifiche push sul telefono.';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore: $erroreDettaglio'),
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
                    child: Row(
                      children: [
                        Expanded(
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
                                color: isDarkMode ? Colors.white70 : Colors.grey.shade600,
                              ),
                              filled: true,
                              fillColor: coloreInputSfondo,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: BorderSide(
                                  color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
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
                        const SizedBox(width: 10),
                        // Pulsante di ordinamento e filtro affianco alla ricerca
                        Container(
                          decoration: BoxDecoration(
                            color: coloreInputSfondo,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isDarkMode ? Colors.white12 : Colors.grey.shade300,
                            ),
                          ),
                          child: PopupMenuButton<FiltroOrdinamento>(
                            icon: const Icon(
                              Icons.filter_list,
                              color: Color(0xFFE2B13C),
                              size: 26,
                            ),
                            tooltip: 'Ordina clienti',
                            onSelected: (FiltroOrdinamento filtroSelected) {
                              setState(() {
                                _filtroAttivo = filtroSelected;
                              });
                            },
                            itemBuilder: (BuildContext context) => <PopupMenuEntry<FiltroOrdinamento>>[
                              PopupMenuItem<FiltroOrdinamento>(
                                value: FiltroOrdinamento.nome,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.sort_by_alpha,
                                      color: _filtroAttivo == FiltroOrdinamento.nome ? const Color(0xFFE2B13C) : Colors.grey,
                                    ),
                                    const SizedBox(width: 10),
                                    const Text('Ordina per Nome'),
                                  ],
                                ),
                              ),
                              PopupMenuItem<FiltroOrdinamento>(
                                value: FiltroOrdinamento.appuntamentiSaltati,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.event_busy,
                                      color: _filtroAttivo == FiltroOrdinamento.appuntamentiSaltati ? const Color(0xFFE2B13C) : Colors.grey,
                                    ),
                                    const SizedBox(width: 10),
                                    const Text('Per Appuntamenti Saltati'),
                                  ],
                                ),
                              ),
                              PopupMenuItem<FiltroOrdinamento>(
                                value: FiltroOrdinamento.debito,
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.monetization_on,
                                      color: _filtroAttivo == FiltroOrdinamento.debito ? const Color(0xFFE2B13C) : Colors.grey,
                                    ),
                                    const SizedBox(width: 10),
                                    const Text('Per Debito'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: StreamBuilder<QuerySnapshot>(
                      // MODIFICATO: Collegato alla variabile dello stream persistente inizializzata in initState
                      stream: _bannedEmailsStream,
                      builder: (context, bannedSnapshot) {
                        final Set<String> emailBannate = {};
                        if (bannedSnapshot.hasData) {
                          for (var doc in bannedSnapshot.data!.docs) {
                            emailBannate.add(doc.id.toLowerCase());
                          }
                        }

                        return StreamBuilder<QuerySnapshot>(
                          // MODIFICATO: Collegato alla variabile dello stream persistente inizializzata in initState
                          stream: _usersStream,
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

                            // Filtro locale per ruolo e query di ricerca
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

                            // Ordinamento locale dinamico con gestione priorità e fallback alfabetico secondario
                            docsFiltrati.sort((a, b) {
                              final datiA = a.data() as Map<String, dynamic>;
                              final datiB = b.data() as Map<String, dynamic>;

                              final String nomeA = (datiA['name'] ?? '').toString().toLowerCase();
                              final String nomeB = (datiB['name'] ?? '').toString().toLowerCase();

                              if (_filtroAttivo == FiltroOrdinamento.appuntamentiSaltati) {
                                final int saltatiA = datiA['appuntamentisaltati'] ?? 0;
                                final int saltatiB = datiB['appuntamentisaltati'] ?? 0;
                                if (saltatiA != saltatiB) {
                                  return saltatiB.compareTo(saltatiA); // Discendente
                                }
                                return nomeA.compareTo(nomeB); // Fallback alfabetico ascendente
                              } else if (_filtroAttivo == FiltroOrdinamento.debito) {
                                final double debitoA = (datiA['debito'] ?? 0.0).toDouble();
                                final double debitoB = (datiB['debito'] ?? 0.0).toDouble();
                                if (debitoA != debitoB) {
                                  return debitoB.compareTo(debitoA); // Discendente
                                }
                                return nomeA.compareTo(nomeB); // Fallback alfabetico ascendente
                              } else {
                                return nomeA.compareTo(nomeB); // Ascendente alfabetico
                              }
                            });

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
                                final String telefonoRaw =
                                    dati['phone'] ??
                                        '';

                                final String? telefonoValido = (telefonoRaw.trim().isNotEmpty &&
                                    telefonoRaw.trim() != 'Nessun cellulare')
                                    ? telefonoRaw.trim()
                                    : null;

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
                                          if (telefonoValido != null) ...[
                                            const SizedBox(height: 2),
                                            GestureDetector(
                                              onTap: () async {
                                                final String numeroPulito = telefonoValido.replaceAll(RegExp(r'[^\d+]'), '');
                                                final Uri telUri = Uri(scheme: 'tel', path: numeroPulito);
                                                try {
                                                  await launchUrl(telUri, mode: LaunchMode.externalApplication);
                                                } catch (e) {
                                                  debugPrint("Errore durante l'apertura del dialer nativo: $e");
                                                }
                                              },
                                              behavior: HitTestBehavior.opaque,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'Cell: ',
                                                    style: TextStyle(
                                                      color: isDarkMode ? Colors.white54 : Colors.black54,
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  Flexible(
                                                    child: Text(
                                                      telefonoValido,
                                                      style: const TextStyle(
                                                        color: Colors.blue,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                        decoration: TextDecoration.underline,
                                                      ),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Icon(Icons.open_in_new, color: Colors.blue, size: 12),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
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