// Страж «возврат из шторки не рвёт загрузки в полёте»
// (RL-http-refresh-only-after-suspension, AC-1…AC-4).
//
// Инцидент 2026-09-15 (GlitchTip #2026): `_refreshHttpClients` срабатывал на
// КАЖДЫЙ `resumed`, в том числе после одного `inactive`, и force-закрывал
// HTTP-клиент. Голосовое 733 КБ на медленной сети оборвалось дважды — ровно в
// моменты возврата из шторки — и ушло ложным `[audio-fail] kind=network`.
//
// Проверяемая величина — решение гейта, по которому `MatrixState` пересоздаёт
// клиенты. Последовательности состояний — те, что реально генерирует
// `ServicesBinding._generateStateTransitions` (через промежуточные состояния).
//
// Red-proof: гейт, отвечающий `state == resumed` (прежнее поведение), краснеет
// на AC-1 и AC-3.

import 'dart:ui' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/network_recovery_trigger.dart';

// Страж реестра регрессии: ledger:RL-http-refresh-only-after-suspension
void main() {
  const shade = [AppLifecycleState.inactive, AppLifecycleState.resumed];
  const background = [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];

  List<bool> feed(ResumeHttpRefreshGate gate, List<AppLifecycleState> path) =>
      [for (final s in path) gate.onStateChange(s)];

  test(
    'AC:RL-http-refresh-only-after-suspension/1 — возврат из шторки (inactive) '
    'не пересоздаёт клиенты, в том числе два раза подряд, как в инциденте',
    () {
      final gate = ResumeHttpRefreshGate(AppLifecycleState.resumed);
      expect(feed(gate, [...shade, ...shade]), everyElement(isFalse));
    },
  );

  test(
    'AC:RL-http-refresh-only-after-suspension/2 — возврат из настоящего фона '
    'пересоздаёт клиенты ровно один раз, следующая шторка — уже нет',
    () {
      final gate = ResumeHttpRefreshGate(AppLifecycleState.resumed);
      expect(feed(gate, background), [false, false, false, false, false, true]);
      expect(feed(gate, shade), [false, false]);
      expect(feed(gate, background).last, isTrue);
    },
  );

  test(
    'AC:RL-http-refresh-only-after-suspension/3 — старт в foreground: первый '
    'resumed не рвёт стартовые запросы',
    () {
      for (final initial in [
        AppLifecycleState.resumed,
        AppLifecycleState.inactive,
      ]) {
        final gate = ResumeHttpRefreshGate(initial);
        expect(gate.onStateChange(AppLifecycleState.resumed), isFalse,
            reason: 'initial=$initial');
      }
    },
  );

  test(
    'AC:RL-http-refresh-only-after-suspension/4 — старт в фоне (пуш) или с '
    'неизвестным состоянием: первый resumed пересоздаёт клиенты',
    () {
      for (final initial in [
        null,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
      ]) {
        final gate = ResumeHttpRefreshGate(initial);
        expect(gate.onStateChange(AppLifecycleState.resumed), isTrue,
            reason: 'initial=$initial');
      }
      final detachedMidway = ResumeHttpRefreshGate(AppLifecycleState.resumed)
        ..onStateChange(AppLifecycleState.detached);
      expect(detachedMidway.onStateChange(AppLifecycleState.resumed), isTrue);
    },
  );
}
