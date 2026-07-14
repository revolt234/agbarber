import Flutter
import UIKit
import flutter_local_notifications // AGGIUNTO: Importa il plugin per le notifiche locali

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // AGGIUNTO: Registra il delegato per gestire correttamente la comparsa dei banner su iOS 10+
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    // AGGIUNTO: Azzera il contatore del badge all'avvio dell'applicazione
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(0) { error in
        if let error = error {
          print("Errore azzeramento badge avvio: \(error.localizedDescription)")
        }
      }
    } else {
      application.applicationIconBadgeNumber = 0
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // AGGIUNTO: Intercetta l'istante in cui l'app torna in primo piano/attiva per azzerare definitivamente il badge
  override func applicationDidBecomeActive(_ application: UIApplication) {
    if #available(iOS 16.0, *) {
      UNUserNotificationCenter.current().setBadgeCount(0) { error in
        if let error = error {
          print("Errore azzeramento badge active: \(error.localizedDescription)")
        }
      }
    } else {
      application.applicationIconBadgeNumber = 0
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}