// Юнит-стражи клиентского (вторичного) push-health сигнала: стабильный PII-safe
// title `Monitoring.pushIssueTitle`, контракт префикса `[push-fail]` с notifier,
// no-op при !isActive. Реальный сигнал на устройстве (нативная сборка, foreground)
// — device/manual (AC-5).
//
// Первичный слой — серверный `analytics.pusher_app_id_dist` + поллер (killed-app
// покрыт им, не клиентом). Реестр: tests/registry/RL-push-health-signal-client.md
// Дизайн: docs/superpowers/specs/2026-08-27-proactive-push-failure-detection-design.md
//
// ledger:RL-push-health-signal-client

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/monitoring.dart';

void main() {
  group('Monitoring.pushIssueTitle — маркер + reason, БЕЗ секретов', () {
    // AC:RL-push-health-signal-client/1
    test('AC-1: title = префикс + reason, стабилен (без счётчика → дедуп цел)', () {
      expect(
        Monitoring.pushIssueTitle('fcm_token_unavailable'),
        '[push-fail] reason=fcm_token_unavailable',
      );
      expect(
        Monitoring.pushIssueTitle('post_pusher_exhausted'),
        '[push-fail] reason=post_pusher_exhausted',
      );
    });

    // AC:RL-push-health-signal-client/3  AC:RL-mediadiag-no-secret/push-fail
    test('AC-3: title НЕ несёт mxid/pushkey-значение/токен-значение (red-proof)', () {
      // Проверяем, что в title не интерполируется ПЕРЕМЕННОЕ значение (mxid,
      // токен, pushkey). reason — фиксированная метка, значений не несёт.
      // (Слово "token" внутри метки `fcm_token_unavailable` — не секрет.)
      final title = Monitoring.pushIssueTitle('fcm_token_unavailable');
      for (final forbidden in const [
        '@',            // mxid @user:server
        ':synapse',     // домен mxid
        'access_token=',
        'bearer ',
        'authorization',
        'pushkey=',
        r'$user',
        r'$token',
      ]) {
        expect(title.toLowerCase(), isNot(contains(forbidden.toLowerCase())));
      }
    });
  });

  group('Контракт префикса с notifier + инертность', () {
    // AC:RL-push-health-signal-client/3
    test('AC-3: маркер [push-fail] стабилен — контракт с monitoring-notifier/поллером', () {
      expect(Monitoring.pushFailurePrefix, '[push-fail]');
    });

    // AC:RL-push-health-signal-client/4  (Д-4: троттл per-reason)
    test('AC-4: pushIssueThrottleAllows — один эмит per-reason за окно 10м', () {
      final t0 = DateTime(2026, 8, 27, 12, 0, 0);
      // уникальный reason на тест (статик-мапа переживает между тестами)
      const r = 'fcm_token_unavailable_ac4';
      expect(Monitoring.pushIssueThrottleAllows(r, t0), isTrue); // первый — можно
      expect(
        Monitoring.pushIssueThrottleAllows(r, t0.add(const Duration(seconds: 5))),
        isFalse, // resume через 5с — подавлен (иначе флуд GlitchTip)
      );
      expect(
        Monitoring.pushIssueThrottleAllows(r, t0.add(const Duration(minutes: 11))),
        isTrue, // за окном — снова можно
      );
      // разные reason независимы
      expect(
        Monitoring.pushIssueThrottleAllows('post_pusher_exhausted_ac4', t0),
        isTrue,
      );
    });

    // AC:RL-push-health-signal-client/2
    test('AC-2: reportPushIssue при !isActive — no-op, не бросает', () {
      // Monitoring не инициализирован в тестах → _active=false → полный no-op
      // (тот же гейт, что защищает от эмита из фонового FCM-изолята: _active там
      // тоже false — honest-gap killed-app, покрыт серверным слоем).
      expect(Monitoring.isActive, isFalse);
      expect(
        () => Monitoring.reportPushIssue('fcm_token_unavailable'),
        returnsNormally,
      );
    });
  });
}
