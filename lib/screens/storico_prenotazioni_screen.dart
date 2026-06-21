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

    if (user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF121212),
        body: Center(
          child: Text(
            'Effettua il login per vedere le prenotazioni.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
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
            return _buildEmptyState(agOro);
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
                // AGGIORNATO: Elimina fisicamente e definitivamente il documento da Firestore
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
            return _buildEmptyState(agOro);
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
                color: const Color(0xFF1C2824),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: agVerde, width: 1),
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
                      style: const TextStyle(
                        color: Colors.white,
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
                            style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Specialista: $barber',
                            style: const TextStyle(color: Colors.grey),
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
                    // INTEGRATO: Tasto di disdetta ed eliminazione dell'appuntamento attivo
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_forever, color: Colors.redAccent, size: 28),
                      tooltip: 'Annulla Appuntamento',
                      onPressed: () async {
                        final bool? conferma = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            backgroundColor: const Color(0xFF1C2824),
                            title: const Text(
                                'Annulla Appuntamento',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                            ),
                            content: const Text(
                                'Sei sicuro di voler cancellare questa prenotazione? L\'orario tornerà disponibile per gli altri clienti.',
                                style: TextStyle(color: Colors.grey)
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

  Widget _buildEmptyState(Color agOro) {
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
            const Text(
              'Nessun appuntamento attivo',
              style: TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'I tuoi prossimi appuntamenti compariranno qui.',
              style: TextStyle(color: Colors.grey, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}