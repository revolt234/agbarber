import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart'; // Importato per cancellare la notifica abbinata

class StoricoPrenotazioniScreen extends StatelessWidget {
  const StoricoPrenotazioniScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    const Color agVerde = Color(0xFF164638);
    const Color agOro = Color(0xFFE2B13C);

    // Rilevazione dinamica del tema attivo sul dispositivo
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Tavolozza di colori dinamici e adattivi
    final Color coloreSfondoSchermata = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF4F6F5);
    final Color coloreTestoLogin = isDarkMode ? Colors.white : Colors.black87;
    final Color coloreSfondoCard = isDarkMode ? const Color(0xFF1C2824) : Colors.white;
    final Color coloreTestoPrimarioCard = isDarkMode ? Colors.white : Colors.black87;
    final Color coloreTestoSecondarioCard = isDarkMode ? Colors.grey : Colors.black54;

    if (user == null) {
      return Scaffold(
        backgroundColor: coloreSfondoSchermata,
        body: Center(
          child: Text(
            'Effettua il login per vedere le prenotazioni.',
            style: TextStyle(color: coloreTestoLogin),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: coloreSfondoSchermata,
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12.0),
          child: Image.asset(
            'assets/A di barber.png',
            fit: BoxFit.contain,
          ),
        ),
        title: const Text(
          'APPUNTAMENTI',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: 1.5,
          ),
        ),
        backgroundColor: agVerde,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('appointments')
            .where('userId', isEqualTo: user.uid)
            .orderBy('date', descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: agOro));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState(agOro, isDarkMode);
          }

          final adesso = DateTime.now();
          final prenotazioniValide = <DocumentSnapshot>[];

          for (var doc in snapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final String dateStr = data['date'] ?? '';
            final String slotStr = data['slot'] ?? '';

            try {
              final DateTime orarioAppuntamento = DateFormat("yyyy-MM-dd HH:mm").parse("$dateStr $slotStr");
              final DateTime limiteVisualizzazione = orarioAppuntamento.add(const Duration(hours: 1));

              if (adesso.isBefore(limiteVisualizzazione)) {
                prenotazioniValide.add(doc);
              } else {
                FirebaseFirestore.instance
                    .collection('appointments')
                    .doc(doc.id)
                    .delete()
                    .catchError((e) => debugPrint("Errore pulizia database: $e"));
              }
            } catch (e) {
              prenotazioniValide.add(doc);
            }
          }

          if (prenotazioniValide.isEmpty) {
            return _buildEmptyState(agOro, isDarkMode);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: prenotazioniValide.length,
            itemBuilder: (context, index) {
              final doc = prenotazioniValide[index];
              final data = doc.data() as Map<String, dynamic>;

              final String idDocumento = doc.id;
              final String dataApp = data['date'] ?? '----';
              final String ora = data['slot'] ?? '--:--';
              final String barber = data['barberName'] ?? 'Operatore';
              final List servizi = data['services'] ?? [];
              final int prezzo = data['totalPrice'] ?? 0;

              String dataFormattata = dataApp;
              try {
                final DateTime parsedDate = DateFormat("yyyy-MM-dd").parse(dataApp);
                dataFormattata = DateFormat("E d MMM", "it_IT").format(parsedDate).toUpperCase();
              } catch (_) {}

              return Card(
                color: coloreSfondoCard,
                margin: const EdgeInsets.only(bottom: 12),
                elevation: isDarkMode ? 0 : 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(
                    color: isDarkMode ? agVerde : Colors.grey.shade300,
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: agVerde,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.event, color: agOro, size: 28),
                    ),
                    title: Text(
                      '${servizi.join(", ")}',
                      style: TextStyle(
                        color: coloreTestoPrimarioCard,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$dataFormattata alle ore $ora',
                            style: TextStyle(color: coloreTestoSecondarioCard, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Specialista: $barber',
                            style: TextStyle(color: coloreTestoSecondarioCard),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '€$prezzo',
                            style: const TextStyle(
                              color: agOro,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 28),
                      tooltip: 'Annulla Appuntamento',
                      onPressed: () async {
                        final bool? conferma = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: isDarkMode ? const Color(0xFF1C2824) : Colors.white,
                            title: Text(
                                'Annulla Appuntamento',
                                style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)
                            ),
                            content: Text(
                                'Sei sicuro di voler cancellare questa prenotazione? L\'orario tornerà disponibile per gli altri clienti.',
                                style: TextStyle(color: isDarkMode ? Colors.grey : Colors.black54)
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('No, mantieni', style: TextStyle(color: agOro)),
                              ),
                              TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Sì, annulla', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );

                        if (conferma == true) {
                          try {
                            // 1. Elimina il documento da Firestore
                            await FirebaseFirestore.instance
                                .collection('appointments')
                                .doc(idDocumento)
                                .delete();

                            // 2. Disdice la sveglia locale dei 15 minuti prima
                            await NotificationService().cancellaNotifica(idDocumento.hashCode);

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Prenotazione annullata con successo.'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Errore durante la cancellazione: $e'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                          }
                        }
                      },
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(Color agOro, bool isDarkMode) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_month,
              size: 100,
              color: agOro.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 24),
            Text(
              'Nessun appuntamento attivo',
              style: TextStyle(
                fontSize: 18,
                color: isDarkMode ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'I tuoi prossimi appuntamenti compariranno qui.',
              style: TextStyle(color: isDarkMode ? Colors.grey : Colors.black54, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}