package com.domotica.control_domotica

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobScheduler
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.concurrent.TimeUnit

/**
 * Notificaciones locales de la app: sin servidor ni cuentas.
 *  - [programar] deja a Android revisando cada 12 horas si hay versiones nuevas (ver [RevisarVersiones]).
 *  - [mostrar] avisa algo ahora (por ejemplo, cómo salió la actualización de una placa).
 */
object Avisos {
    /** Versiones nuevas de la app o de las placas. */
    const val CANAL_VERSIONES = "versiones"

    /** Cómo salió la actualización de una placa. */
    const val CANAL_PLACAS = "placas"

    private const val TRABAJO = 7401

    fun crearCanales(ctx: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        nm.createNotificationChannel(
            NotificationChannel(CANAL_VERSIONES, "Versiones nuevas", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Cuando hay una versión nueva de la app o del programa de tus placas"
            },
        )
        nm.createNotificationChannel(
            NotificationChannel(CANAL_PLACAS, "Actualización de placas", NotificationManager.IMPORTANCE_DEFAULT).apply {
                description = "Cómo salió la actualización de una placa mientras la app estaba en segundo plano"
            },
        )
    }

    fun puedeAvisar(ctx: Context) = NotificationManagerCompat.from(ctx).areNotificationsEnabled()

    /** Muestra un aviso. Tocarlo abre la app. Sin permiso no hace nada: avisar es un extra. */
    fun mostrar(ctx: Context, id: Int, canal: String, titulo: String, texto: String) {
        if (!puedeAvisar(ctx)) return
        crearCanales(ctx)
        val abrir = PendingIntent.getActivity(
            ctx,
            0,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val aviso = NotificationCompat.Builder(ctx, canal)
            .setSmallIcon(R.drawable.ic_aviso)
            .setContentTitle(titulo)
            .setContentText(texto)
            .setStyle(NotificationCompat.BigTextStyle().bigText(texto))
            .setContentIntent(abrir)
            .setAutoCancel(true)
            .build()
        try {
            NotificationManagerCompat.from(ctx).notify(id, aviso)
        } catch (_: SecurityException) {
            // el permiso se quitó justo ahora
        }
    }

    /**
     * Revisión cada 12 horas, solo con internet, con el programador de tareas de Android (JobScheduler).
     * Si ya está programada no se toca: así la app puede pedirla cada vez que se abre sin reiniciar la espera.
     * Sigue programada aunque se reinicie el teléfono.
     */
    fun programar(ctx: Context, activos: Boolean) {
        val js = ctx.getSystemService(JobScheduler::class.java) ?: return
        if (!activos) {
            js.cancel(TRABAJO)
            return
        }
        if (js.getPendingJob(TRABAJO) != null) return
        val tarea = JobInfo.Builder(TRABAJO, ComponentName(ctx, RevisarVersiones::class.java))
            .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
            .setPeriodic(TimeUnit.HOURS.toMillis(12))
            .setPersisted(true)
            .build()
        js.schedule(tarea)
    }
}
