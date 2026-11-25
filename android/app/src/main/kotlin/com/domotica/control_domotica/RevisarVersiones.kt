package com.domotica.control_domotica

import android.content.Context
import androidx.core.content.pm.PackageInfoCompat
import androidx.work.Worker
import androidx.work.WorkerParameters
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * La revisión que Android corre cada 12 horas, aunque la app esté cerrada (ver [Avisos.programar]).
 *
 * Mira lo mismo que la app al abrirse, con las mismas reglas (lib/core/updater.dart y lib/core/firmware.dart):
 *  - la última versión de la app publicada en GitHub;
 *  - la versión publicada del programa de cada placa (la lista de la página del instalador), comparada con la
 *    que dijo cada placa guardada la última vez que se conectó.
 * Avisa una sola vez por versión. Lee lo que guarda la app (shared_preferences) sin cambiarlo.
 */
class RevisarVersiones(context: Context, params: WorkerParameters) : Worker(context, params) {
    private val app = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    private val avisados = context.getSharedPreferences("avisos_enviados", Context.MODE_PRIVATE)

    override fun doWork(): Result {
        if (!app.getBoolean("flutter.avisos_versiones", true)) return Result.success()
        return try {
            revisarApp()
            revisarPlacas()
            Result.success()
        } catch (_: IOException) {
            Result.retry() // sin internet o GitHub no contestó: Android vuelve a probar más tarde
        } catch (_: JSONException) {
            Result.success() // respuesta rara: se prueba en la próxima vuelta
        }
    }

    private fun revisarApp() {
        val ultima = JSONObject(leer("https://api.github.com/repos/$REPO/releases/latest"))
        val tag = ultima.optString("tag_name")
        if (!appMasNueva(tag) || yaAvisado("app:$tag")) return
        val titulo = ultima.optString("name").ifBlank { "Versión ${tag.removePrefix("v")}" }
        Avisos.mostrar(applicationContext, ID_APP, Avisos.CANAL_VERSIONES, "Versión nueva de la app", "$titulo está lista. Toca para actualizar.")
        marcar("app:$tag")
    }

    private fun revisarPlacas() {
        val guardadas = app.getString("flutter.devices_v1", null) ?: return
        val publicadas = mutableMapOf<String, String>() // placa → versión
        val boards = JSONObject(leer(CATALOGO)).optJSONArray("boards") ?: return
        for (i in 0 until boards.length()) {
            val b = boards.optJSONObject(i) ?: continue
            publicadas[b.optString("id")] = b.optString("version")
        }
        val lista = JSONArray(guardadas)
        for (i in 0 until lista.length()) {
            val d = lista.optJSONObject(i) ?: continue
            val tiene = d.optString("firmware").ifBlank { null } ?: continue // sin versión: no se actualiza por Wi-Fi
            if (d.optString("transport") == "demo") continue
            val nueva = publicadas[d.optString("profile")] ?: continue
            val clave = "placa:${d.optString("id")}:$nueva"
            if (!placaMasNueva(nueva, tiene) || yaAvisado(clave)) continue
            val nombre = d.optString("name")
            Avisos.mostrar(
                applicationContext, ID_PLACA + i, Avisos.CANAL_VERSIONES,
                "Versión nueva para «$nombre»", "$nueva está lista (tiene $tiene). Toca para instalarla.",
            )
            marcar(clave)
        }
    }

    /** Igual que Updater.isNewer: versión mayor, o la misma con un número de compilación mayor. */
    private fun appMasNueva(tag: String): Boolean {
        val m = Regex("""^[vV]?(\d+)\.(\d+)(?:\.(\d+))?(?:\+(\d+))?$""").find(tag.trim()) ?: return false
        val publicada = listOf(m.groupValues[1].toInt(), m.groupValues[2].toInt(), m.groupValues[3].ifEmpty { "0" }.toInt())
        val info = applicationContext.packageManager.getPackageInfo(applicationContext.packageName, 0)
        val instalada = (info.versionName ?: "").split('.').map { it.toIntOrNull() ?: 0 }.plus(listOf(0, 0, 0)).take(3)
        for (i in 0..2) if (publicada[i] != instalada[i]) return publicada[i] > instalada[i]
        // Con APK por procesador, Android suma 1000 × procesador al número: la compilación son las 3 últimas cifras.
        val compilacion = (PackageInfoCompat.getLongVersionCode(info) % 1000).toInt()
        return m.groupValues[4].isNotEmpty() && m.groupValues[4].toInt() > compilacion
    }

    /** Igual que Firmware.isNewer: misma placa (`casa-…` con `casa-…`) y número mayor. */
    private fun placaMasNueva(publicada: String, tiene: String): Boolean {
        val patron = Regex("""^(.*?)-?(\d+(?:\.\d+)*)$""")
        val a = patron.find(publicada.trim()) ?: return false
        val b = patron.find(tiene.trim()) ?: return false
        if (a.groupValues[1] != b.groupValues[1]) return false
        val x = a.groupValues[2].split('.').map { it.toInt() }
        val y = b.groupValues[2].split('.').map { it.toInt() }
        for (i in 0 until maxOf(x.size, y.size)) {
            val p = x.getOrElse(i) { 0 }
            val q = y.getOrElse(i) { 0 }
            if (p != q) return p > q
        }
        return false
    }

    private fun yaAvisado(clave: String) = avisados.getBoolean(clave, false)

    private fun marcar(clave: String) = avisados.edit().putBoolean(clave, true).apply()

    private fun leer(direccion: String): String {
        val c = URL(direccion).openConnection() as HttpURLConnection
        try {
            c.connectTimeout = 10000
            c.readTimeout = 15000
            c.setRequestProperty("User-Agent", "control-domotica-app")
            c.setRequestProperty("Accept", "application/vnd.github+json")
            if (c.responseCode != 200) throw IOException("respondió ${c.responseCode}")
            return c.inputStream.bufferedReader().use { it.readText() }
        } finally {
            c.disconnect()
        }
    }

    companion object {
        // Los mismos de la app: lib/core/updater.dart (repo) y lib/core/firmware.dart (catálogo).
        private const val REPO = "Samestves/Domotica-Control-App"
        private const val CATALOGO = "https://samestves.github.io/Domotica-Control-App/placas.json"
        private const val ID_APP = 1
        private const val ID_PLACA = 100
    }
}
