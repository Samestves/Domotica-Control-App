package com.domotica.control_domotica

import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "control_domotica/red").setMethodCallHandler { call, result ->
            when (call.method) {
                "usarWifi" -> result.success(usarWifi())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Manda las conexiones de la app por el Wi‑Fi.
     *
     * La red propia del ESP32 no tiene internet, así que Android sigue usando los datos móviles
     * y no llegaría a 192.168.4.1. Atando la app al Wi‑Fi, la placa siempre se alcanza.
     * Devuelve false si el teléfono no está conectado a ningún Wi‑Fi.
     */
    private fun usarWifi(): Boolean {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return false
        @Suppress("DEPRECATION")
        val wifi = cm.allNetworks.firstOrNull {
            cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
        cm.bindProcessToNetwork(wifi)
        return wifi != null
    }
}
