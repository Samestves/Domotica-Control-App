package com.domotica.control_domotica

import android.Manifest
import android.content.ActivityNotFoundException
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
import android.net.Uri
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Wi‑Fi de verdad para la app:
 *  - busca las redes cercanas (para mostrar la red propia del ESP32 y las demás),
 *  - conecta el teléfono a la red de la placa desde la app (Android pide confirmación una vez),
 *  - y manda las conexiones de la app por esa red aunque no tenga internet.
 */
class MainActivity : FlutterActivity() {
    private val handler = Handler(Looper.getMainLooper())
    private var permisoPendiente: MethodChannel.Result? = null

    // true si Android ya no muestra la pregunta del permiso («No volver a preguntar»): hay que ir a Ajustes.
    private var permisoBloqueado = false

    // Búsqueda de redes en curso (para limpiarla si la app se cierra a mitad).
    private var receptorBusqueda: BroadcastReceiver? = null

    // Respuesta pendiente del permiso para avisar (Android 13 o más nuevo).
    private var avisosPendiente: MethodChannel.Result? = null

    // Respuesta pendiente de «conectarRed»: siempre se contesta una vez, aunque se pida otra red o se suelte.
    private var resultadoRed: MethodChannel.Result? = null

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
                    abrir(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS), Intent(Settings.ACTION_SETTINGS))
                    result.success(null)
                }
                "ajustesApp" -> {
                    abrir(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null)),
                        Intent(Settings.ACTION_SETTINGS),
                    )
                    result.success(null)
                }
                "permisoBloqueado" -> result.success(permisoBloqueado)
                else -> result.notImplemented()
            }
        }
        // Actualizaciones de la app (ver lib/core/updater.dart): la descarga la hace Dart; aquí solo se instala.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "control_domotica/app").setMethodCallHandler { call, result ->
            when (call.method) {
                "abi" -> result.success(Build.SUPPORTED_ABIS.firstOrNull())
                "carpetaActualizaciones" -> {
                    val carpeta = File(cacheDir, "actualizaciones")
                    carpeta.mkdirs()
                    result.success(carpeta.absolutePath)
                }
                "puedeInstalar" -> result.success(if (Build.VERSION.SDK_INT >= 26) packageManager.canRequestPackageInstalls() else true)
                "permisoInstalar" -> {
                    if (Build.VERSION.SDK_INT >= 26) {
                        abrir(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName")), Intent(Settings.ACTION_SECURITY_SETTINGS))
                    } else {
                        abrir(Intent(Settings.ACTION_SECURITY_SETTINGS))
                    }
                    result.success(null)
                }
                "instalarApk" -> instalarApk(call.argument<String>("ruta") ?: "", result)
                else -> result.notImplemented()
            }
        }
        // Notificaciones locales (ver Avisos.kt y lib/core/avisos.dart).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "control_domotica/avisos").setMethodCallHandler { call, result ->
            when (call.method) {
                "programar" -> {
                    Avisos.programar(this, call.argument<Boolean>("activos") ?: true)
                    result.success(null)
                }
                "pedirPermiso" -> pedirPermisoAvisos(result)
                "mostrar" -> {
                    Avisos.mostrar(this, ID_RESULTADO, Avisos.CANAL_PLACAS, call.argument<String>("titulo") ?: "", call.argument<String>("texto") ?: "")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Android 13 o más nuevo pregunta si la app puede avisar. En los anteriores el permiso viene dado.
    private fun pedirPermisoAvisos(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return result.success(Avisos.puedeAvisar(this))
        }
        avisosPendiente?.success(false)
        avisosPendiente = result
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PEDIDO_AVISOS)
    }

    /// Abre el instalador de Android con el APK descargado. Android pide confirmar y reemplaza la app
    /// (los dispositivos guardados se conservan, porque la versión nueva está firmada con la misma llave).
    private fun instalarApk(ruta: String, result: MethodChannel.Result) {
        val archivo = File(ruta)
        if (!archivo.exists()) return result.error("sin_archivo", "No se encontró la descarga. Descárgala otra vez.", null)
        val uri = try {
            FileProvider.getUriForFile(this, "$packageName.archivos", archivo)
        } catch (_: IllegalArgumentException) {
            return result.error("sin_archivo", "La descarga quedó en un lugar que Android no deja abrir.", null)
        }
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.error("sin_instalador", "Este teléfono no tiene el instalador de Android disponible.", null)
        }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        receptorBusqueda?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        receptorBusqueda = null
        resultadoRed = null // la app se cierra: ya no hay a quién contestar
        avisosPendiente = null
        soltarRed()
        super.onDestroy()
    }

    /// Abre la primera pantalla de Ajustes que exista en este teléfono (algunas marcas quitan algunas).
    private fun abrir(vararg intents: Intent) {
        for (i in intents) {
            try {
                startActivity(i)
                return
            } catch (_: ActivityNotFoundException) {
            }
        }
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
        if (tienePermisoWifi()) {
            permisoBloqueado = false
            return result.success(true)
        }
        permisoPendiente?.success(false)
        permisoPendiente = result
        requestPermissions(permisosWifi(), PEDIDO_WIFI)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == PEDIDO_AVISOS) {
            avisosPendiente?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            avisosPendiente = null
            return
        }
        if (requestCode != PEDIDO_WIFI) return
        val ok = grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        // Negado y sin «explicación» disponible: el usuario marcó «No volver a preguntar» (o lo negó dos veces).
        permisoBloqueado = !ok && grantResults.isNotEmpty() && permissions.indices.any { i ->
            grantResults[i] != PackageManager.PERMISSION_GRANTED && !shouldShowRequestPermissionRationale(permissions[i])
        }
        permisoPendiente?.success(ok)
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
        lateinit var espera: Runnable
        fun responder() {
            if (respondido) return
            respondido = true
            handler.removeCallbacks(espera)
            receptorBusqueda = null
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
        espera = Runnable { responder() }
        val filtro = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(receptor, filtro, Context.RECEIVER_EXPORTED) else registerReceiver(receptor, filtro)
        receptorBusqueda = receptor

        // Android limita las búsquedas seguidas: si no deja buscar, se usan las últimas redes que vio.
        @Suppress("DEPRECATION")
        if (!wm.startScan()) responder() else handler.postDelayed(espera, 8000)
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
        // Antes de soltar la red actual: una contraseña que Android no acepta no debe dejarte sin red.
        if (clave.isNotEmpty() && (clave.length !in 8..63 || clave.any { it.code !in 32..126 })) {
            return result.error("clave_invalida", "La contraseña de una red Wi‑Fi tiene de 8 a 63 letras o números, sin tildes ni ñ.", null)
        }
        if (ssidPlaca == ssid && redPlaca != null) return result.success(true)
        soltarRed() // contesta «reemplazada» a un pedido anterior que siguiera esperando
        val cm = getSystemService(ConnectivityManager::class.java) ?: return result.error("sin_wifi", "No se pudo usar el Wi‑Fi.", null)

        val spec = WifiNetworkSpecifier.Builder().setSsid(ssid).apply { if (clave.isNotEmpty()) setWpa2Passphrase(clave) }.build()
        val pedido = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(spec)
            .build()

        // Los avisos llegan en el hilo principal (handler): sin carreras con las variables de abajo.
        resultadoRed = result
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (callbackPlaca !== this) return // es de un pedido viejo que ya se soltó
                redPlaca = network
                ssidPlaca = ssid
                cm.bindProcessToNetwork(network)
                resultadoRed?.success(true)
                resultadoRed = null
            }

            override fun onUnavailable() {
                if (callbackPlaca !== this) return
                callbackPlaca = null
                resultadoRed?.error("no_conecto", "No se pudo unir a «$ssid». Revisa la contraseña y que la placa esté encendida.", null)
                resultadoRed = null
            }

            override fun onLost(network: Network) {
                if (callbackPlaca !== this || network != redPlaca) return
                redPlaca = null
                ssidPlaca = null
                cm.bindProcessToNetwork(null)
            }
        }
        callbackPlaca = cb
        cm.requestNetwork(pedido, cb, handler, 30000)
    }

    private fun soltarRed() {
        resultadoRed?.error("reemplazada", "Se canceló la unión a la red de la placa.", null)
        resultadoRed = null
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
        if (Build.VERSION.SDK_INT >= 29) abrir(Intent(Settings.Panel.ACTION_WIFI), Intent(Settings.ACTION_WIFI_SETTINGS))
        else abrir(Intent(Settings.ACTION_WIFI_SETTINGS))
    }

    companion object {
        private const val PEDIDO_WIFI = 7301
        private const val PEDIDO_AVISOS = 7302
        private const val ID_RESULTADO = 2
    }
}
