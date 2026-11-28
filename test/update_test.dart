import 'package:control_domotica/core/updater.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Versiones', () {
    test('lee la etiqueta de una Release', () {
      final t = Updater.parseTag('v0.9.1+21')!;
      expect(t.version, [0, 9, 1]);
      expect(t.build, 21);
      expect(Updater.parseTag('1.0')!.version, [1, 0, 0]);
      expect(Updater.parseTag('1.0')!.build, isNull);
      expect(Updater.parseTag('ultima'), isNull);
    });

    test('solo avisa si la publicada es más nueva que la instalada', () {
      bool newer(String tag) => Updater.isNewer(tag, current: 'Alpha 0.9.0', currentBuild: 20);
      expect(newer('v0.9.1+21'), isTrue);
      expect(newer('v1.0.0'), isTrue);
      expect(newer('v0.9.0+21'), isTrue, reason: 'misma versión, compilación más nueva');
      expect(newer('v0.9.0+20'), isFalse, reason: 'es la misma');
      expect(newer('v0.9.0'), isFalse);
      expect(newer('v0.8.9+30'), isFalse, reason: 'una versión vieja nunca se ofrece');
      expect(newer('basura'), isFalse);
      expect(Updater.isNewer('v0.9.10+30', current: 'Alpha 0.9.9', currentBuild: 29), isTrue, reason: '10 es más que 9: números, no letras');
    });
  });

  group('APK para este teléfono', () {
    final assets = [
      {'name': 'Control-Domotica-Alpha-0.9.1-arm64.apk', 'size': 18000000, 'browser_download_url': 'https://x/arm64.apk'},
      {'name': 'Control-Domotica-Alpha-0.9.1-armeabi.apk', 'size': 17000000, 'browser_download_url': 'https://x/armeabi.apk'},
      {'name': 'notas.txt', 'size': 10, 'browser_download_url': 'https://x/notas.txt'},
    ];

    test('elige el de su procesador', () {
      expect(Updater.pickApk(assets, 'arm64-v8a')!['name'], contains('arm64'));
      expect(Updater.pickApk(assets, 'armeabi-v7a')!['name'], contains('armeabi'));
    });

    test('nunca ofrece el de otro procesador: si no hay uno que sirva, el universal o ninguno', () {
      expect(Updater.pickApk(assets, 'x86_64'), isNull, reason: 'no se instalaría');
      final withUniversal = [...assets, {'name': 'Control-Domotica-Alpha-0.9.1.apk', 'size': 50000000, 'browser_download_url': 'https://x/u.apk'}];
      expect(Updater.pickApk(withUniversal, 'x86_64')!['name'], 'Control-Domotica-Alpha-0.9.1.apk');
    });

    test('lee la respuesta de GitHub', () {
      final r = Updater.parseRelease({
        'tag_name': 'v0.9.1+21',
        'name': 'Alpha 0.9.1',
        'body': '- Actualizar desde la app',
        'assets': assets,
      }, 'arm64-v8a')!;
      expect(r.title, 'Alpha 0.9.1');
      expect(r.notes, '- Actualizar desde la app');
      expect(r.apkUrl, 'https://x/arm64.apk');
      expect(r.sizeText, '18.0 MB');

      final untitled = Updater.parseRelease({'tag_name': 'v0.9.2', 'assets': assets}, 'arm64-v8a')!;
      expect(untitled.title, 'Versión 0.9.2');
      expect(Updater.parseRelease({'tag_name': 'borrador', 'assets': assets}, 'arm64-v8a'), isNull);
    });
  });
}
