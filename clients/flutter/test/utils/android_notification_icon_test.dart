import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// ledger:RL-android-notification-icon-liza
///
/// Инвариант: монохромные Android-значки (smallIcon уведомлений и тематическая
/// иконка лаунчера) — силуэт Лизы, а не кот FluffyChat. Регрессия: ресурсы
/// `notifications_icon` и `ic_launcher_monochrome` жили котом с импорта клиента;
/// вектор `drawable-anydpi-v24` на API 24+ перекрывал PNG — замена одних PNG
/// ничего бы не изменила. Генератор — `scripts/gen-android-mono-icons.py`.
void main() {
  const res = 'android/app/src/main/res';
  const densities = {
    'mdpi': 1.0,
    'hdpi': 1.5,
    'xhdpi': 2.0,
    'xxhdpi': 3.0,
    'xxxhdpi': 4.0,
  };
  // md5 PNG-кота FluffyChat (mdpi..xxxhdpi) до замены.
  const catMd5 = {
    '9252ec9eecc84fd0cbaa7a84d34b5567',
    '046cac21295ec7a4a1739ac25dd4766a',
    '35ab75af1668548708bfe7b707942542',
    'a09f04b93a794984b140f48265460100',
    '3547c43eb677407258a09a8108412866',
  };

  void expectWhiteSilhouette(String path, int side) {
    final bytes = File(path).readAsBytesSync();
    final image = img.decodePng(bytes)!;
    expect(image.width, side, reason: path);
    expect(image.height, side, reason: path);
    var opaque = 0;
    var transparent = 0;
    for (final p in image) {
      if (p.a == 0) {
        transparent++;
      } else {
        opaque++;
        expect(
          p.r >= 250 && p.g >= 250 && p.b >= 250,
          isTrue,
          reason: '$path: Android берёт только альфу, цвет должен быть белым',
        );
      }
    }
    expect(opaque, greaterThan(0), reason: path);
    expect(transparent, greaterThan(0), reason: path);
  }

  group('RL-android-notification-icon-liza', () {
    test(
      'AC:RL-android-notification-icon-liza/1 нет векторного notifications_icon',
      () {
        final xmls = Directory(res)
            .listSync()
            .whereType<Directory>()
            .map((d) => File('${d.path}/notifications_icon.xml'))
            .where((f) => f.existsSync())
            .map((f) => f.path);
        expect(
          xmls,
          isEmpty,
          reason: 'вектор на API 24+ перекрывает PNG по плотностям',
        );
      },
    );

    test('AC:RL-android-notification-icon-liza/2 '
        'AC:RL-android-notification-icon-liza/3 '
        'notifications_icon.png — белый силуэт 24·k во всех плотностях', () {
      densities.forEach((d, k) {
        expectWhiteSilhouette(
          '$res/drawable-$d/notifications_icon.png',
          (24 * k).round(),
        );
      });
    });

    test('AC:RL-android-notification-icon-liza/4 ни один PNG не кот', () {
      densities.forEach((d, _) {
        final bytes = File(
          '$res/drawable-$d/notifications_icon.png',
        ).readAsBytesSync();
        expect(
          catMd5,
          isNot(contains(md5.convert(bytes).toString())),
          reason: d,
        );
      });
    });

    test('AC:RL-android-notification-icon-liza/5 '
        'манифест задаёт default_notification_icon', () {
      final manifest = File(
        'android/app/src/main/AndroidManifest.xml',
      ).readAsStringSync();
      expect(
        RegExp(
          r'com\.google\.firebase\.messaging\.default_notification_icon"\s*'
          r'android:resource="@drawable/notifications_icon"',
        ).hasMatch(manifest),
        isTrue,
        reason:
            'Sygnal шлёт android.notification без icon — системный баннер '
            'берёт иконку из манифеста',
      );
    });

    test('AC:RL-android-notification-icon-liza/6 '
        'ic_launcher_monochrome — белый силуэт 108·k, без XML-кота', () {
      expect(
        File('$res/drawable/ic_launcher_monochrome.xml').existsSync(),
        isFalse,
      );
      densities.forEach((d, k) {
        expectWhiteSilhouette(
          '$res/drawable-$d/ic_launcher_monochrome.png',
          (108 * k).round(),
        );
      });
    });

    test('AC:RL-android-notification-icon-liza/7 '
        'Dart ссылается на ресурс по прежнему имени', () {
      for (final path in [
        'lib/utils/client_manager.dart',
        'lib/utils/background_push.dart',
      ]) {
        expect(
          File(path).readAsStringSync().contains(
            "AndroidInitializationSettings('notifications_icon')",
          ),
          isTrue,
          reason: path,
        );
      }
    });
  });
}
