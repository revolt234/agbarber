const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");
admin.initializeApp();

// 0. PULIZIA AUTOMATICA PRENOTAZIONI VECCHIE (Eseguita ogni 9 giorni)
exports.puliziaPrenotazioniVecchie = onSchedule(
  {
    schedule: "0 3 */9 * *", // Alle 03:00 del mattino, ogni 9 giorni
    timeZone: "Europe/Rome",
    region: "europe-west3",
  },
  async (event) => {
    console.log("Starting automatic cleanup of appointments older than 7 days...");

    const db = admin.firestore();
    const adesso = new Date();

    // Calcola la data e l'ora limite di 7 giorni fa
    const limiteSetteGiorniFa = new Date(adesso.getTime() - 7 * 24 * 60 * 60 * 1000);

    try {
      const appointmentsSnap = await db.collection("appointments").get();

      if (appointmentsSnap.empty) {
        console.log("No appointments found in database.");
        return;
      }

      const batch = db.batch();
      let contatoreEliminati = 0;

      appointmentsSnap.docs.forEach((doc) => {
        const data = doc.data();
        const dateStr = data.date; // Formato previsto: "YYYY-MM-DD"
        const slotStr = data.slot; // Formato previsto: "HH:mm"

        if (dateStr && slotStr) {
          // Ricostruisce la data e l'orario completo dell'appuntamento
          const orarioAppuntamento = new Date(`${dateStr}T${slotStr}:00`);

          // Se l'appuntamento è avvenuto più di 7 giorni fa, viene accodato per l'eliminazione
          if (orarioAppuntamento < limiteSetteGiorniFa) {
            batch.delete(doc.ref);
            contatoreEliminati++;
          }
        }
      });

      if (contatoreEliminati > 0) {
        await batch.commit();
        console.log(`Successfully deleted ${contatoreEliminati} old appointment(s).`);
      } else {
        console.log("No old appointments to delete.");
      }
    } catch (error) {
      console.error("Error during automatic appointment cleanup:", error);
    }
  }
);
// 1. ELIMINA UTENTE
exports.eliminaUtenteCompleto = onCall({ region: "europe-west3" }, async (request) => {
  const auth = request.auth;
  const data = request.data;

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

// 2. CREA PRENOTAZIONE SICURA
exports.creaPrenotazioneSicura = onCall({ region: "europe-west3" }, async (request) => {
  const auth = request.auth;
  const data = request.data;

  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Devi essere autenticato per effettuare una prenotazione."
    );
  }

  const { date, slot, duration, barberId, barberName, serviceNome, servicePrezzo, targetUserId, targetUserName, nota } = data;

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

    // Determinazione dell'ID cliente (targetUserId se prenotato dal barbiere, altrimenti auth.uid)
    const effectiveUserId = targetUserId || auth.uid;

    let nomeRealeCliente = targetUserName || "Cliente";
    let emailCliente = (auth.token && auth.token.email) ? auth.token.email : "Cliente anonimo";

    // Se NON è un ospite non registrato, recupera le informazioni dal profilo utente in Firestore
    if (effectiveUserId !== "OSPITE") {
      const userDoc = await db.collection("users").doc(effectiveUserId).get();
      if (userDoc.exists && userDoc.data()) {
        const userData = userDoc.data();
        if (!targetUserName) {
          nomeRealeCliente = userData.name || userData.nome || (auth.token && auth.token.name) || "Cliente";
        }
        emailCliente = userData.email || emailCliente;
      }
    } else {
      emailCliente = "Cliente Non Registrato";
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

      const appuntamentoData = {
        date: date,
        slot: slot,
        duration: parseInt(duration, 10),
        barberId: barberId,
        barberName: barberName,
        userId: effectiveUserId,
        userName: nomeRealeCliente,
        userEmail: emailCliente,
        services: [serviceNome],
        totalPrice: parseFloat(servicePrezzo),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      if (nota && typeof nota === 'string' && nota.trim().length > 0) {
        appuntamentoData.nota = nota.trim();
      }

      transaction.set(docBloccoRef, appuntamentoData);

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

// Helper per estrarre tutti i token validi da un documento utente (multi-dispositivo con fallback)
function estraiTuttiIToken(datiUtente) {
  const tokens = new Set();

  // Array multi-dispositivo (sistema attuale)
  if (Array.isArray(datiUtente.fcmTokens)) {
    datiUtente.fcmTokens.forEach((t) => {
      if (t && typeof t === 'string' && t.trim().length > 0) tokens.add(t.trim());
    });
  }

  // Fallback campo singolo (sistema precedente)
  if (datiUtente.fcmToken && typeof datiUtente.fcmToken === 'string') {
    tokens.add(datiUtente.fcmToken.trim());
  }

  return Array.from(tokens);
}

// Helper per inviare push a una lista di token e pulire i token non più validi
async function inviaNotificheEPulisciToken(tokens, messaggioBase, userDocRef) {
  const invii = tokens.map(async (token) => {
    try {
      const messaggioPush = { ...messaggioBase, token: token };
      await admin.messaging().send(messaggioPush);
    } catch (err) {
      // Se il token è invalido o il dispositivo si è disconnesso/ha disinstallato, lo rimuoviamo dal DB
      if (
        err.code === 'messaging/invalid-registration-token' ||
        err.code === 'messaging/registration-token-not-registered'
      ) {
        if (userDocRef) {
          await userDocRef.update({
            fcmTokens: admin.firestore.FieldValue.arrayRemove(token)
          });
        }
      }
      console.warn(`Invio notifica fallito per il token ${token}:`, err.message);
    }
  });

  await Promise.all(invii);
}
// 3. INVIA SOLLECITO CLIENTE (Multi-Dispositivo con Autopulizia Token)
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

    const clientRef = db.collection("users").doc(userIdCliente);
    const clientDoc = await clientRef.get();
    if (!clientDoc.exists) {
      throw new HttpsError("not-found", "Impossibile trovare il profilo del cliente.");
    }

    const tokens = estraiTuttiIToken(clientDoc.data());

    if (tokens.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "Il cliente non ha le notifiche push attive o un dispositivo registrato."
      );
    }

    const testoNotifica = "Ehi dove sei? Il barbiere ti sta aspettando al salone!";

    const messaggioBase = {
      notification: {
        title: "Il barbiere ti aspetta! 💈",
        body: testoNotifica,
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
          },
        },
      },
      data: {
        type: "sollecito",
      }
    };

    await inviaNotificheEPulisciToken(tokens, messaggioBase, clientRef);

    return { success: true, message: `Sollecito inviato con successo.` };

  } catch (error) {
    console.error("Errore invio sollecito push:", error.message);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", error.message);
  }
});

// 4. INVIA NOTIFICA PERSONALIZZATA CLIENTE (Multi-Dispositivo con Autopulizia Token)
exports.inviaNotificaPersonalizzataCliente = onCall({ region: "europe-west3" }, async (request) => {
  const auth = request.auth;
  const data = request.data;

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

    const callerDoc = await db.collection("users").doc(auth.uid).get();
    if (!callerDoc.exists || callerDoc.data().role !== "barbiere") {
      throw new HttpsError(
        "permission-denied",
        "Non hai i permessi per inviare comunicazioni personalizzate."
      );
    }

    const userRef = db.collection("users").doc(userIdCliente);
    const userDoc = await userRef.get();

    if (!userDoc.exists) {
      throw new HttpsError(
        "not-found",
        "Cliente non trovato nel database."
      );
    }

    const tokens = estraiTuttiIToken(userDoc.data());

    if (tokens.length === 0) {
      throw new HttpsError(
        "failed-precondition",
        "Il cliente non ha dispositivi attivi per ricevere notifiche."
      );
    }

    const messaggioBase = {
      notification: {
        title: "AG Barber",
        body: messaggioPersonalizzato,
      },
      apns: {
        payload: {
          aps: {
            sound: "default",
            badge: 0,
          },
        },
      },
      android: {
        priority: "high",
        notification: {
          sound: "default",
        },
      },
    };

    await inviaNotificheEPulisciToken(tokens, messaggioBase, userRef);

    return { success: true, message: `Notifica inviata con successo!` };
  } catch (error) {
    console.error("Errore durante l'invio della notifica personalizzata:", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError(
      "internal",
      error.message || "Errore interno durante l'invio della notifica."
    );
  }
});

// 5. INVIA NOTIFICA NUOVA PRENOTAZIONE AL BARBIERE (Multi-Dispositivo Simultaneo con Autopulizia Token)
exports.inviaNotificaNuovaPrenotazioneAlBarbiere = onCall({ region: "europe-west3" }, async (request) => {
  const auth = request.auth;
  const data = request.data;

  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Devi essere autenticato per eseguire questa operazione."
    );
  }

  const { date, slot, barberName, serviceNome, clienteNome } = data;

  if (!date || !slot || !serviceNome) {
    throw new HttpsError(
      "invalid-argument",
      "Parametri obbligatori mancanti per l'invio della notifica."
    );
  }

  try {
    const db = admin.firestore();

    const barbieriSnap = await db.collection("users").where("role", "==", "barbiere").get();

    if (barbieriSnap.empty) {
      console.warn("Nessun utente con ruolo 'barbiere' trovato nel database.");
      return { success: false, message: "Nessun barbiere trovato." };
    }

    const dateFormatted = date.split('-').reverse().join('/');
    const testoNotifica = `${dateFormatted} ore ${slot} con ${barberName || "lo staff"}: ${clienteNome || "Un cliente"} - ${serviceNome}`;

    const messaggioBase = {
      notification: {
        title: "Nuova Prenotazione! 💈",
        body: testoNotifica,
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
      },
    };

    const inviiGruppo = barbieriSnap.docs.map(async (doc) => {
      const tokens = estraiTuttiIToken(doc.data());
      if (tokens.length > 0) {
        await inviaNotificheEPulisciToken(tokens, messaggioBase, doc.ref);
      }
    });

    await Promise.all(inviiGruppo);

    return { success: true, message: `Notifica inviata con successo.` };

  } catch (error) {
    console.error("Errore durante l'invio della notifica al barbiere:", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError(
      "internal",
      error.message || "Errore interno durante l'invio della notifica al barbiere."
    );
  }
});

// 6. INVIA NOTIFICA ANNULLAMENTO PRENOTAZIONE AL BARBIERE (Multi-Dispositivo Simultaneo con Autopulizia Token)
exports.inviaNotificaAnnullamentoAlBarbiere = onCall({ region: "europe-west3" }, async (request) => {
  const auth = request.auth;
  const data = request.data;

  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Devi essere autenticato per eseguire questa operazione."
    );
  }

  const { date, slot, barberName, serviceNome, clienteNome } = data;

  if (!date || !slot) {
    throw new HttpsError(
      "invalid-argument",
      "Parametri obbligatori mancanti per l'invio della notifica di annullamento."
    );
  }

  try {
    const db = admin.firestore();

    const barbieriSnap = await db.collection("users").where("role", "==", "barbiere").get();

    if (barbieriSnap.empty) {
      console.warn("Nessun utente con ruolo 'barbiere' trovato nel database.");
      return { success: false, message: "Nessun barbiere trovato." };
    }

    const dateFormatted = date.split('-').reverse().join('/');
    const testoAnnullamento = `${dateFormatted} ore ${slot} con ${barberName || "Staff"}: ${clienteNome || "Un cliente"} - ${serviceNome || "Servizio"}.`;

    const messaggioBase = {
      notification: {
        title: "Prenotazione Annullata ❌",
        body: testoAnnullamento,
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
      },
    };

    const inviiGruppo = barbieriSnap.docs.map(async (doc) => {
      const tokens = estraiTuttiIToken(doc.data());
      if (tokens.length > 0) {
        await inviaNotificheEPulisciToken(tokens, messaggioBase, doc.ref);
      }
    });

    await Promise.all(inviiGruppo);

    return { success: true, message: `Notifica di annullamento inviata con successo.` };

  } catch (error) {
    console.error("Errore durante l'invio della notifica di annullamento:", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError(
      "internal",
      error.message || "Errore interno durante l'invio della notifica al barbiere."
    );
  }
});

// 7. CREA PRENOTAZIONI PERIODICHE SICURE (Solo Barbiere/Admin)
exports.creaPrenotazioniPeriodicheSicure = onCall({ region: "europe-west3" }, async (request) => {
  const auth = request.auth;
  const data = request.data;

  if (!auth) {
    throw new HttpsError(
      "unauthenticated",
      "Devi essere autenticato per eseguire questa operazione."
    );
  }

  const { userIdCliente, barberId, barberName, serviceNome, servicePrezzo, duration, dateList, slot } = data;

  if (!userIdCliente || !barberId || !barberName || !serviceNome || !servicePrezzo || !duration || !dateList || !slot) {
    throw new HttpsError(
      "invalid-argument",
      "Parametri obbligatori mancanti per la creazione del periodico."
    );
  }

  const minutiDaStringa = (s) => {
    const parti = s.split(':');
    return parseInt(parti[0], 10) * 60 + parseInt(parti[1], 10);
  };

  try {
    const db = admin.firestore();

    const callerDoc = await db.collection("users").doc(auth.uid).get();
    if (!callerDoc.exists || callerDoc.data().role !== "barbiere") {
      throw new HttpsError(
        "permission-denied",
        "Solo un operatore o barbiere può creare prenotazioni periodiche."
      );
    }

    const clientDoc = await db.collection("users").doc(userIdCliente).get();
    if (!clientDoc.exists) {
      throw new HttpsError("not-found", "Cliente non trovato nel database.");
    }

    const clienteData = clientDoc.data();
    const nomeClienteReale = clienteData.name || clienteData.nome || "Cliente";
    const emailCliente = clienteData.email || "Cliente anonimo";

    const nuovoInizioMinuti = minutiDaStringa(slot);
    const nuovoFineMinuti = nuovoInizioMinuti + parseInt(duration, 10);

    const adessoLocaleStr = new Date().toLocaleString("en-US", { timeZone: "Europe/Rome" });
    const adesso = new Date(adessoLocaleStr);
    const anno = adesso.getFullYear();
    const mese = String(adesso.getMonth() + 1).padStart(2, '0');
    const giorno = String(adesso.getDate()).padStart(2, '0');
    const oggiDataStr = `${anno}-${mese}-${giorno}`;
    const minutiAttualiServer = adesso.getHours() * 60 + adesso.getMinutes();

    let createConSuccesso = 0;
    let saltateOccupate = 0;
    const dateSaltate = [];

    for (const dateStr of dateList) {
      if (dateStr === oggiDataStr && nuovoInizioMinuti <= minutiAttualiServer) {
        saltateOccupate++;
        dateSaltate.push(dateStr);
        continue;
      }

      const bloccoSlotId = `${dateStr}_${barberId}_${slot.replace(':', '')}`;

      const esitoInserimento = await db.runTransaction(async (transaction) => {
        const docBloccoRef = db.collection("appointments").doc(bloccoSlotId);
        const snapshotBlocco = await transaction.get(docBloccoRef);

        if (snapshotBlocco.exists) {
          return false;
        }

        const queryIncastri = db.collection("appointments")
          .where("date", "==", dateStr)
          .where("barberId", "==", barberId);

        const querySnapshot = await transaction.get(queryIncastri);

        let siSovrappone = false;
        for (const doc of querySnapshot.docs) {
          const datiApp = doc.data();
          if (datiApp.slot) {
            const appInizio = minutiDaStringa(datiApp.slot);
            const appDurata = datiApp.duration || datiApp.totalDuration || 30;
            const appFine = appInizio + appDurata;

            if (nuovoInizioMinuti < appFine && nuovoFineMinuti > appInizio) {
              siSovrappone = true;
              break;
            }
          }
        }

        if (siSovrappone) {
          return false;
        }

        transaction.set(docBloccoRef, {
          date: dateStr,
          slot: slot,
          duration: parseInt(duration, 10),
          barberId: barberId,
          barberName: barberName,
          userId: userIdCliente,
          userName: nomeClienteReale,
          userEmail: emailCliente,
          services: [serviceNome],
          totalPrice: parseFloat(servicePrezzo),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          isPeriodico: true
        });

        return true;
      });

      if (esitoInserimento === true) {
        createConSuccesso++;
      } else {
        saltateOccupate++;
        dateSaltate.push(dateStr);
      }
    }

    return {
      success: true,
      createConSuccesso,
      saltateOccupate,
      dateSaltate,
      message: `Processo completato: ${createConSuccesso} create, ${saltateOccupate} saltate.`
    };

  } catch (error) {
    console.error("Errore durante la creazione delle prenotazioni periodiche:", error);
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", error.message);
  }
});