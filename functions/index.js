const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();

exports.eliminaUtenteCompleto = onCall({ region: "europe-west3", cors: true }, async (request) => {
  const auth = request.auth;
  const data = request.data;

  // 1. Verifica di sicurezza: l'utente deve essere autenticato
  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Devi essere autenticato per eseguire questa operazione."
    );
  }

  const uidDaEliminare = data.uid;
  if (!uidDaEliminare) {
    throw new HttpsError(
      "invalid-argument",
      "Il parametro 'uid' è obbligatorio."
    );
  }

  try {
    // 2. MODIFICATO: Controllo flessibile dei permessi (Barbiere autorizzato OPPURE Autocancellazione del cliente)
    const isSelfDeletion = auth.uid === uidDaEliminare;

    if (!isSelfDeletion) {
      // Se non si sta cancellando da solo, l'utente che chiama deve essere per forza un barbiere
      const callerDoc = await admin.firestore().collection("users").doc(auth.uid).get();
      if (!callerDoc.exists || callerDoc.data().role !== "barbiere") {
        throw new HttpsError(
          "permission-denied",
          "Non hai i permessi per eliminare questo account."
        );
      }
    }

    // 3. ELIMINAZIONE DA FIREBASE AUTHENTICATION
    await admin.auth().deleteUser(uidDaEliminare);

    // 4. Cerca ed elimina tutte le prenotazioni collegate a questo utente
    const appointmentsSnapshot = await admin.firestore()
        .collection("appointments")
        .where("userId", "==", uidDaEliminare)
        .get();

    const batch = admin.firestore().batch();
    appointmentsSnapshot.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });
    // Esegue la cancellazione atomica di tutte le prenotazioni trovate
    await batch.commit();

    // 5. Elimina il documento dell'utente da Cloud Firestore
    await admin.firestore().collection("users").doc(uidDaEliminare).delete();

    return { success: true, message: "Utente e relative prenotazioni rimosse con successo." };
  } catch (error) {
    console.error("Errore durante l'eliminazione dell'utente:", error);
    throw new HttpsError("internal", error.message);
  }
});
exports.creaPrenotazioneSicura = onCall({ region: "europe-west3", cors: true }, async (request) => {
  const auth = request.auth;
  const data = request.data;

  // 1. Verifica di sicurezza iniziale
  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Devi essere autenticato per effettuare una prenotazione."
    );
  }

  // Estrazione e validazione parametri obbligatori inviati dal client
  const { date, slot, duration, barberId, barberName, serviceNome, servicePrezzo } = data;

  if (!date || !slot || !duration || !barberId || !barberName || !serviceNome || !servicePrezzo) {
    throw new HttpsError(
      "invalid-argument",
      "Tutti i parametri della prenotazione sono obbligatori."
    );
  }

  // Funzione di utilità interna per convertire "HH:mm" in minuti totali dall'inizio della giornata
  const minutiDaStringa = (s) => {
    const parti = s.split(':');
    return parseInt(parti[0], 10) * 60 + parseInt(parti[1], 10);
  };

  try {
    const db = admin.firestore();

    // 2. Recupero del nome reale dell'utente dal suo record utente in Firestore
    let nomeRealeCliente = "Cliente";
    const userDoc = await db.collection("users").doc(auth.uid).get();
    if (userDoc.exists && userDoc.data()) {
      nomeRealeCliente = userDoc.data().name || auth.token.name || "Cliente";
    }

    const nuovoInizioMinuti = minutiDaStringa(slot);
    const nuovoFineMinuti = nuovoInizioMinuti + parseInt(duration, 10);

    // Costruzione della chiave univoca per bloccare lo slot al millesimo di secondo
    const bloccoSlotId = `${date}_${barberId}_${slot.replace(':', '')}`;

    // 3. Esecuzione della Transazione Atomica Centralizzata Lato Server Blindata
    const risultatoTransazione = await db.runTransaction(async (transaction) => {

      // SOLUZIONE PROFESSIONALE: Acquisiamo un lucchetto (Lock) sul documento del barbiere specifico.
      // Qualsiasi altra prenotazione concomitante per questo barbiere dovrà attendere in coda seriale,
      // azzerando i conflitti di lettura della query.
      const barberRef = db.collection("barbers").doc(barberId);
      await transaction.get(barberRef);

      const docBloccoRef = db.collection("appointments").doc(bloccoSlotId);
      const snapshotBlocco = await transaction.get(docBloccoRef);

      // Se il documento con ID univoco esiste già, lo slot esatto è occupato
      if (snapshotBlocco.exists) {
        return { success: false, error: "SLOT_OCCUPATO" };
      }

      // MODIFICATO: Eseguiamo la query di controllo passandola dentro transaction.get()
      // Questo dice a Firestore di tracciare l'intero set di dati e invalidare la transazione se cambia qualcosa
      const queryIncastri = db.collection("appointments")
        .where("date", "==", date)
        .where("barberId", "==", barberId);

      const querySnapshot = await transaction.get(queryIncastri);

      for (const doc of querySnapshot.docs) {
        const datiApp = doc.data();
        if (datiApp.slot) {
          const appInizio = minutiDaStringa(datiApp.slot);
          const appDurata = datiApp.duration || datiApp.totalDuration || datiApp.services_duration || 30;
          const appFine = appInizio + appDurata;

          // Se i tempi si sovrappongono, respingi immediatamente
          if (nuovoInizioMinuti < appFine && nuovoFineMinuti > appInizio) {
            return { success: false, error: "SLOT_OCCUPATO" };
          }
        }
      }

      // 4. Se tutti i controlli passano, inseriamo l'appuntamento
      transaction.set(docBloccoRef, {
        date: date,
        slot: slot,
        duration: parseInt(duration, 10),
        barberId: barberId,
        barberName: barberName,
        userId: auth.uid,
        userName: nomeRealeCliente,
        userEmail: auth.token.email || 'Cliente anonimo',
        services: [serviceNome],
        totalPrice: parseFloat(servicePrezzo),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return { success: true, appointmentId: bloccoSlotId };
    });

    if (!risultatoTransazione.success) {
      throw new HttpsError("already-exists", "Lo slot orario selezionato si sovrappone o è già stato prenotato.");
    }

    return {
      success: true,
      message: "Prenotazione registrata con successo.",
      appointmentId: risultatoTransazione.appointmentId
    };

  } catch (error) {
    console.error("Errore durante la transazione di prenotazione:", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", error.message);
  }
});
// Esportazione completa e aggiornata nel file index.js delle tue Cloud Functions

exports.inviaSollecitoCliente = onCall({ region: "europe-west3", cors: true }, async (request) => {
  const auth = request.auth;
  const data = request.data;

  // 1. Verifica di sicurezza: il mittente deve essere autenticato
  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Devi essere autenticato per eseguire questa operazione."
    );
  }

  const { userIdCliente } = data;
  if (!userIdCliente) {
    throw new HttpsError(
      "invalid-argument",
      "Il parametro 'userIdCliente' è obbligatorio."
    );
  }

  try {
    const db = admin.firestore();

    // 2. Controllo dei permessi: solo un barbiere può inviare solleciti
    const callerDoc = await db.collection("users").doc(auth.uid).get();
    if (!callerDoc.exists || callerDoc.data().role !== "barbiere") {
      throw new HttpsError(
        "permission-denied",
        "Non hai i permessi per inviare un sollecito a questo cliente."
      );
    }

    // 3. Recupero del documento del cliente per estrarre il token di notifica (fcmToken)
    const clientDoc = await db.collection("users").doc(userIdCliente).get();
    if (!clientDoc.exists) {
      throw new HttpsError("not-found", "Impossibile trovare il profilo del cliente.");
    }

    const clienteData = clientDoc.data();
    const fcmToken = clienteData.fcmToken || clienteData.pushToken;

    if (!fcmToken) {
      throw new HttpsError(
        "failed-precondition",
        "Il cliente non ha le notifiche push attive o un dispositivo registrato."
      );
    }

    // 4. Costruzione e invio del payload della notifica push tramite Firebase Cloud Messaging
    const messaggioPush = {
      token: fcmToken,
      notification: {
        title: "Il barbiere ti aspetta! 💈",
        body: "Ehi dove sei? Il barbiere ti sta aspettando al salone!",
      },
      android: {
        priority: "high",
        notification: {
          sound: "default",
          // CORRETTO: Sostituito clickAction (deprecato) con click_action in snake_case richiesto da Android
          click_action: "FLUTTER_NOTIFICATION_CLICK",
          icon: "ic_stat_name",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 1,
            // AGGIUNTO: Forza la categoria di click action anche per i dispositivi iOS
            category: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
      },
      // Il blocco data globale permette a Flutter di intercettare il tap sia a schermo spento che in background
      data: {
        click_action: "FLUTTER_NOTIFICATION_CLICK",
        type: "sollecito",
      }
    };

    // Invia il messaggio al dispositivo del cliente
    await admin.messaging().send(messaggioPush);

    return { success: true, message: "Sollecito inviato con successo al dispositivo del cliente." };

  } catch (error) {
    console.error("Errore durante l'invio del sollecito push:", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", error.message);
  }
});