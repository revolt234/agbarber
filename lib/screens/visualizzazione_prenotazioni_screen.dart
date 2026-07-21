import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart'; // AGGIUNTO: Necessario per il recupero forzato del token utente corretto

class VisualizzazionePrenotazioniScreen extends StatefulWidget {
  const VisualizzazionePrenotazioniScreen({super.key});

  @override
  State<VisualizzazionePrenotazioniScreen> createState() => _VisualizzazionePrenotazioniScreenState();
}

class _VisualizzazionePrenotazioniScreenState extends State<VisualizzazionePrenotazioniScreen> {
  DateTime _dataSelezionata = DateTime.now();
  String? _operatoreSelezionato; // null significa "Tutti"

  // Configurazione Griglia Oraria Dinamica
  int oraInizioGiornata = 8;
  int oraFineGiornata = 20;
  final double altezzaPerMinuto = 1.6;
  final double larghezzaColonnaOra = 65.0;

  // Colori del brand AG Barber
  final Color agVerde = const Color(0xFF164638);
  final Color agOro = const Color(0xFFE2B13C);
  final Color agScuro = const Color(0xFF121212);

  String get _dataString => DateFormat('yyyy-MM-dd').format(_dataSelezionata);

  final List<String> _giorniSettimanaDb = [
    'domenica', 'lunedì', 'martedì', 'mercoledì', 'giovedì', 'venerdì', 'sabato'
  ];

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
    return 30;
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

  void _mostraDettagliAppuntamento(Map<String, dynamic> data, String oraInizioStr, String oraFineStr, int durata, String appointmentId) async {
    final String clienteNome = data['userName'] ?? data['displayName'] ?? 'Cliente';
    final String operatoreNome = data['barberName'] ?? 'Qualsiasi';
    final List servizi = data['services'] ?? [];
    final double prezzoTotale = (data['totalPrice'] ?? 0.0).toDouble();
    final String? clienteId = data['userId'];
    final String dataApp = data['date'] ?? '';

    bool mostraSelettorePresenza = false;
    try {
      final DateTime orarioInizioApp = DateFormat("yyyy-MM-dd HH:mm").parse("$dataApp $oraInizioStr");
      final DateTime limiteSoglia = orarioInizioApp.add(const Duration(hours: 1));
      if (DateTime.now().isAfter(limiteSoglia)) {
        mostraSelettorePresenza = true;
      }
    } catch (e) {
      debugPrint("Errore parsing data appuntamento: $e");
    }

    String? telefonoGreggio = data['phone'] ?? data['phoneNumber'];

    if ((telefonoGreggio == null || telefonoGreggio.trim().isEmpty || telefonoGreggio.trim() == 'Nessun cellulare') && clienteId != null) {
      try {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(clienteId).get();
        if (userDoc.exists && userDoc.data() != null) {
          final userData = userDoc.data() as Map<String, dynamic>;
          telefonoGreggio = userData['phone'] ?? userData['phoneNumber'];
        }
      } catch (e) {
        debugPrint("Errore nel recupero del cellulare dal profilo utente: $e");
      }
    }

    final String? telefonoValido = (telefonoGreggio != null &&
        telefonoGreggio.trim().isNotEmpty &&
        telefonoGreggio.trim() != 'Nessun cellulare')
        ? telefonoGreggio.trim()
        : null;

    if (!mounted) return;
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    bool isInvioInCorso = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) {
        final Color coloreTestoDettaglio = isDarkMode ? Colors.white : Colors.black87;

        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setModalState) {
              // Verifica se l'appuntamento ha un flag 'pagato' impostato a false
              final bool isContrassegnatoNonPagato = data['pagato'] == false;

              return Container(
                padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                decoration: BoxDecoration(
                  color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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
                                '€ ${prezzoTotale.toStringAsFixed(2).replaceAll('.', ',')}',
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
                            Icon(Icons.phone, color: agOro, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Cellulare: ',
                              style: TextStyle(color: coloreTestoDettaglio, fontSize: 15),
                            ),
                            if (telefonoValido != null)
                              Flexible(
                                child: GestureDetector(
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
                                      Flexible(
                                        child: Text(
                                          telefonoValido,
                                          style: const TextStyle(
                                            color: Colors.blue,
                                            fontSize: 15,
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
                              )
                            else
                              Text(
                                "Non disponibile",
                                style: TextStyle(color: coloreTestoDettaglio, fontSize: 15),
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

                        if (mostraSelettorePresenza) ...[
                          Divider(color: isDarkMode ? Colors.grey : Colors.grey.shade300, height: 24),
                          Text(
                            'IL CLIENTE SI È PRESENTATO?',
                            style: TextStyle(color: coloreTestoDettaglio, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ChoiceChip(
                                label: const Text('SI'),
                                selected: data['presentato'] == 'si',
                                selectedColor: Colors.green,
                                labelStyle: TextStyle(
                                  color: data['presentato'] == 'si' ? Colors.white : (isDarkMode ? Colors.white : Colors.black),
                                  fontWeight: FontWeight.bold,
                                ),
                                onSelected: (bool selected) async {
                                  if (selected && clienteId != null && data['presentato'] != 'si') {
                                    if (data['presentato'] == 'no') {
                                      await FirebaseFirestore.instance.collection('users').doc(clienteId).update({
                                        'appuntamentisaltati': FieldValue.increment(-1)
                                      });
                                    }
                                    await FirebaseFirestore.instance.collection('appointments').doc(appointmentId).update({
                                      'presentato': 'si'
                                    });
                                    setModalState(() {
                                      data['presentato'] = 'si';
                                    });
                                  }
                                },
                              ),
                              const SizedBox(width: 12),
                              ChoiceChip(
                                label: const Text('NO'),
                                selected: data['presentato'] == 'no',
                                selectedColor: Colors.red.shade900,
                                labelStyle: TextStyle(
                                  color: data['presentato'] == 'no' ? Colors.white : (isDarkMode ? Colors.white : Colors.black),
                                  fontWeight: FontWeight.bold,
                                ),
                                onSelected: (bool selected) async {
                                  if (selected && clienteId != null && data['presentato'] != 'no') {
                                    await FirebaseFirestore.instance.collection('users').doc(clienteId).update({
                                      'appuntamentisaltati': FieldValue.increment(1)
                                    });
                                    await FirebaseFirestore.instance.collection('appointments').doc(appointmentId).update({
                                      'presentato': 'no'
                                    });
                                    setModalState(() {
                                      data['presentato'] = 'no';
                                    });
                                  }
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // SEZIONE GESTIONE DEBITO / MANCATO PAGAMENTO
                          Text(
                            'STATO PAGAMENTO',
                            style: TextStyle(color: coloreTestoDettaglio, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 8),
                          FilterChip(
                            label: const Text('IL CLIENTE NON HA PAGATO'),
                            selected: isContrassegnatoNonPagato,
                            selectedColor: Colors.red.shade900,
                            checkmarkColor: Colors.white,
                            labelStyle: TextStyle(
                              color: isContrassegnatoNonPagato ? Colors.white : (isDarkMode ? Colors.white : Colors.black87),
                              fontWeight: FontWeight.bold,
                            ),
                            onSelected: (bool selected) async {
                              if (clienteId == null) return;

                              final DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(clienteId);
                              final DocumentReference appRef = FirebaseFirestore.instance.collection('appointments').doc(appointmentId);

                              try {
                                if (selected) {
                                  // Esegue una transazione atomica per incrementare in modo sicuro il debito dell'utente
                                  await FirebaseFirestore.instance.runTransaction((transaction) async {
                                    final userSnapshot = await transaction.get(userRef);
                                    double debitoAttuale = 0.0;
                                    if (userSnapshot.exists && userSnapshot.data() != null) {
                                      final userData = userSnapshot.data() as Map<String, dynamic>;
                                      debitoAttuale = (userData['debito'] ?? 0.0).toDouble();
                                    }
                                    transaction.update(userRef, {'debito': debitoAttuale + prezzoTotale});
                                    transaction.update(appRef, {'pagato': false});
                                  });

                                  setModalState(() {
                                    data['pagato'] = false;
                                  });
                                } else {
                                  // Esegue una transazione atomica per stornare/rimborsare il debito se deselezionato
                                  await FirebaseFirestore.instance.runTransaction((transaction) async {
                                    final userSnapshot = await transaction.get(userRef);
                                    double debitoAttuale = 0.0;
                                    if (userSnapshot.exists && userSnapshot.data() != null) {
                                      final userData = userSnapshot.data() as Map<String, dynamic>;
                                      debitoAttuale = (userData['debito'] ?? 0.0).toDouble();
                                    }
                                    double nuovoDebito = debitoAttuale - prezzoTotale;
                                    if (nuovoDebito < 0) nuovoDebito = 0.0;

                                    transaction.update(userRef, {'debito': nuovoDebito});
                                    transaction.update(appRef, {'pagato': true});
                                  });

                                  setModalState(() {
                                    data['pagato'] = true;
                                  });
                                }
                              } catch (e) {
                                debugPrint("Errore aggiornamento debito/pagamento: $e");
                              }
                            },
                          ),
                        ],

                        const SizedBox(height: 24),

                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: agOro, width: 1.5),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              foregroundColor: agOro,
                            ),
                            icon: isInvioInCorso
                                ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: agOro,
                                strokeWidth: 2,
                              ),
                            )
                                : const Icon(Icons.notification_important, size: 20),
                            label: Text(
                              isInvioInCorso ? 'INVIO IN CORSO...' : 'SOLLECITA CLIENTE',
                              style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                            ),
                            onPressed: (isInvioInCorso || clienteId == null)
                                ? null
                                : () async {
                              setModalState(() => isInvioInCorso = true);
                              try {
                                // MODIFICATO: Forza il refresh immediato del token utente per evitare la scadenza delle credenziali OAuth2 su iOS
                                await FirebaseAuth.instance.currentUser?.getIdToken(true);

                                final HttpsCallable callable = FirebaseFunctions.instanceFor(region: 'europe-west3')
                                    .httpsCallable('inviaSollecitoCliente');

                                await callable.call(<String, dynamic>{
                                  'userIdCliente': clienteId,
                                });

                                if (!context.mounted) return;
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Notifica inviata con successo a $clienteNome!'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              } catch (e) {
                                setModalState(() => isInvioInCorso = false);

                                // MODIFICATO: Estrae il messaggio di errore nativo proveniente dalle Cloud Functions per diagnostica
                                String erroreDettaglio = e is FirebaseFunctionsException
                                    ? e.message ?? e.toString()
                                    : e.toString();

                                if (erroreDettaglio.contains('failed-precondition')) {
                                  erroreDettaglio = 'Il cliente non ha abilitato le notifiche push sul telefono.';
                                }

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Errore: $erroreDettaglio'),
                                    backgroundColor: Colors.orange.shade800,
                                    duration: const Duration(seconds: 5),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 12),

                        SizedBox(
                          width: double.infinity,
                          height: 48,
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
                  ),
                ),
              );
            }
        );
      },
    );
  }

  Stream<Map<String, dynamic>> _ascoltaConfigurazioneOrariEDati() {
    final String docIdEccezione = _dataString;
    final String giornoSettimana = _giorniSettimanaDb[_dataSelezionata.weekday % 7];

    final snapEccezioni = FirebaseFirestore.instance.collection('calendar_exceptions').doc(docIdEccezione).snapshots();
    final snapOrariBase = FirebaseFirestore.instance.collection('settings').doc('orari_negozio').snapshots();

    return StreamZip([snapEccezioni, snapOrariBase]).map((List<DocumentSnapshot> snapshotList) {
      final docEx = snapshotList[0];
      final docBase = snapshotList[1];

      bool isNegozioAperto = true;
      String mAp = "09:00", mCh = "13:00", pAp = "14:30", pCh = "19:30";
      String stringaNota = "";

      if (docEx.exists && docEx.data() != null) {
        final datiEx = docEx.data() as Map<String, dynamic>;
        stringaNota = datiEx['nota'] ?? "";
        if (datiEx['status'] == 'chiuso') {
          isNegozioAperto = false;
        } else if (datiEx['status'] == 'aperto') {
          isNegozioAperto = true;
          if (datiEx.containsKey('mattina') && datiEx['mattina'] != null) {
            mAp = datiEx['mattina']['apertura'] ?? mAp;
            mCh = datiEx['mattina']['chiusura'] ?? mCh;
          }
          if (datiEx.containsKey('pomeriggio') && datiEx['pomeriggio'] != null) {
            pAp = datiEx['pomeriggio']['apertura'] ?? pAp;
            pCh = datiEx['pomeriggio']['chiusura'] ?? pCh;
          }
        }
      }
      else if (docBase.exists && docBase.data() != null) {
        final datiBase = docBase.data() as Map<String, dynamic>;
        if (datiBase.containsKey(giornoSettimana)) {
          final infoGiorno = datiBase[giornoSettimana] as Map<String, dynamic>;
          isNegozioAperto = infoGiorno['isAperto'] ?? true;
          if (isNegozioAperto) {
            if (infoGiorno.containsKey('mattina') && infoGiorno['mattina'] != null) {
              mAp = infoGiorno['mattina']['apertura'] ?? mAp;
              mCh = infoGiorno['mattina']['chiusura'] ?? mCh;
            }
            if (infoGiorno.containsKey('pomeriggio') && infoGiorno['pomeriggio'] != null) {
              pAp = infoGiorno['pomeriggio']['apertura'] ?? pAp;
              pCh = infoGiorno['pomeriggio']['chiusura'] ?? pCh;
            }
          }
        }
      }

      return {
        'isAperto': isNegozioAperto,
        'mattinaApertura': mAp,
        'mattinaChiusura': mCh,
        'pomeriggioApertura': pAp,
        'pomeriggioChiusura': pCh,
        'nota': stringaNota,
      };
    });
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

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final Color coloreSfondoSchermata = isDarkMode ? agScuro : const Color(0xFFF4F6F5);
    final Color coloreSfondoBarraData = isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.white;
    final Color coloreTestoSecondario = isDarkMode ? Colors.white70 : Colors.black54;
    final Color coloreLineeDivisione = isDarkMode ? Colors.grey.withValues(alpha: 0.25) : Colors.grey.shade300;
    final Color coloreLineeMezzora = isDarkMode ? Colors.grey.withValues(alpha: 0.12) : Colors.grey.shade200;

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
      body: SafeArea(
        child: Column(
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

            // 3. TIMELINE ORIENTATA DINAMICAMENTE
            Expanded(
              child: StreamBuilder<Map<String, dynamic>>(
                stream: _ascoltaConfigurazioneOrariEDati(),
                builder: (context, configSnapshot) {
                  if (configSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final config = configSnapshot.data ?? {
                    'isAperto': true,
                    'mattinaApertura': '08:00',
                    'pomeriggioChiusura': '20:00',
                    'nota': ''
                  };

                  final bool isAperto = config['isAperto'] ?? true;
                  final String notaAttuale = config['nota'] ?? "";

                  if (!isAperto) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.no_meeting_room, size: 64, color: Colors.red.shade400),
                          const SizedBox(height: 16),
                          Text(
                            'SALONE CHIUSO',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isDarkMode ? Colors.white : agVerde),
                          ),
                          if (notaAttuale.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 32.0),
                              child: Text(
                                notaAttuale,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.grey),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }

                  final int minInizio = _minutiDaStringa(config['mattinaApertura'] ?? '08:00');
                  final int minFine = _minutiDaStringa(config['pomeriggioChiusura'] ?? '20:00');

                  oraInizioGiornata = minInizio ~/ 60;
                  oraFineGiornata = (minFine / 60).ceil();

                  final int inizioMinutiTotali = oraInizioGiornata * 60;
                  final int fineMinutiTotali = oraFineGiornata * 60;
                  final int minutiTotaliGiornata = fineMinutiTotali - inizioMinutiTotali;
                  final double altezzaTotaleGriglia = minutiTotaliGiornata * altezzaPerMinuto;

                  return StreamBuilder<QuerySnapshot>(
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
                          'id': doc.id,
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
                              for (int i = oraInizioGiornata; i < oraFineGiornata; i++) ...[
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

                              for (var elem in elementiCalendario) ...[
                                (() {
                                  final data = elem['data'];
                                  final String appointmentId = elem['id'];
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
                                  final double prezzoTotale = (data['totalPrice'] ?? 0.0).toDouble();
                                  final String oraInizioStr = data['slot'] ?? '--:--';
                                  final String oraFineStr = _stringaDaMinuti(inizioMinuti + durata);

                                  // MODIFICATO: Rilevazione del flag per le prenotazioni periodiche
                                  final bool isPeriodico = data['isPeriodico'] == true;

                                  // Colori dinamici in base alla natura della prenotazione (Standard vs Periodico)
                                  final Color coloreSfondoCard = isPeriodico
                                      ? agOro.withValues(alpha: 0.95)
                                      : agVerde.withValues(alpha: 0.95);
                                  final Color coloreTestoCard = isPeriodico
                                      ? Colors.black
                                      : Colors.white;
                                  final Color colorePrezzoCard = isPeriodico
                                      ? const Color(0xFF164638)
                                      : agOro;
                                  final Color coloreBordoCard = isPeriodico
                                      ? agVerde
                                      : agOro;

                                  return Positioned(
                                    top: topPos + 2,
                                    left: leftPos,
                                    width: larghezzaCard - 4,
                                    height: altezzaBlocco - 4,
                                    child: GestureDetector(
                                      onTap: () => _mostraDettagliAppuntamento(data, oraInizioStr, oraFineStr, durata, appointmentId),
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: coloreSfondoCard,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: coloreBordoCard, width: 1.2),
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
                                                    style: TextStyle(color: coloreTestoCard, fontWeight: FontWeight.bold, fontSize: 13),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '€ ${prezzoTotale.toStringAsFixed(2).replaceAll('.', ',')}',
                                                  style: TextStyle(color: colorePrezzoCard, fontWeight: FontWeight.bold, fontSize: 13),
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
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StreamZip<T> extends StreamView<List<T>> {
  StreamZip(Iterable<Stream<T>> streams) : super(_zip(streams));

  static Stream<List<T>> _zip<T>(Iterable<Stream<T>> streams) {
    StreamController<List<T>>? mainController;

    mainController = StreamController<List<T>>(onListen: () {
      final listatiSotto = <StreamSubscription<T>>[];
      final codeElementi = List.generate(streams.length, (_) => <T>[]);

      void controllaEInvia() {
        if (codeElementi.every((c) => c.isNotEmpty)) {
          final smazzati = codeElementi.map((c) => c.removeAt(0)).toList();
          mainController!.add(smazzati);
        }
      }

      int idx = 0;
      for (var stream in streams) {
        final currentIdx = idx;
        listatiSotto.add(stream.listen((dati) {
          codeElementi[currentIdx].add(dati);
          controllaEInvia();
        }, onError: mainController!.addError, onDone: () {
          if (codeElementi[currentIdx].isEmpty) {
            mainController!.close();
          }
        }));
        idx++;
      }

      mainController!.onCancel = () async {
        for (var sub in listatiSotto) {
          await sub.cancel();
        }
      };
    });

    return mainController.stream;
  }
}