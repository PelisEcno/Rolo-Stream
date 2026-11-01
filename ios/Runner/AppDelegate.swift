import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        
        // 1. Arrancar el proxy
        MediaFlowBridge.shared.start()

        // 2. Registrar los plugins de Flutter
        GeneratedPluginRegistrant.register(with: self)

        // 3. Crear la ventana
        let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

        // 4. Configurar el canal con el FlutterViewController
        if let controller = window?.rootViewController as? FlutterViewController {
            MediaFlowBridge.shared.register(with: controller)
        } else {
            NSLog("[MediaFlow] ⚠️ FlutterViewController no encontrado")
        }

        return result
    }

    override func applicationWillTerminate(_ application: UIApplication) {
        MediaFlowBridge.shared.stop()
    }
}