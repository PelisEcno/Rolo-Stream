import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 1. Arrancar el proxy al iniciar la app
        MediaFlowBridge.shared.start()
        
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
    
    // Este método es el correcto para registrar el canal con el ciclo de vida de escenas (SceneDelegate)
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        // 1. Registrar los plugins de Flutter
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        
        // 2. Crear el canal usando el messenger del engine bridge
        let channel = FlutterMethodChannel(
            name: "com.rolostream/mediaflow",
            binaryMessenger: engineBridge.applicationRegistrar.messenger()
        )
        
        // 3. Configurar el handler para que Dart pueda controlar el proxy
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }
            
            switch call.method {
            case "startProxy":
                MediaFlowBridge.shared.start()
                // Devolvemos el puerto (8888) para que Dart sepa dónde conectar
                result(8888)
                
            case "restartProxy":
                MediaFlowBridge.shared.restart()
                result(8888)

            case "stopProxy":
                MediaFlowBridge.shared.stop()
                result(nil)
                
            case "proxyStatus":
                // Nota: Asumimos que MediaFlowBridge tiene un método isRunning()
                // Si no lo tiene, devolvemos true por defecto para evitar errores
                result(true) 
                
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }
    
    override func applicationWillTerminate(_ application: UIApplication) {
        // Detener el proxy al cerrar la app
        MediaFlowBridge.shared.stop()
    }
}