import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'prenotazione_data_screen.dart';

class PrenotazioneServiziScreen extends StatefulWidget {
  const PrenotazioneServiziScreen({super.key});

  @override
  State<PrenotazioneServiziScreen> createState() => _PrenotazioneServiziScreenState();
}

class _GestioneServiziScreenState {}

class _PrenotazioneServiziScreenState extends State<PrenotazioneServiziScreen> {
  String? _servizioSelezionatoId;
  Map<String, dynamic>? _datiServizioSelezionato;
  String _nomeUtente = "Cliente";

  @override
  void initState() {
    super.initState();
    _recuperaNomeUtente();
    _richiediPermessiNotifiche();
  }

  Future<void> _richiediPermessiNotifiche() async {
    await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  Future<void> _recuperaNomeUtente() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists && userDoc.data() != null) {
          final data = userDoc.data() as Map<String, dynamic>;
          if (data.containsKey('name') && data['name']!.toString().trim().isNotEmpty) {
            setState(() {
              _nomeUtente = data['name'];
            });
            return;
          }
        }
      } catch (e) {
        debugPrint("Errore nel recupero del nome da Firestore: $e");
      }

      setState(() {
        _nomeUtente = user.displayName ?? user.email?.split('@')[0] ?? "Cliente";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. INTESTAZIONE (Header personalizzato del brand con Logo Ufficiale)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ciao, $_nomeUtente!',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // AGGIORNATO: Ora mostra l'asset reale 'A di barber.png' integrato nel cerchio con bordo oro
                      Container(
                        width: 60,
                        height: 60,
                        padding: const EdgeInsets.all(4.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFF164638),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFE2B13C), width: 2),
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/A di barber.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AG The gentleman\nBarber di Abate Gerardo',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, height: 1.2),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Via Sacco Giovanni, 18\nCapaccio Paestum',
                              style: TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 2. LISTA DEI SERVIZI
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('services').orderBy('createdAt', descending: false).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFFE2B13C)));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(child: Text('Nessun servizio disponibile al momento.', style: TextStyle(color: Colors.white)));
                  }

                  final servizi = snapshot.data!.docs;

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    itemCount: servizi.length,
                    itemBuilder: (context, index) {
                      final doc = servizi[index];
                      final dati = doc.data() as Map<String, dynamic>;

                      final String id = doc.id;
                      final String nome = dati['name'] ?? 'Servizio';
                      final double prezzo = (dati['price'] ?? 0.0).toDouble();
                      final int durata = dati['duration'] ?? 0;

                      final bool isSelezionato = _servizioSelezionatoId == id;

                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _servizioSelezionatoId = id;
                            _datiServizioSelezionato = dati;
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          decoration: BoxDecoration(
                            color: isSelezionato ? const Color(0xFFFFF6E0) : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isSelezionato ? const Color(0xFFE2B13C) : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                nome.toLowerCase().contains('barba') ? Icons.chair : Icons.content_cut,
                                color: const Color(0xFF164638),
                                size: 28,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nome,
                                      style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$durata min',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '${prezzo.toStringAsFixed(2).replaceAll('.', ',')} €',
                                style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),

            // 3. PULSANTE PROSEGUI
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE2B13C),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  elevation: 2,
                ),
                onPressed: _servizioSelezionatoId == null
                    ? null
                    : () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PrenotazioneDataScreen(
                        servizioId: _servizioSelezionatoId!,
                        servizioNome: _datiServizioSelezionato?['name'] ?? 'Servizio',
                        servizioDurata: _datiServizioSelezionato?['duration'] ?? 30,
                      ),
                    ),
                  );
                },
                child: const Text(
                  'Prosegui',
                  style: TextStyle(color: Color(0xFF121212), fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}