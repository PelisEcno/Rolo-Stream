package com.example.rolostream

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.rolostream/mediaflow"
    private lateinit var proxyManager: ProxyManager

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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startProxy" -> {
                        // Si Dart lo llama, lanzamos en background también
                        Thread {
                            proxyManager.start()
                        }.start()
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

    override fun onDestroy() {
        if (::proxyManager.isInitialized) {
            proxyManager.stop()
        }
        super.onDestroy()
    }
}