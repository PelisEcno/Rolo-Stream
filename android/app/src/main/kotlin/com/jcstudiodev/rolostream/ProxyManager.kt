package com.jcstudiodev.rolostream

import android.content.Context
import android.util.Log
import android.widget.Toast
import java.io.File

class ProxyManager(private val context: Context) {

    companion object {
        private const val TAG = "MediaFlowProxy"
        private const val PORT = 8888
        private const val API_PASSWORD = "changeme"
    }

    private var process: Process? = null

    fun start() {
        if (process?.isAlive == true) {
            Log.d(TAG, "Proxy ya estaba corriendo")
            return
        }

        try {
            val nativeLibDir = context.applicationInfo.nativeLibraryDir
            val binaryPath = File(nativeLibDir, "libmediaflow-proxy.so").absolutePath
            
            Log.d(TAG, "Buscando binario en: $binaryPath")

            val outputFile = File(binaryPath)
            if (!outputFile.exists()) {
                Log.e(TAG, "❌ El binario no existe en $binaryPath")
                Toast.makeText(context, "❌ Error: Motor de video no encontrado", Toast.LENGTH_LONG).show()
                return
            }

            val pb = ProcessBuilder(binaryPath)
            pb.environment().apply {
                put("APP__SERVER__HOST", "127.0.0.1")
                put("APP__SERVER__PORT", PORT.toString())
                put("APP__AUTH__API_PASSWORD", API_PASSWORD)
                put("APP__SERVER__WORKERS", "1")
            }
            pb.redirectErrorStream(true)

            process = pb.start()

            Thread {
                try {
                    process?.inputStream?.bufferedReader()?.forEachLine { line ->
                        Log.d(TAG, "[proxy] $line")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error leyendo logs: ${e.message}")
                }
            }.start()

        } catch (e: Exception) {
            Log.e(TAG, "❌ Error arrancando proxy: ${e.message}", e)
            Toast.makeText(context, "⚠️ Error al iniciar reproductor", Toast.LENGTH_LONG).show()
        }
    }

    fun stop() {
        try {
            process?.destroy()
            process = null
            Log.d(TAG, "🛑 Proxy detenido")
        } catch (e: Exception) {
            Log.e(TAG, "Error deteniendo proxy: ${e.message}")
        }
    }

    fun isRunning(): Boolean = process?.isAlive == true
}