package com.jcstudiodev.rolostream

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.rolostream/mediaflow"
    private lateinit var proxyManager: ProxyManager
    private var videoPlayers: NativeVideoPlayer? = null

    companion object {
        private const val TAG = "MainActivity"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        proxyManager = ProxyManager(this)

        // Arrancar el proxy en un hilo de fondo para no bloquear la UI
        Thread {
            try {
                proxyManager.start()
                runOnUiThread {
                    if (proxyManager.isRunning()) {
                        Log.i(TAG, "✅ Proxy iniciado correctamente")
                    } else {
                        Log.e(TAG, "❌ El proxy no arrancó correctamente")
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error crítico iniciando el proxy: ${e.message}")
            }
        }.start()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        videoPlayers = NativeVideoPlayer(this, flutterEngine.dartExecutor.binaryMessenger, flutterEngine.renderer)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startProxy" -> {
                        // Si Dart lo llama, lanzamos en background también
                        runInBackground { proxyManager.start() }
                        result.success(8888)
                    }
                    "restartProxy" -> {
                        runInBackground { proxyManager.restart() }
                        result.success(8888)
                    }
                    "stopProxy" -> {
                        proxyManager.stop()
                        result.success(null)
                    }
                    "proxyStatus" -> result.success(proxyManager.isRunning())
                    "proxyDiagnostic" -> {
                        val nativeDir = applicationInfo.nativeLibraryDir
                        val binary = java.io.File(nativeDir, "libmediaflow-proxy.so")
                        result.success("Proxy: ${if (proxyManager.isRunning()) "✅" else "❌"} | Binario: ${if (binary.exists()) "✅" else "❌"}")
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// Una excepción sin capturar en un hilo cierra toda la app: el proxy no puede tumbarla.
    private fun runInBackground(block: () -> Unit) {
        Thread {
            try {
                block()
            } catch (e: Exception) {
                Log.e(TAG, "Error en el proxy: ${e.message}", e)
            }
        }.start()
    }

    override fun onDestroy() {
        videoPlayers?.disposeAll()
        if (::proxyManager.isInitialized) {
            proxyManager.stop()
        }
        super.onDestroy()
    }
}