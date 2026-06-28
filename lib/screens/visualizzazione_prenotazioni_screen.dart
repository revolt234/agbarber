import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class VisualizzazionePrenotazioniScreen extends StatefulWidget {
  const VisualizzazionePrenotazioniScreen({super.key});

  @override
  State<VisualizzazionePrenotazioniScreen> createState() => _VisualizzazionePrenotazioniScreenState();
}

class _VisualizzazionePrenotazioniScreenState extends State<VisualizzazionePrenotazioniScreen> {
  DateTime _dataSelezionata = DateTime.now();
  String? _operatoreSelezionato; // null significa "Tutti"

  // Configurazione Griglia Oraria (Modificabile in base ai tuoi orari di apertura)
  final int oraInizioGiornata = 8;  // 08:00
  final int oraFineGiornata = 20;   // 20:00
  final double altezzaPerMinuto = 1.6; // Incrementato leggermente per dare più spazio agli slot di 30 min
  final double larghezzaColonnaOra = 65.0;

  // Colori del brand AG Barber
  final Color agVerde = const Color(0xFF164638);
  final Color agOro = const Color(0xFFE2B13C);
  final Color agScuro = const Color(0xFF121212);

  String get _dataString => DateFormat('yyyy-MM-dd').format(_dataSelezionata);

  int _minutiDaStringa(String s) {
    final parti = s.split(':');
    return int.parse(parti[0]) * 60 + int.parse(parti[1]);
  }

  String _stringaDaMinuti(int m) {
    int ora = m ~/ 60;
    int min = m % 60;
    return "${ora.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}";
  }

  int _estraiDurata(Map<String, dynamic> data) {
    if (data.containsKey('duration')) return data['duration'];
    if (data.containsKey('totalDuration')) return data['totalDuration'];
    if (data.containsKey('services_duration')) return data['services_duration'];
    return 30; // default 30 min
  }

  Future<void> _selezionaData(BuildContext context) async {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dataSelezionata,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('it', 'IT'),
      builder: (context, child) {
        return Theme(
          data: isDarkMode
              ? ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: agOro,
              onPrimary: Colors.black,
              surface: const Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ), dialogTheme: DialogThemeData(backgroundColor: const Color(0xFF1E1E1E)),
          )
              : ThemeData.light().copyWith(
            colorScheme: ColorScheme.light(
              primary: agVerde,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ), dialogTheme: DialogThemeData(backgroundColor: Colors.white),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _dataSelezionata) {
      setState(() {
        _dataSelezionata = picked;
      });
    }
  }

  // Mostra il Popup dal basso con tutti i dettagli dell'appuntamento selezionato
  void _mostraDettagliAppuntamento(Map<String, dynamic> data, String oraInizioStr, String oraFineStr, int durata) {
    final String clienteNome = data['userName'] ?? data['displayName'] ?? 'Cliente';
    final String operatoreNome = data['barberName'] ?? 'Qualsiasi';
    final List servizi = data['services'] ?? [];
    final int prezzoTotale = data['totalPrice'] ?? 0;

    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final Color coloreTestoDettaglio = isDarkMode ? Colors.white : Colors.black87;
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      clienteNome.toUpperCase(),
                      style: TextStyle(color: coloreTestoDettaglio, fontWeight: FontWeight.bold, fontSize: 20),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: agVerde,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '€$prezzoTotale',
                      style: TextStyle(color: agOro, fontWeight: FontWeight.bold, fontSize: 18),
                    ),
                  ),
                ],
              ),
              Divider(color: isDarkMode ? Colors.grey : Colors.grey.shade300, height: 24),
              Row(
                children: [
                  Icon(Icons.access_time, color: agOro, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Orario: $oraInizioStr - $oraFineStr ($durata min)',
                    style: TextStyle(color: coloreTestoDettaglio, fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.person, color: agOro, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Operatore: $operatoreNome',
                    style: TextStyle(color: coloreTestoDettaglio, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.content_cut, color: agOro, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Servizio: ${servizi.join(", ")}',
                      style: TextStyle(color: isDarkMode ? Colors.white70 : Colors.black54, fontSize: 14, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: agVerde,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CHIUDI', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // MODIFICATO: Rilevazione dinamica del tema di sistema attivo sul telefono
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Configurazione dei colori dinamici
    final Color coloreSfondoSchermata = isDarkMode ? agScuro : const Color(0xFFF4F6F5);
    final Color coloreSfondoBarraData = isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.white;
    final Color coloreTestoSecondario = isDarkMode ? Colors.white70 : Colors.black54;
    final Color coloreLineeDivisione = isDarkMode ? Colors.grey.withValues(alpha: 0.25) : Colors.grey.shade300;
    final Color coloreLineeMezzora = isDarkMode ? Colors.grey.withValues(alpha: 0.12) : Colors.grey.shade200;

    final int inizioMinutiTotali = oraInizioGiornata * 60;
    final int fineMinutiTotali = oraFineGiornata * 60;
    final int minutiTotaliGiornata = fineMinutiTotali - inizioMinutiTotali;
    final double altezzaTotaleGriglia = minutiTotaliGiornata * altezzaPerMinuto;

    return Scaffold(
      backgroundColor: coloreSfondoSchermata,
      appBar: AppBar(
        title: const Text(
          'AGENDA CALENDARIO',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.1, color: Colors.white),
        ),
        backgroundColor: agVerde,
        iconTheme: const IconThemeData(color: Colors.white),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 1. SELETTORE DATA
          Container(
            color: coloreSfondoBarraData,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(Icons.chevron_left, color: isDarkMode ? Colors.white : agVerde, size: 28),
                  onPressed: () {
                    setState(() => _dataSelezionata = _dataSelezionata.subtract(const Duration(days: 1)));
                  },
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _selezionaData(context),
                    icon: Icon(Icons.calendar_today, color: agOro, size: 20),
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        DateFormat('E d MMM yyyy', 'it_IT').format(_dataSelezionata).toUpperCase(),
                        style: TextStyle(color: isDarkMode ? Colors.white : agVerde, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.chevron_right, color: isDarkMode ? Colors.white : agVerde, size: 28),
                  onPressed: () {
                    setState(() => _dataSelezionata = _dataSelezionata.add(const Duration(days: 1)));
                  },
                ),
              ],
            ),
          ),

          // 2. FILTRO OPERATORI
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('barbers').snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final barbieri = snapshot.data!.docs;

              return Container(
                height: 60,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: barbieri.length + 1,
                  itemBuilder: (context, index) {
                    final bool isTutti = index == 0;
                    final String label = isTutti ? "Tutti" : barbieri[index - 1]['name'];
                    final String? idFiltro = isTutti ? null : barbieri[index - 1].id;
                    final bool isSelected = _operatoreSelezionato == idFiltro;

                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: isSelected,
                        selectedColor: agOro,
                        labelStyle: TextStyle(
                          color: isSelected ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        backgroundColor: agVerde,
                        onSelected: (selected) {
                          setState(() => _operatoreSelezionato = idFiltro);
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),

          Divider(height: 1, color: isDarkMode ? Colors.grey : Colors.grey.shade400),

          // 3. CALENDARIO CON TIMELINE AD ALTA PRECISIONE (30 MIN)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _costruisciStreamPrenotazioni(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final prenotazioniDocs = snapshot.data?.docs ?? [];

                List<Map<String, dynamic>> elementiCalendario = [];
                for (var doc in prenotazioniDocs) {
                  final data = doc.data() as Map<String, dynamic>;
                  final String oraInizio = data['slot'] ?? '08:00';
                  final int inizioMinuti = _minutiDaStringa(oraInizio);
                  final int durata = _estraiDurata(data);
                  final int fineMinuti = inizioMinuti + durata;

                  int colonna = 0;
                  while (true) {
                    bool collisione = elementiCalendario.any((e) =>
                    e['colonna'] == colonna &&
                        ((inizioMinuti >= e['inizio'] && inizioMinuti < e['fine']) ||
                            (fineMinuti > e['inizio'] && fineMinuti <= e['fine']) ||
                            (inizioMinuti <= e['inizio'] && fineMinuti >= e['fine'])));
                    if (!collisione) break;
                    colonna++;
                  }

                  elementiCalendario.add({
                    'data': data,
                    'inizio': inizioMinuti,
                    'fine': fineMinuti,
                    'durata': durata,
                    'colonna': colonna,
                  });
                }

                return SingleChildScrollView(
                  child: SizedBox(
                    height: altezzaTotaleGriglia,
                    child: Stack(
                      children: [
                        // Righello Orario ad alta precisione: Include frazioni di mezz'ora (:00 e :30)
                        for (int i = oraInizioGiornata; i < oraFineGiornata; i++) ...[
                          // Linea dell'ora esatta (es. 09:00)
                          Positioned(
                            top: (i - oraInizioGiornata) * 60 * altezzaPerMinuto,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 30 * altezzaPerMinuto,
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: coloreLineeDivisione, width: 1.2),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: larghezzaColonnaOra,
                                    padding: const EdgeInsets.only(top: 4, left: 8),
                                    child: Text(
                                      "${i.toString().padLeft(2, '0')}:00",
                                      style: TextStyle(color: coloreTestoSecondario, fontSize: 12, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const Expanded(child: SizedBox.shrink()),
                                ],
                              ),
                            ),
                          ),
                          // Linea della mezz'ora (es. 09:30)
                          Positioned(
                            top: ((i - oraInizioGiornata) * 60 + 30) * altezzaPerMinuto,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 30 * altezzaPerMinuto,
                              decoration: BoxDecoration(
                                border: Border(
                                  top: BorderSide(color: coloreLineeMezzora, width: 1, style: BorderStyle.solid),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: larghezzaColonnaOra,
                                    padding: const EdgeInsets.only(top: 2, left: 8),
                                    child: Text(
                                      "${i.toString().padLeft(2, '0')}:30",
                                      style: TextStyle(color: isDarkMode ? Colors.grey : Colors.black38, fontSize: 11, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  const Expanded(child: SizedBox.shrink()),
                                ],
                              ),
                            ),
                          ),
                        ],
                        // Linea finale di chiusura (es. 20:00)
                        Positioned(
                          top: (oraFineGiornata - oraInizioGiornata) * 60 * altezzaPerMinuto,
                          left: 0,
                          right: 0,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(color: coloreLineeDivisione, width: 1.2),
                              ),
                            ),
                          ),
                        ),

                        // Generazione dinamica dei blocchi appuntamento proporzionali al tempo
                        for (var elem in elementiCalendario) ...[
                          (() {
                            final data = elem['data'];
                            final int inizioMinuti = elem['inizio'];
                            final int durata = elem['durata'];
                            final int colonna = elem['colonna'];

                            final double topPos = (inizioMinuti - inizioMinutiTotali) * altezzaPerMinuto;
                            final double altezzaBlocco = durata * altezzaPerMinuto;

                            final int maxCollisioniSuQuestoSlot = elementiCalendario
                                .where((e) => (inizioMinuti < e['fine'] && elem['fine'] > e['inizio']))
                                .map((e) => e['colonna'] as int)
                                .fold(0, (max, col) => col > max ? col : max) + 1;

                            final double larghezzaDisponibile = MediaQuery.of(context).size.width - larghezzaColonnaOra - 20;
                            final double larghezzaCard = larghezzaDisponibile / maxCollisioniSuQuestoSlot;
                            final double leftPos = larghezzaColonnaOra + (colonna * larghezzaCard) + 4;

                            final String clienteNome = data['userName'] ?? data['displayName'] ?? 'Cliente';
                            final int prezzoTotale = data['totalPrice'] ?? 0;
                            final String oraInizioStr = data['slot'] ?? '--:--';
                            final String oraFineStr = _stringaDaMinuti(inizioMinuti + durata);

                            return Positioned(
                              top: topPos + 2,
                              left: leftPos,
                              width: larghezzaCard - 4,
                              height: altezzaBlocco - 4,
                              child: GestureDetector(
                                onTap: () => _mostraDettagliAppuntamento(data, oraInizioStr, oraFineStr, durata),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: agVerde.withValues(alpha: 0.95),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: agOro, width: 1.2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: isDarkMode ? 0.4 : 0.15),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      )
                                    ],
                                  ),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              clienteNome,
                                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '€$prezzoTotale',
                                            style: TextStyle(color: agOro, fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }()),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Stream<QuerySnapshot> _costruisciStreamPrenotazioni() {
    Query query = FirebaseFirestore.instance
        .collection('appointments')
        .where('date', isEqualTo: _dataString);

    if (_operatoreSelezionato != null) {
      query = query.where('barberId', isEqualTo: _operatoreSelezionato);
    }

    return query.orderBy('slot').snapshots();
  }
}