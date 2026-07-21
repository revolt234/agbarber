const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();

// 1. ELIMINA UTENTE (Corretto CORS)
exports.eliminaUtenteCompleto = onCall({ region: "europe-west3" }, async (request) => {
  const auth = request.auth;
  const data = request.data;

  // Verifica di sicurezza: l'utente deve essere autenticato
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
    const isSelfDeletion = auth.uid === uidDaEliminare;

    if (!isSelfDeletion) {
      const callerDoc = await admin.firestore().collection("users").doc(auth.uid).get();
      if (!callerDoc.exists || callerDoc.data().role !== "barbiere") {
        throw new HttpsError(
          "permission-denied",
          "Non hai i permessi per eliminare questo account."
        );
      }
    }

    await admin.auth().deleteUser(uidDaEliminare);

    const appointmentsSnapshot = await admin.firestore()
        .collection("appointments")
        .where("userId", "==", uidDaEliminare)
        .get();

    const batch = admin.firestore().batch();
    appointmentsSnapshot.docs.forEach((doc) => {
      batch.delete(doc.ref);
    });
    await batch.commit();

    await admin.firestore().collection("users").doc(uidDaEliminare).delete();

    return { success: true, message: "Utente e relative prenotazioni rimosse con successo." };
  } catch (error) {
    console.error("Errore durante l'eliminazione dell'utente:", error);
    throw new HttpsError("internal", error.message);
  }
});

// 2. CREA PRENOTAZIONE SICURA (Corretto CORS)
exports.creaPrenotazioneSicura = onCall({ region: "europe-west3" }, async (request) => {
  const auth = request.auth;
  const data = request.data;

  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Devi essere autenticato per effettuare una prenotazione."
    );
  }

  const { date, slot, duration, barberId, barberName, serviceNome, servicePrezzo } = data;

  if (!date || !slot || !duration || !barberId || !barberName || !serviceNome || !servicePrezzo) {
    throw new HttpsError(
      "invalid-argument",
      "Tutti i parametri della prenotazione sono obbligatori."
    );
  }

  const minutiDaStringa = (s) => {
    const parti = s.split(':');
    return parseInt(parti[0], 10) * 60 + parseInt(parti[1], 10);
  };

  try {
    const db = admin.firestore();

    let nomeRealeCliente = "Cliente";
    const userDoc = await db.collection("users").doc(auth.uid).get();
    if (userDoc.exists && userDoc.data()) {
      nomeRealeCliente = userDoc.data().name || auth.token.name || "Cliente";
    }

    const nuovoInizioMinuti = minutiDaStringa(slot);
    const nuovoFineMinuti = nuovoInizioMinuti + parseInt(duration, 10);
    const bloccoSlotId = `${date}_${barberId}_${slot.replace(':', '')}`;

    const risultatoTransazione = await db.runTransaction(async (transaction) => {
      const barberRef = db.collection("barbers").doc(barberId);
      await transaction.get(barberRef);

      const docBloccoRef = db.collection("appointments").doc(bloccoSlotId);
      const snapshotBlocco = await transaction.get(docBloccoRef);

      if (snapshotBlocco.exists) {
        return { success: false, error: "SLOT_OCCUPATO" };
      }

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

          if (nuovoInizioMinuti < appFine && nuovoFineMinuti > appInizio) {
            return { success: false, error: "SLOT_OCCUPATO" };
          }
        }
      }

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

// 3. INVIA SOLLECITO CLIENTE
exports.inviaSollecitoCliente = onCall({ region: "europe-west3" }, async (request) => {
  const auth = request.auth;
  const data = request.data;

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

    const callerDoc = await db.collection("users").doc(auth.uid).get();
    if (!callerDoc.exists || callerDoc.data().role !== "barbiere") {
      throw new HttpsError(
        "permission-denied",
        "Non hai i permessi per inviare un sollecito a questo cliente."
      );
    }

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
          icon: "ic_stat_name",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            // MODIFICATO: Rimosso "badge: 1" per evitare che rimanga il pallino rosso bloccato sull'icona del cliente
          },
        },
      },
      data: {
        type: "sollecito",
      }
    };

    await admin.messaging().send(messaggioPush);

    return { success: true, message: "Sollecito inviato con successo al dispositivo del cliente." };

  } catch (error) {
    // Log di produzione compatto ma estremamente utile
    console.error("Errore invio sollecito push:", error.message);
    if (error.errorInfo) {
      console.error("Dettagli errore FCM:", JSON.stringify(error.errorInfo));
    }

    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", error.message);
  }
});
// 4. INVIA NOTIFICA PERSONALIZZATA CLIENTE (Corretto CORS e aggiornato alla v2)
exports.inviaNotificaPersonalizzataCliente = onCall({ region: "europe-west3" }, async (request) => {
  const auth = request.auth;
  const data = request.data;

  // 1. Verifichiamo che l'operatore (barbiere) sia autenticato
  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "L'utente deve essere autenticato per inviare notifiche."
    );
  }

  const userIdCliente = data.userIdCliente;
  const messaggioPersonalizzato = data.messaggio;

  if (!userIdCliente || !messaggioPersonalizzato) {
    throw new HttpsError(
      "invalid-argument",
      "Parametri 'userIdCliente' o 'messaggio' mancanti."
    );
  }

  try {
    const db = admin.firestore();

    // Verifichiamo il ruolo di chi effettua la richiesta
    const callerDoc = await db.collection("users").doc(auth.uid).get();
    if (!callerDoc.exists || callerDoc.data().role !== "barbiere") {
      throw new HttpsError(
        "permission-denied",
        "Non hai i permessi per inviare comunicazioni personalizzate."
      );
    }

    // 2. Recuperiamo il documento del cliente da Firestore per estrarre il token FCM
    const userDoc = await db.collection("users").doc(userIdCliente).get();

    if (!userDoc.exists) {
      throw new HttpsError(
        "not-found",
        "Cliente non trovato nel database."
      );
    }

    const userData = userDoc.data();
    const tokenFcm = userData.fcmToken || userData.pushToken;

    if (!tokenFcm) {
      throw new HttpsError(
        "failed-precondition",
        "Il cliente non ha un token notifiche valido registrato."
      );
    }

    // 3. Costruiamo il payload della notifica push
    const payload = {
      token: tokenFcm,
      notification: {
        title: "AG Barber",
        body: messaggioPersonalizzato,
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 0, // Impostato a 0 per non causare il glitch del badge 1 su iOS
          },
        },
      },
      android: {
        notification: {
          sound: "default",
        },
      },
    };

    // 4. Inviamo la notifica tramite l'SDK di Firebase Admin
    await admin.messaging().send(payload);

    return { success: true, message: "Notifica inviata con successo!" };
  } catch (error) {
    console.error("Errore durante l'invio della notifica personalizzata:", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError(
      "internal",
      error.message || "Errore interno durante l'invio della notifica."
    );
  }
});
// 5. INVIA NOTIFICA NUOVA PRENOTAZIONE AL BARBIERE
exports.inviaNotificaNuovaPrenotazioneAlBarbiere = onCall({ region: "europe-west3" }, async (request) => {
  const auth = request.auth;
  const data = request.data;

  // 1. Verifichiamo che l'utente che ha prenotato sia autenticato
  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Devi essere autenticato per eseguire questa operazione."
    );
  }

  const { date, slot, barberId, barberName, serviceNome, clienteNome } = data;

  if (!date || !slot || !barberId || !serviceNome) {
    throw new HttpsError(
      "invalid-argument",
      "Parametri obbligatori mancanti per l'invio della notifica."
    );
  }

  try {
    const db = admin.firestore();

    // 2. Recuperiamo il profilo dell'operatore/barbiere selezionato da Firestore
    const barberDoc = await db.collection("users").doc(barberId).get();

    if (!barberDoc.exists) {
      console.warn(`Impossibile trovare il profilo del barbiere con ID: ${barberId}`);
      return { success: false, message: "Profilo barbiere non trovato." };
    }

    const barberData = barberDoc.data();
    const tokenFcmBarbiere = barberData.fcmToken || barberData.pushToken;

    if (!tokenFcmBarbiere) {
      console.warn(`Il barbiere ${barberName || barberId} non ha un token notifiche registrato.`);
      return { success: false, message: "Il barbiere non ha le notifiche push attive." };
    }

    // 3. Costruiamo il payload della notifica push per il barbiere
    const messaggioPush = {
      token: tokenFcmBarbiere,
      notification: {
        title: "Nuova Prenotazione! 💈",
        body: `${clienteNome || "Un cliente"} ha prenotato "${serviceNome}" per il ${date} alle ${slot}.`,
      },
      android: {
        priority: "high",
        notification: {
          sound: "default",
          icon: "ic_stat_name",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 0,
          },
        },
      },
      data: {
        type: "nuova_prenotazione",
      }
    };

    // 4. Inviamo la notifica push tramite Firebase Admin Messaging
    await admin.messaging().send(messaggioPush);

    return { success: true, message: "Notifica inviata con successo al barbiere." };

  } catch (error) {
    console.error("Errore durante l'invio della notifica al barbiere:", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError(
      "internal",
      error.message || "Errore interno durante l'invio della notifica al barbiere."
    );
  }
});
// 6. INVIA NOTIFICA ANNULLAMENTO PRENOTAZIONE AL BARBIERE
exports.inviaNotificaAnnullamentoAlBarbiere = onCall({ region: "europe-west3" }, async (request) => {
  const auth = request.auth;
  const data = request.data;

  // 1. Verifichiamo che l'utente sia autenticato
  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Devi essere autenticato per eseguire questa operazione."
    );
  }

  const { barberId, barberName, date, slot, serviceNome, clienteNome } = data;

  if (!barberId || !date || !slot) {
    throw new HttpsError(
      "invalid-argument",
      "Parametri obbligatori mancanti per l'invio della notifica di annullamento."
    );
  }

  try {
    const db = admin.firestore();

    // 2. Recuperiamo il profilo dell'operatore/barbiere da Firestore per estrarre il token FCM
    const barberDoc = await db.collection("users").doc(barberId).get();

    if (!barberDoc.exists) {
      console.warn(`Impossibile trovare il profilo del barbiere con ID: ${barberId}`);
      return { success: false, message: "Profilo barbiere non trovato." };
    }

    const barberData = barberDoc.data();
    const tokenFcmBarbiere = barberData.fcmToken || barberData.pushToken;

    if (!tokenFcmBarbiere) {
      console.warn(`Il barbiere ${barberName || barberId} non ha un token notifiche registrato.`);
      return { success: false, message: "Il barbiere non ha le notifiche push attive." };
    }

    // 3. Costruiamo il payload della notifica push di disdetta
    const messaggioPush = {
      token: tokenFcmBarbiere,
      notification: {
        title: "Prenotazione Annullata ❌",
        body: `${clienteNome || "Un cliente"} ha disdetto l'appuntamento per "${serviceNome || "Servizio"}" del ${date} alle ${slot}. Lo slot è di nuovo libero.`,
      },
      android: {
        priority: "high",
        notification: {
          sound: "default",
          icon: "ic_stat_name",
        },
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 0,
          },
        },
      },
      data: {
        type: "annullamento_prenotazione",
      }
    };

    // 4. Inviamo la notifica push al barbiere
    await admin.messaging().send(messaggioPush);

    return { success: true, message: "Notifica di annullamento inviata con successo al barbiere." };

  } catch (error) {
    console.error("Errore durante l'invio della notifica di annullamento:", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError(
      "internal",
      error.message || "Errore interno durante l'invio della notifica al barbiere."
    );
  }
});