# Firmar la app con una llave propia

Hoy la app se firma con la **llave de pruebas** de esta PC. Funciona para instalarla a mano, pero tiene dos problemas:

- **Google Play no la acepta.**
- **Cada PC tiene su propia llave de pruebas.** Un APK compilado en otra computadora no se instala encima del actual:
  hay que desinstalar, y se pierden los dispositivos guardados y sus claves.

La app ya está preparada para usar una llave propia: si existe `android/key.properties`, la versión final se firma con esa
llave. Si no existe, sigue como hasta ahora. Crearla es un paso que hace la persona dueña del proyecto, una sola vez.

## 1. Crear la llave

En PowerShell, desde la carpeta del proyecto (`keytool` viene con Android Studio, en `C:\Program Files\Android\Android Studio\jbr\bin`):

```powershell
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkey -v -keystore "$env:USERPROFILE\control-domotica.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias control-domotica
```

Pide una contraseña y unos datos (nombre, ciudad…). **Guarden el archivo `.jks` y la contraseña en un lugar seguro:**
si se pierden, ninguna versión nueva se podrá instalar encima de las anteriores firmadas con ella.

## 2. Decirle a la app dónde está

Crea el archivo `android/key.properties` (git lo ignora: nunca se sube) con este contenido, cambiando las contraseñas:

```properties
storePassword=la-contraseña-que-elegiste
keyPassword=la-contraseña-que-elegiste
keyAlias=control-domotica
storeFile=C:/Users/TU_USUARIO/control-domotica.jks
```

## 3. Compilar

```powershell
flutter build apk --release --split-per-abi --target-platform android-arm64
```

El APK queda firmado con la llave propia.

## Ojo: el primer cambio de llave

Un teléfono que tiene la app firmada con la llave de pruebas **no acepta** la versión firmada con la llave nueva.
La primera vez hay que **desinstalar** la app y volver a instalarla. Se pierden los dispositivos guardados: antes,
anoten cómo estaba cada uno (nombre, Bluetooth o Wi‑Fi, pines cambiados). Las claves no se pierden: están en las placas;
basta con escribirlas otra vez.
