# Actualizar la app desde la app

Desde la **Alpha 0.9.1**, la app se actualiza sola desde GitHub, gratis:

- **Al abrirla** (con internet), revisa si hay una versión nueva. Si la hay, aparece un aviso arriba en el inicio.
- **En Ajustes → Buscar actualización** se puede revisar a mano.
- Al tocar **Descargar e instalar**, baja el APK de este teléfono (unos 18 MB) y abre el instalador de Android.
  Hay que tocar **Actualizar** (o **Instalar**) en la ventana de Android: ninguna app normal puede saltarse ese paso.
- **La primera vez**, Android pide permitir que Control Domótica instale actualizaciones («Permitir de esta fuente»).
  Se activa una sola vez y la instalación sigue sola al volver.
- Los dispositivos guardados y las claves **se conservan** al actualizar.

Si el teléfono está unido a la red Wi‑Fi de una placa (Casa Domotica o Carrito 4x4), no tiene internet: la app lo
avisa y hay que salir de esa red para actualizar.

## Una sola vez: preparar GitHub

1. **Crear el repositorio** en https://github.com/new con el nombre `Domotica-Control-App`, **público**, y sin marcar
   «Add a README» (el proyecto ya tiene uno). Si eligen otro nombre, cámbienlo en `lib/core/updater.dart` (`repo`).
2. **Subir el proyecto** (desde la carpeta del proyecto, después de hacer el commit):

   ```powershell
   git remote add origin https://github.com/Samestves/Domotica-Control-App.git
   git push -u origin master mvp-app-control
   ```

   La primera vez Windows abre el navegador para iniciar sesión en GitHub.
3. **Recomendado: crear la llave propia antes de la primera versión publicada** (ver [FIRMA.md](FIRMA.md)).
   Todas las actualizaciones tienen que estar firmadas con la misma llave que la app instalada. Si la llave se cambia
   después, la actualización falla con «App no instalada» y hay que desinstalar. Hacerlo ahora, una vez, evita eso.
4. **Instalar la 0.9.1 a mano** en cada teléfono por última vez (si cambiaron la llave, desinstalando antes la vieja).
   Desde ahí, las siguientes llegan por la app.

## Cada versión nueva

1. Suban la versión en **los dos lugares**, por ejemplo a `0.9.2+22`:
   - `pubspec.yaml` → `version: 0.9.2+22`
   - `lib/version.dart` → `appVersion = 'Alpha 0.9.2'` y `appBuild = 22`

   El número de después del `+` **siempre tiene que subir**: Android no instala una versión con un número menor.
2. En PowerShell, desde la carpeta del proyecto:

   ```powershell
   .\tool\publicar.ps1
   ```

   Compila los dos APK (64 y 32 bits), los deja en `entregas\` y dice paso a paso qué poner en GitHub:
   la etiqueta (por ejemplo `v0.9.2+22`), el título, la descripción y los dos APK. Con la herramienta de GitHub
   instalada (`gh`), `.\tool\publicar.ps1 -Notas "qué trae" -Publicar` lo hace todo solo.
3. En GitHub, **Publish release** (no «pre-release» ni borrador: la app solo ve la última versión publicada).

## Cuidados

- **No cambien los nombres de los APK**: la app elige el de cada teléfono porque el nombre dice `arm64` o `armeabi`.
- **Compilen siempre en la misma PC**, o con la misma llave propia: si no, la actualización no se instala.
- La etiqueta tiene que verse como `v0.9.2+22`. La app solo ofrece una versión si es más nueva que la instalada.
- GitHub deja preguntar unas 60 veces por hora desde una misma red: de sobra para el equipo.

## Qué queda público

Con el repositorio público, cualquiera puede ver el código y descargar la app. Dentro del código están los
**nombres completos del equipo** (en los créditos escondidos) y, en cada commit, el **nombre y correo** con que está
configurado git en esta PC. Si prefieren que el correo no se vea, en GitHub → Settings → Emails activen
«Keep my email addresses private» y usen el correo `@users.noreply.github.com` que GitHub les da:

```powershell
git config user.email "ID+Samestves@users.noreply.github.com"
```

(Ese cambio vale para los commits nuevos; los ya hechos conservan el correo con que se hicieron.)
