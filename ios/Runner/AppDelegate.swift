import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 1. Arrancar el proxy
        MediaFlowBridge.shared.start()
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // Este método es el que usa Flutter 3.44+ para registrar plugins con SceneDelegate
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        
        // Registrar el canal del proxy
        if let controller = engineBridge.viewController as? FlutterViewController {
            MediaFlowBridge.shared.register(with: controller)
        }
    }
    
    override func applicationWillTerminate(_ application: UIApplication) {
        MediaFlowBridge.shared.stop()
    }
}