package com.example.rolostream

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.rolostream/mediaflow"
    private lateinit var proxyManager: ProxyManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        proxyManager = ProxyManager(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startProxy" -> {
                        proxyManager.start()
                        result.success(8888) // Devuelve el puerto
                    }
                    "stopProxy" -> {
                        proxyManager.stop()
                        result.success(null)
                    }
                    "proxyStatus" -> result.success(proxyManager.isRunning())
                    "proxyDiagnostic" -> result.success("Proxy en: ${proxyManager.isRunning()}")
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        if (::proxyManager.isInitialized) proxyManager.stop()
        super.onDestroy()
    }
}