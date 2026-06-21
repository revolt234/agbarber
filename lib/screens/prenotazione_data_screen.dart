import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PrenotazioneDataScreen extends StatefulWidget {
  final String servizioId;
  final String servizioNome;
  final int servizioDurata;

  const PrenotazioneDataScreen({
    super.key,
    required this.servizioId,
    required this.servizioNome,
    required this.servizioDurata,
  });

  @override
  State<PrenotazioneDataScreen> createState() => _PrenotazioneDataScreenState();
}

class _PrenotazioneDataScreenState extends State<PrenotazioneDataScreen> {
  DateTime _dataSelezionata = DateTime.now();
  String? _barbiereSelezionatoId;
  String? _barbiereSelezionatoNome;
  String? _orarioSelezionato;

  bool _isLoadingSlot = false;
  bool _isLoadingConfig = true;

  Map<String, dynamic> _orariNegozioBase = {};
  Map<String, dynamic> _eccezioniCalendario = {};
  List<String> _slotOrariCalcolati = [];

  final List<String> _giorniSettimana = [
    'domenica', 'lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato'
  ];

  @override
  void initState() {
    super.initState();
    _inizializzaDati();
  }

  Future<void> _inizializzaDati() async {
    try {
      final orariDoc = await FirebaseFirestore.instance.collection('settings').doc('orari_negozio').get();
      if (orariDoc.exists) _orariNegozioBase = orariDoc.data() ?? {};

      final eccezioniSnap = await FirebaseFirestore.instance.collection('calendar_exceptions').get();
      for (var doc in eccezioniSnap.docs) {
        _eccezioniCalendario[doc.id] = doc.data();
      }
      setState(() => _isLoadingConfig = false);
    } catch (e) {
      debugPrint("Errore inizializzazione: $e");
      setState(() => _isLoadingConfig = false);
    }
  }

  Future<void> _aggiornaSlotOrari() async {
    if (_barbiereSelezionatoId == null) return;
    setState(() => _isLoadingSlot = true);
    _slotOrariCalcolati.clear();

    try {
      final String dataStr = _formattaData(_dataSelezionata);
      final barberEx = await FirebaseFirestore.instance.collection('barber_exceptions').doc("${dataStr}_$_barbiereSelezionatoId").get();
      final dataEx = barberEx.exists ? barberEx.data() : null;

      if (dataEx != null && dataEx['type'] == 'assente') {
        setState(() => _isLoadingSlot = false);
        return;
      }

      String nomeGiorno = _giorniSettimana[_dataSelezionata.weekday % 7];
      var orariGiorno = _orariNegozioBase[nomeGiorno];

      if (orariGiorno != null && orariGiorno['isAperto'] == true) {
        // Genera slot separati per Mattina e Pomeriggio (Pausa pranzo esclusa automaticamente)
        if (orariGiorno.containsKey('mattina')) {
          _calcolaSlotPerFascia(orariGiorno['mattina'], dataEx);
        }
        if (orariGiorno.containsKey('pomeriggio')) {
          _calcolaSlotPerFascia(orariGiorno['pomeriggio'], dataEx);
        }
      }
    } catch (e) {
      debugPrint("Errore slot: $e");
    } finally { // <--- CORRETTO CON finally
      setState(() => _isLoadingSlot = false);
    }
  }

  void _calcolaSlotPerFascia(Map<String, dynamic> fasciaData, Map<String, dynamic>? dataEx) {
    int start = _minutiDaStringa(fasciaData['apertura'] ?? "09:00");
    int end = _minutiDaStringa(fasciaData['chiusura'] ?? "13:00");

    for (int m = start; m + widget.servizioDurata <= end; m += 30) {
      int ora = m ~/ 60;
      int min = m % 60;

      // Applica eventuali turnazioni speciali o mezze giornate del singolo operatore
      if (dataEx != null && dataEx['type'] == 'mezza_giornata') {
        if (dataEx['fascia'] == 'mattina' && ora >= 13) continue;
        if (dataEx['fascia'] == 'pomeriggio' && ora < 13) continue;
      }

      _slotOrariCalcolati.add("${ora.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}");
    }
  }

  int _minutiDaStringa(String s) => int.parse(s.split(':')[0]) * 60 + int.parse(s.split(':')[1]);
  String _formattaData(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  bool _isChiuso(DateTime d) {
    if (_eccezioniCalendario[_formattaData(d)]?['status'] == 'chiuso') return true;
    return _orariNegozioBase[_giorniSettimana[d.weekday % 7]]?['isAperto'] == false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingConfig) return const Scaffold(backgroundColor: Color(0xFF121212), body: Center(child: CircularProgressIndicator(color: Color(0xFFE2B13C))));

    final String dataStr = _formattaData(_dataSelezionata);
    final bool giornoCorrenteChiuso = _isChiuso(_dataSelezionata);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Scegli Data e Barber', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF164638),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. SELEZIONE GIORNO Orizzontale (14 giorni)
          const Padding(
            padding: EdgeInsets.only(left: 20.0, top: 16, bottom: 8),
            child: Text('Seleziona il giorno:', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: 14,
              itemBuilder: (ctx, i) {
                DateTime d = DateTime.now().add(Duration(days: i));
                bool isChiusoGiorno = _isChiuso(d);
                bool sel = _formattaData(d) == dataStr;

                final List<String> settimanaAbbr = ['Dom', 'Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab'];
                String nomeGiorno = settimanaAbbr[d.weekday % 7];

                return GestureDetector(
                  onTap: isChiusoGiorno
                      ? null
                      : () {
                    setState(() {
                      _dataSelezionata = d;
                      _orarioSelezionato = null;
                    });
                    _aggiornaSlotOrari();
                  },
                  child: Container(
                    width: 65,
                    margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: sel
                          ? const Color(0xFFE2B13C)
                          : (isChiusoGiorno ? Colors.red.withValues(alpha: 0.2) : const Color(0xFF1C2824)),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isChiusoGiorno ? Colors.red.shade800 : Colors.transparent,
                        width: isChiusoGiorno ? 1.5 : 0,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(nomeGiorno, style: TextStyle(color: isChiusoGiorno ? Colors.red.shade300 : (sel ? Colors.black : Colors.grey), fontSize: 13)),
                        const SizedBox(height: 4),
                        Text('${d.day}', style: TextStyle(color: isChiusoGiorno ? Colors.red.shade300 : (sel ? Colors.black : Colors.white), fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // 2. SELEZIONE OPERATORE
          const Padding(
            padding: EdgeInsets.only(left: 20.0, top: 16, bottom: 8),
            child: Text('Scegli chi ti guiderà:', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            height: 110,
            child: giornoCorrenteChiuso
                ? const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20.0),
                child: Text(
                  'Il salone è chiuso in questa data. Scegli un giorno attivo sopra.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 15),
                  textAlign: TextAlign.center,
                ),
              ),
            )
                : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('barbers').snapshots(),
              builder: (ctx, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFE2B13C)));
                final barbieri = snap.data!.docs;

                return ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: barbieri.length,
                  itemBuilder: (context, index) {
                    var doc = barbieri[index];
                    var data = doc.data() as Map<String, dynamic>;
                    final id = doc.id;
                    final nome = data['name'] ?? 'Staff';
                    bool sel = _barbiereSelezionatoId == id;

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _barbiereSelezionatoId = id;
                          _barbiereSelezionatoNome = nome;
                          _orarioSelezionato = null;
                        });
                        _aggiornaSlotOrari();
                      },
                      child: Container(
                        width: 100,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C2824),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: sel ? const Color(0xFFE2B13C) : Colors.transparent, width: 2),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircleAvatar(
                              backgroundColor: sel ? const Color(0xFFE2B13C) : const Color(0xFF164638),
                              child: Icon(Icons.person, color: sel ? Colors.black : Colors.white),
                            ),
                            const SizedBox(height: 8),
                            Text(nome, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // 3. GRIGLIA ORARI DINAMICI
          const Padding(
            padding: EdgeInsets.only(left: 20.0, top: 20, bottom: 8),
            child: Text('Orari disponibili:', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: giornoCorrenteChiuso
                ? const SizedBox.shrink()
                : (_barbiereSelezionatoId == null
                ? const Center(child: Text('Seleziona un operatore per vedere gli orari.', style: TextStyle(color: Colors.grey)))
                : (_isLoadingSlot
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFE2B13C)))
                : (_slotOrariCalcolati.isEmpty
                ? const Center(child: Text('Nessun orario disponibile o operatore fuori turno.', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)))
                : GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.2,
              ),
              itemCount: _slotOrariCalcolati.length,
              itemBuilder: (context, index) {
                final ora = _slotOrariCalcolati[index];
                bool sel = _orarioSelezionato == ora;

                return GestureDetector(
                  onTap: () => setState(() => _orarioSelezionato = ora),
                  child: Container(
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFFE2B13C) : const Color(0xFF1C2824),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        ora,
                        style: TextStyle(color: sel ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                );
              },
            )))),
          ),

          // 4. BOTTONE CONFERMA PRENOTAZIONE
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE2B13C),
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: (_barbiereSelezionatoId == null || _orarioSelezionato == null || giornoCorrenteChiuso)
                  ? null
                  : () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Conferma Prenotazione'),
                    content: Text('Servizio: ${widget.servizioNome}\nData: $dataStr\nOra: $_orarioSelezionato\nCon: $_barbiereSelezionatoNome'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Modifica')),
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Conferma')),
                    ],
                  ),
                );
              },
              child: const Text('Conferma Prenotazione', style: TextStyle(color: Color(0xFF121212), fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}