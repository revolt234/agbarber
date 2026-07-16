import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // CORRETTO: Registra il delegato in modo sicuro impostando self
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    // Azzera il contatore del badge all'avvio dell'applicazione
    self.azzeraBadge()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Intercetta l'istante in cui l'app torna attiva per azzerare definitivamente il badge
  override func applicationDidBecomeActive(_ application: UIApplication) {
    self.azzeraBadge()
  }

  // Funzione di supporto isolata per evitare duplicazione di codice
  private func azzeraBadge() {
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(0) { error in
        if let error = error {
          print("Errore azzeramento badge: \(error.localizedDescription)")
        }
      }
    } else {
      UIApplication.shared.applicationIconBadgeNumber = 0
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}