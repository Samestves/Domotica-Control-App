package com.domotica.control_domotica

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Wi‑Fi de verdad para la app:
 *  - busca las redes cercanas (para mostrar la red propia del ESP32 y las demás),
 *  - conecta el teléfono a la red de la placa desde la app (Android pide confirmación una vez),
 *  - y manda las conexiones de la app por esa red aunque no tenga internet.
 */
class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private var permisoPendiente: MethodChannel.Result? = null

    // Red de la placa a la que la app se unió (la suelta al salir o al pedirlo).
    private var redPlaca: Network? = null
    private var ssidPlaca: String? = null
    private var callbackPlaca: ConnectivityManager.NetworkCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "control_domotica/red").setMethodCallHandler { call, result ->
            when (call.method) {
                "usarWifi" -> result.success(usarWifi())
                "permisoWifi" -> pedirPermisoWifi(result)
                "redesWifi" -> buscarRedes(result)
                "conectarRed" -> conectarRed(call.argument<String>("ssid") ?: "", call.argument<String>("clave") ?: "", result)
                "redPlaca" -> result.success(ssidPlaca)
                "soltarRed" -> {
                    soltarRed()
                    result.success(null)
                }
                "ajustesWifi" -> {
                    abrirAjustesWifi()
                    result.success(null)
                }
                "ajustesUbicacion" -> {
                    startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        soltarRed()
        super.onDestroy()
    }

    /**
     * Manda las conexiones de la app por el Wi‑Fi.
     *
     * La red propia del ESP32 no tiene internet, así que Android seguiría usando los datos móviles
     * y no llegaría a 192.168.4.1. Atando la app al Wi‑Fi, la placa siempre se alcanza.
     * Devuelve false si el teléfono no está conectado a ningún Wi‑Fi.
     */
    private fun usarWifi(): Boolean {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return false
        redPlaca?.let {
            cm.bindProcessToNetwork(it)
            return true
        }
        @Suppress("DEPRECATION")
        val wifi = cm.allNetworks.firstOrNull {
            cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
        }
        cm.bindProcessToNetwork(wifi)
        return wifi != null
    }

    // ---------- Permiso para ver las redes cercanas ----------

    // Para leer la lista de redes, Android (10 o más) exige la ubicación precisa, aunque la app no la use.
    private fun permisosWifi(): Array<String> =
        if (Build.VERSION.SDK_INT >= 33)
            arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES, Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)
        else arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION)

    private fun ubicacionEncendida(): Boolean {
        val lm = getSystemService(LocationManager::class.java) ?: return true
        return if (Build.VERSION.SDK_INT >= 28) lm.isLocationEnabled
        else lm.isProviderEnabled(LocationManager.GPS_PROVIDER) || lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    private fun tienePermisoWifi() = permisosWifi().all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    private fun pedirPermisoWifi(result: MethodChannel.Result) {
        if (tienePermisoWifi()) return result.success(true)
        permisoPendiente?.success(false)
        permisoPendiente = result
        requestPermissions(permisosWifi(), PEDIDO_WIFI)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != PEDIDO_WIFI) return
        permisoPendiente?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
        permisoPendiente = null
    }

    // ---------- Buscar redes ----------

    private fun buscarRedes(result: MethodChannel.Result) {
        val wm = applicationContext.getSystemService(WifiManager::class.java)
            ?: return result.error("sin_wifi", "Este teléfono no tiene Wi‑Fi.", null)
        if (!wm.isWifiEnabled) return result.error("wifi_apagado", "Activa el Wi‑Fi del teléfono.", null)
        if (!tienePermisoWifi()) return result.error("sin_permiso", "Falta el permiso de ubicación: Android lo pide para mostrar las redes Wi‑Fi.", null)
        if (!ubicacionEncendida()) return result.error("ubicacion_apagada", "Activa la ubicación del teléfono: Android la exige para mostrar las redes Wi‑Fi cercanas.", null)

        var respondido = false
        lateinit var receptor: BroadcastReceiver
        fun responder() {
            if (respondido) return
            respondido = true
            try {
                unregisterReceiver(receptor)
            } catch (_: Exception) {
            }
            try {
                result.success(resultados(wm))
            } catch (_: SecurityException) {
                result.error("sin_permiso", "Android no dejó leer las redes. Revisa el permiso de ubicación de la app.", null)
            }
        }
        receptor = object : BroadcastReceiver() {
            override fun onReceive(c: Context?, i: Intent?) = responder()
        }
        val filtro = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(receptor, filtro, Context.RECEIVER_EXPORTED) else registerReceiver(receptor, filtro)

        // Android limita las búsquedas seguidas: si no deja buscar, se usan las últimas redes que vio.
        @Suppress("DEPRECATION")
        if (!wm.startScan()) responder() else handler.postDelayed({ responder() }, 8000)
    }

    private fun resultados(wm: WifiManager): List<Map<String, Any>> {
        return wm.scanResults.mapNotNull { r ->
            val ssid = if (Build.VERSION.SDK_INT >= 33) r.wifiSsid?.toString()?.removeSurrounding("\"") else @Suppress("DEPRECATION") r.SSID
            if (ssid.isNullOrBlank()) return@mapNotNull null
            val cap = r.capabilities ?: ""
            mapOf(
                "ssid" to ssid,
                "nivel" to r.level,
                "segura" to (cap.contains("WPA") || cap.contains("WEP") || cap.contains("SAE")),
                "ghz" to (if (r.frequency > 4900) 5 else 2),
            )
        }
            .groupBy { it["ssid"] }
            .map { (_, iguales) -> iguales.maxByOrNull { it["nivel"] as Int }!! }
            .sortedByDescending { it["nivel"] as Int }
    }

    // ---------- Unirse a la red de la placa ----------

    private fun conectarRed(ssid: String, clave: String, result: MethodChannel.Result) {
        if (ssid.isEmpty()) return result.error("sin_red", "Falta el nombre de la red.", null)
        if (Build.VERSION.SDK_INT < 29) {
            abrirAjustesWifi()
            return result.error("android_viejo", "En este Android hay que conectarse desde Ajustes → Wi‑Fi.", null)
        }
        if (ssidPlaca == ssid && redPlaca != null) return result.success(true)
        soltarRed()
        val cm = getSystemService(ConnectivityManager::class.java) ?: return result.error("sin_wifi", "No se pudo usar el Wi‑Fi.", null)

        val spec = WifiNetworkSpecifier.Builder().setSsid(ssid).apply { if (clave.isNotEmpty()) setWpa2Passphrase(clave) }.build()
        val pedido = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(spec)
            .build()

        var respondido = false
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                redPlaca = network
                ssidPlaca = ssid
                cm.bindProcessToNetwork(network)
                handler.post {
                    if (!respondido) {
                        respondido = true
                        result.success(true)
                    }
                }
            }

            override fun onUnavailable() {
                callbackPlaca = null
                handler.post {
                    if (!respondido) {
                        respondido = true
                        result.error("no_conecto", "No se pudo unir a «$ssid». Revisa la contraseña y que la placa esté encendida.", null)
                    }
                }
            }

            override fun onLost(network: Network) {
                if (network != redPlaca) return
                redPlaca = null
                ssidPlaca = null
                cm.bindProcessToNetwork(null)
            }
        }
        callbackPlaca = cb
        cm.requestNetwork(pedido, cb, 30000)
    }

    private fun soltarRed() {
        val cm = getSystemService(ConnectivityManager::class.java) ?: return
        callbackPlaca?.let {
            try {
                cm.unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
        }
        callbackPlaca = null
        redPlaca = null
        ssidPlaca = null
        cm.bindProcessToNetwork(null)
    }

    private fun abrirAjustesWifi() {
        val accion = if (Build.VERSION.SDK_INT >= 29) Settings.Panel.ACTION_WIFI else Settings.ACTION_WIFI_SETTINGS
        startActivity(Intent(accion))
    }

    companion object {
        private const val PEDIDO_WIFI = 7301
    }
}
