// Юнит-стражи heartbeat живости флота (ВТОРИЧНЫЙ liveness; первичный —
// серверный поллер). Ключ троттла — номер СБОРКИ: смена сборки эмитит heartbeat
// немедленно (иначе liveness молчит ровно после раската нового релиза, где он
// критичнее всего). GlitchTip не принимает sessions → autoSessionTracking=false.
//
// Подавление `[health]` в чате — на стороне notifier (pytest в
// servers/monitoring-notifier/test_notifier.py, AC-3/AC-4).
// Реестр: tests/registry/RL-monitoring-fleet-heartbeat.md
//
// ledger:RL-monitoring-fleet-heartbeat

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/monitoring.dart';

void main() {
  group('healthHeartbeatDue — троттл ПО НОМЕРУ СБОРКИ', () {
    final t0 = DateTime(2026, 8, 31, 12, 0, 0);

    // AC:RL-monitoring-fleet-heartbeat/1
    test('AC-1: другая сборка → эмит НЕМЕДЛЕННО, даже если окно не истекло', () {
      expect(
        Monitoring.healthHeartbeatDue(
          lastBuild: 3737,
          lastSent: t0, // только что слали на старой сборке
          currentBuild: 3738, // новая сборка
          now: t0.add(const Duration(minutes: 1)),
        ),
        isTrue,
        reason: 'после раската новой сборки heartbeat не должен молчать',
      );
    });

    // AC:RL-monitoring-fleet-heartbeat/1
    test('AC-1: та же сборка в пределах окна → подавлен; за окном → снова да', () {
      expect(
        Monitoring.healthHeartbeatDue(
          lastBuild: 3738,
          lastSent: t0,
          currentBuild: 3738,
          now: t0.add(const Duration(hours: 1)),
        ),
        isFalse,
      );
      expect(
        Monitoring.healthHeartbeatDue(
          lastBuild: 3738,
          lastSent: t0,
          currentBuild: 3738,
          now: t0.add(const Duration(hours: 21)),
        ),
        isTrue,
      );
    });

    // AC:RL-monitoring-fleet-heartbeat/1
    test('AC-1: нет прошлой отметки (первый запуск сборки) → да', () {
      expect(
        Monitoring.healthHeartbeatDue(
          lastBuild: null,
          lastSent: null,
          currentBuild: 3738,
          now: t0,
        ),
        isTrue,
      );
    });
  });

  group('Контракт heartbeat: маркер + GlitchTip sessions выключены', () {
    // AC:RL-monitoring-fleet-heartbeat/2
    test('AC-2: healthPrefix == "[health]" (контракт подавления с notifier)', () {
      expect(Monitoring.healthPrefix, '[health]');
    });

    // AC:RL-monitoring-fleet-heartbeat/2  (source-scan: GlitchTip не принимает sessions)
    test('AC-2: Monitoring.init выставляет enableAutoSessionTracking=false', () {
      // Опция задаётся внутри SentryFlutter.init (требует DSN — юнитом не
      // инстанцируется). Пиним КОНТРАКТ source-scan'ом: без явного false SDK
      // шлёт sessions, которые GlitchTip отвергает 4xx (deep-research 2026-08-31).
      final src = File('lib/utils/monitoring.dart').readAsStringSync();
      expect(
        src.contains('enableAutoSessionTracking = false'),
        isTrue,
        reason: 'init() обязан явно отключить session-tracking для GlitchTip',
      );
    });

    // AC:RL-monitoring-fleet-heartbeat/2
    test('AC-2: reportHealthHeartbeat при !isActive — no-op, не бросает', () async {
      expect(Monitoring.isActive, isFalse);
      await expectLater(Monitoring.reportHealthHeartbeat(), completes);
    });
  });
}
