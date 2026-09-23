// Страж активности против App Nap на macOS (заявка №31, третий круг 2026-09-17).
//
// Механизм нативный (`ProcessInfo.beginActivity`), Dart-поверхности у него нет —
// host-тест может защитить только САМ вызов и выбор опции от молчаливой правки.
// Это осознанно слабый, статический страж (ratchet), а не поведенческий: что App
// Nap реально снят, проверяется device-прогоном (AC-2..AC-4 в реестре), считая
// провалы /sync по nginx на СЕРВЕРЕ (клиентский heartbeat сам снимает App Nap и
// потому в измерении запрещён).
//
// Почему опция ровно одна:
//   .userInitiatedAllowingIdleSystemSleep — снимает App Nap, НЕ мешает Маку
//     засыпать по бездействию;
//   .background — App Nap НЕ снимает (наоборот, подтверждает фоновость);
//   .userInitiated / .idleSystemSleepDisabled / .idleDisplaySleepDisabled —
//     держали бы систему или дисплей от сна («ноутбук не засыпает»).
//
// ledger:RL-macos-app-nap-sync-alive

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('macos/Runner/AppDelegate.swift').readAsStringSync();

  // AC:RL-macos-app-nap-sync-alive/1
  test('активность против App Nap берётся на старте и снимается на выходе '
      'ровно с одной безопасной опцией', () {
    expect(
      source.contains('beginActivity('),
      isTrue,
      reason: 'ProcessInfo.beginActivity снят — при перекрытом окне /sync снова '
          'замрёт на минуты, и уведомление будет зависеть только от APNs',
    );
    expect(
      source.contains('.userInitiatedAllowingIdleSystemSleep'),
      isTrue,
      reason: 'единственная допустимая опция: снимает App Nap и не держит Мак '
          'от сна',
    );
    expect(
      source.contains('endActivity('),
      isTrue,
      reason: 'активность обязана сниматься на applicationWillTerminate',
    );

    for (final forbidden in const [
      '.idleSystemSleepDisabled',
      '.idleDisplaySleepDisabled',
      '.latencyCritical',
    ]) {
      expect(
        source.contains(forbidden),
        isFalse,
        reason: '$forbidden держит систему/дисплей от сна — это превращает '
            'страховку уведомлений в wake-lock («ноутбук не засыпает»)',
      );
    }

    // `.background` App Nap не снимает; ловим его именно в вызове активности,
    // чтобы не цепляться за слово в комментариях и прочем коде.
    final activityCall = RegExp(r'beginActivity\([\s\S]{0,200}?\)')
        .firstMatch(source)
        ?.group(0);
    expect(activityCall, isNotNull);
    expect(
      activityCall!.contains('.background'),
      isFalse,
      reason: '.background не снимает App Nap — процесс продолжит замирать',
    );
  });
}
