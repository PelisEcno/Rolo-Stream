import Foundation
import UIKit
import Flutter

// MARK: - Bridge

class MediaFlowBridge {
    static let shared = MediaFlowBridge()

    private var serverPtr: UnsafeMutableRawPointer?
    private let channelName = "com.rolostream/mediaflow"

    private init() {}

    /// Registra el MethodChannel para que Dart pueda controlar el proxy
    func register(with controller: FlutterViewController) {
        let channel = FlutterMethodChannel(
            name: channelName,
            binaryMessenger: controller.binaryMessenger
        )

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { return }

            switch call.method {
            case "proxyStatus":
                guard let ptr = self.serverPtr else {
                    result(false)
                    return
                }
                let running = mediaflow_server_is_running(ptr)
                result(running)

            case "proxyDiagnostic":
                guard let ptr = self.serverPtr else {
                    result("iOS Proxy: ❌ no inicializado")
                    return
                }
                let running = mediaflow_server_is_running(ptr)
                let port = mediaflow_server_port(ptr)
                let diag = "iOS Proxy: \(running ? "✅ corriendo" : "❌ parado") puerto \(port)"
                result(diag)

            case "testExtraction":
                self.testExtraction { success, message in
                    result(message)
                }

            case "openPlayer":
                result(FlutterMethodNotImplemented)

            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    /// Arranca el proxy en background.
    func start() {
        guard serverPtr == nil else {
            NSLog("[MediaFlow] Ya estaba corriendo")
            return
        }

        // MARK: - Variables de entorno (deben coincidir con el Rust)
        setenv("APP__SERVER__WORKERS", "1", 1)
        setenv("APP__SERVER__HOST", "127.0.0.1", 1)
        setenv("APP__SERVER__PORT", "8888", 1)
        setenv("APP__AUTH__API_PASSWORD", "changeme", 1)

        setenv("APP__PROXY__CONNECT_TIMEOUT", "30", 1)
        setenv("APP__PROXY__BUFFER_SIZE", "262144", 1)
        setenv("APP__PROXY__FOLLOW_REDIRECTS", "true", 1)
        setenv("APP__PROXY__REQUEST_TIMEOUT_FACTOR", "8", 1)
        setenv("APP__PROXY__MAX_CONCURRENT_PER_HOST", "10", 1)
        setenv("APP__PROXY__POOL_IDLE_TIMEOUT", "90", 1)
        setenv("APP__PROXY__POOL_MAX_IDLE_PER_HOST", "100", 1)

        // MARK: - Strings estáticos (NO necesitan free)
        // Usamos literales C directamente. El Rust NO debe liberarlos.
        let host: UnsafeMutablePointer<CChar>? = UnsafeMutablePointer(mutating: ("127.0.0.1" as NSString).utf8String)
        let password: UnsafeMutablePointer<CChar>? = UnsafeMutablePointer(mutating: ("changeme" as NSString).utf8String)

        var config = MediaflowConfig(
            host: host,
            port: 8888,
            api_password: password,
            redis_url: nil,
            config_json: nil
        )

        let ptr = withUnsafePointer(to: &config) { cfgPtr -> UnsafeMutableRawPointer? in
            return mediaflow_server_create(cfgPtr)
        }

        guard let serverPtr = ptr else {
            NSLog("[MediaFlow] ❌ Error creando server handle")
            return
        }

        let status = mediaflow_server_start(serverPtr)

        if status == MediaflowStatusOk {
            self.serverPtr = serverPtr
            let port = mediaflow_server_port(serverPtr)
            NSLog("[MediaFlow] ✅ Server arrancado en 127.0.0.1:\(port)")
            // NO mostrar alert aquí — bloquea la UX
        } else {
            NSLog("[MediaFlow] ❌ Error arrancando server: \(status.rawValue)")
            mediaflow_server_destroy(serverPtr)
            self.showAlert(
                title: "❌ Proxy NO arrancó",
                message: "Error code: \(status.rawValue)"
            )
        }
    }

    /// Detiene el proxy limpiamente.
    func stop() {
        guard let serverPtr = serverPtr else { return }
        _ = mediaflow_server_stop(serverPtr)
        mediaflow_server_destroy(serverPtr)
        self.serverPtr = nil
        NSLog("[MediaFlow] 🛑 Server detenido")
    }

    // MARK: - Helpers

    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.windows.first,
                  let rootVC = window.rootViewController else {
                NSLog("[MediaFlow] ⚠️ No hay rootViewController")
                return
            }

            let alert = UIAlertController(
                title: title,
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            rootVC.present(alert, animated: true)
        }
    }

    /// Test genérico de extracción (no hardcodeado).
    private func testExtraction(completion: @escaping (Bool, String) -> Void) {
        // Endpoint /health para verificar que el proxy responde
        let urlString = "http://127.0.0.1:8888/health"

        guard let url = URL(string: urlString) else {
            completion(false, "URL inválida")
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(false, "Error: \(error.localizedDescription)")
                return
            }

            guard let data = data, let body = String(data: data, encoding: .utf8) else {
                completion(false, "Sin respuesta")
                return
            }

            completion(true, "OK: \(body.prefix(200))")
        }
        task.resume()
    }
}