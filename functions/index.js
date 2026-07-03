const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();

exports.eliminaUtenteCompleto = onCall({ region: "us-central1", cors: true }, async (request) => {
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