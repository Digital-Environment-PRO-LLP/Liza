// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/app_badge.dart';

/// Расшифровка ответа ОС о настройках уведомлений (RL-badge-os-settings-probe).
///
/// Зачем датчик вообще: read-back бейджа на macOS ТАВТОЛОГИЧЕН —
/// `flutter_new_badger` пишет `dockTile.badgeLabel` и всегда рапортует успех
/// (PERMISSION_DENIED там невозможен), а `getBadge` читает ту же in-process
/// переменную. Поэтому «бейдж не появился» неотличимо от «бейдж записан» без
/// вопроса САМОЙ системе.
///
/// ledger:RL-badge-os-settings-probe
void main() {
  group('AppBadge.describeNotificationSettings', () {
    test('AC:RL-badge-os-settings-probe/1 полный ответ расшифрован именами, '
        'а не сырыми кодами (лог читает человек)', () {
      final s = AppBadge.describeNotificationSettings(
        {'authorization': 2, 'alert': 2, 'badge': 2, 'sound': 2},
      );
      expect(s, 'auth=authorized alert=enabled badge=enabled sound=enabled');
    });

    test('AC:RL-badge-os-settings-probe/2 ИМЕННО тот случай, ради которого '
        'датчик писался: бейдж выключен системой при разрешённых уведомлениях',
        () {
      final s = AppBadge.describeNotificationSettings(
        {'authorization': 2, 'alert': 2, 'badge': 1, 'sound': 2},
      );
      expect(s, contains('badge=disabled'));
      expect(s, contains('auth=authorized'));
    });

    test('AC:RL-badge-os-settings-probe/3 отказ в разрешениях виден отдельно '
        'от выключенного бейджа', () {
      final s = AppBadge.describeNotificationSettings(
        {'authorization': 1, 'alert': 1, 'badge': 1, 'sound': 1},
      );
      expect(s, startsWith('auth=denied'));
    });

    test('AC:RL-badge-os-settings-probe/4 битый/неполный ответ натива НЕ роняет '
        'и не врёт: отсутствующее поле помечено, неизвестный код показан', () {
      final s = AppBadge.describeNotificationSettings(
        {'authorization': 99, 'alert': 'nonsense'},
      );
      expect(s, contains('auth=unknown(99)'));
      expect(s, contains('alert=absent'));
      expect(s, contains('badge=absent'));
    });

    test('AC:RL-badge-os-settings-probe/5 PII-safe: строка несёт только статусы, '
        'ни токена, ни mxid, ни хоста', () {
      final s = AppBadge.describeNotificationSettings(
        {'authorization': 2, 'alert': 2, 'badge': 2, 'sound': 2},
      );
      for (final secret in ['@', 'token', 'pushkey', 'liza.ru', '.tech']) {
        expect(s.contains(secret), isFalse, reason: 'утечка "$secret" в лог');
      }
    });

    test('AC:RL-badge-os-settings-probe/6 нативный метод есть в ОБОИХ плагинах '
        '(iOS и macOS) — иначе гейт Platform.isIOS||isMacOS обещает покрытие, '
        'которого нет', () {
      // Ревью 2026-09-09 поймало ровно это: метод был добавлен только в
      // macOS-плагин, а RL и дозор в app_badge.dart заявляли iOS+macOS. На iOS
      // вызов молча падал в `default: FlutterMethodNotImplemented`, то есть
      // диагностика отсутствовала НА ЛЮБОЙ сборке, а не «на старой».
      for (final path in const [
        'macos/Runner/MacApnsPushPlugin.swift',
        'ios/Runner/ApnsPushPlugin.swift',
      ]) {
        final src = File(path).readAsStringSync();
        expect(src, contains('case "getNotificationSettings"'),
            reason: '$path не реализует getNotificationSettings');
        expect(src, contains('getNotificationSettings { s in'),
            reason: '$path не спрашивает UNUserNotificationCenter');
      }
    });
  });
}
