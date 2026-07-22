import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prenotazionibarbiere/screens/prenotazione_calendario_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class PrenotazioneServiziBarbiereScreen extends StatefulWidget {
  final String clienteId;
  final String clienteNome;

  const PrenotazioneServiziBarbiereScreen({
    super.key,
    required this.clienteId,
    required this.clienteNome,
  });

  @override
  State<PrenotazioneServiziBarbiereScreen> createState() => _PrenotazioneServiziBarbiereScreenState();
}

class _PrenotazioneServiziBarbiereScreenState extends State<PrenotazioneServiziBarbiereScreen> {
  String? _servizioSelezionatoId;
  Map<String, dynamic>? _datiServizioSelezionato;
  late Stream<QuerySnapshot> _servicesStream;

  // Colori del brand AG Barber
  final Color constColorVerde = const Color(0xFF164638);
  final Color constColorOro = const Color(0xFFE2B13C);

  @override
  void initState() {
    super.initState();
    _inizializzaStream();
  }

  void _inizializzaStream() {
    _servicesStream = FirebaseFirestore.instance
        .collection('services')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  Future<bool> _controllaConnessioneReale() async {
    if (kIsWeb) return true;
    try {
      final risultato = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      return risultato.isNotEmpty && risultato[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final Color coloreSfondoSchermata = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF4F6F5);
    final Color coloreTestoTitoli = isDarkMode ? Colors.white : Colors.black87;
    final Color coloreSfondoCardSpenta = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final Color coloreTestoCardSpenta = isDarkMode ? Colors.white : Colors.black87;
    final Color coloreIconaCardSpenta = isDarkMode ? constColorOro : constColorVerde;

    return Scaffold(
      backgroundColor: coloreSfondoSchermata,
      appBar: AppBar(
        title: const Text(
          'SELEZIONA SERVIZIO',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.0, color: Colors.white, fontSize: 18),
        ),
        backgroundColor: constColorVerde,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: StreamBuilder<QuerySnapshot>(
          stream: _servicesStream,
          builder: (context, snapshot) {
            final bool haErroreConnessione = snapshot.hasError;
            final bool haDatiValidi = snapshot.hasData && snapshot.data!.docs.isNotEmpty;
            final bool puoProseguire = !haErroreConnessione && haDatiValidi && _servizioSelezionatoId != null;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Banner Intestazione del Cliente Selezionato
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 14.0),
                  color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.white,
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: constColorVerde,
                        child: Text(
                          widget.clienteNome.isNotEmpty ? widget.clienteNome[0].toUpperCase() : 'C',
                          style: TextStyle(color: constColorOro, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Prenotazione per:',
                              style: TextStyle(color: isDarkMode ? Colors.white60 : Colors.black54, fontSize: 12),
                            ),
                            Text(
                              widget.clienteNome,
                              style: TextStyle(color: coloreTestoTitoli, fontSize: 17, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Lista dei servizi da Firestore
                Expanded(
                  child: Builder(
                    builder: (context) {
                      if (haErroreConnessione) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.wifi_off, color: constColorOro, size: 48),
                                const SizedBox(height: 16),
                                Text(
                                  'Connessione internet assente\no instabile.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: coloreTestoTitoli, fontSize: 16),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: constColorVerde,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _inizializzaStream();
                                    });
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Riprova'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Center(child: CircularProgressIndicator(color: constColorOro));
                      }

                      if (!haDatiValidi) {
                        return Center(
                          child: Text('Nessun servizio disponibile al momento.', style: TextStyle(color: coloreTestoTitoli)),
                        );
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
                                color: isSelezionato
                                    ? (isDarkMode ? const Color(0xFFFFF1CC) : const Color(0xFFFFF6E0))
                                    : coloreSfondoCardSpenta,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: isSelezionato ? constColorOro : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    nome.toLowerCase().contains('barba') ? Icons.chair : Icons.content_cut,
                                    color: isSelezionato ? constColorVerde : coloreIconaCardSpenta,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          nome,
                                          style: TextStyle(
                                            color: isSelezionato ? Colors.black : coloreTestoCardSpenta,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$durata min',
                                          style: TextStyle(color: isSelezionato ? Colors.grey.shade700 : Colors.grey.shade500, fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    '${prezzo.toStringAsFixed(2).replaceAll('.', ',')} €',
                                    style: TextStyle(
                                      color: isSelezionato ? Colors.black : coloreTestoCardSpenta,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
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

                // Tasto Prosegui
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: constColorOro,
                      foregroundColor: const Color(0xFF121212),
                      disabledBackgroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
                      disabledForegroundColor: isDarkMode ? Colors.white.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.25),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 2,
                    ),
                    onPressed: puoProseguire
                        ? () async {
                      bool online = await _controllaConnessioneReale();

                      if (!context.mounted) return;

                      if (online) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PrenotazioneCalendarioScreen(
                              servizioId: _servizioSelezionatoId!,
                              servizioNome: _datiServizioSelezionato?['name'] ?? 'Servizio',
                              servizioDurata: _datiServizioSelezionato?['duration'] ?? 30,
                              servizioPrezzo: (_datiServizioSelezionato?['price'] ?? 0.0).toDouble(),
                              clienteId: widget.clienteId,     // PASSATO IL CLIENTE
                              clienteNome: widget.clienteNome, // PASSATO IL CLIENTE
                            ),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Impossibile proseguire: connessione internet assente o instabile.'),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                        : null,
                    child: const Text(
                      'Prosegui',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}