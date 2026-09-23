import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/monitoring.dart';

/// Страж клиентского детектора дрейфа бейджа (ВТОРИЧНЫЙ human-facing сигнал):
/// серверное push-payload counts.unread против пост-sync СЫРОГО серверного числа.
/// Чистый оконный агрегатор — один сигнал за окно, порог душит штатный зазор.
///
/// ledger:RL-badge-drift-telemetry
void main() {
  final t0 = DateTime(2026, 8, 21, 12, 0, 0);

  group('BadgeDriftAggregator.amount', () {
    // AC:RL-badge-drift-telemetry/1  AC:RL-badge-drift-telemetry/2
    test('AC-1/AC-2: величина дрейфа = серверное − сырое клиентское', () {
      expect(BadgeDriftAggregator.amount(5, 1), 4);
      expect(BadgeDriftAggregator.amount(2, 2), 0);
      // клиент считает БОЛЬШЕ сервера — не патология (отрицательно)
      expect(BadgeDriftAggregator.amount(1, 3), -2);
    });
  });

  group('BadgeDriftAggregator.observe — порог', () {
    // AC:RL-badge-drift-telemetry/1
    test('AC-1: дрейф ≥ порога копится', () {
      final agg = BadgeDriftAggregator();
      expect(agg.observe(5, 1, t0), isNull); // первое окно — эмита ещё нет
      expect(agg.pendingCount, 1);
      agg.observe(4, 2, t0.add(const Duration(minutes: 1))); // drift=2 ≥ порог
      expect(agg.pendingCount, 2);
    });

    // AC:RL-badge-drift-telemetry/2
    test('AC-2: дрейф < порога и равенство — игнор (red-proof: порог>0 краснил бы)', () {
      final agg = BadgeDriftAggregator();
      agg.observe(2, 2, t0); // drift=0
      agg.observe(3, 2, t0.add(const Duration(seconds: 1))); // drift=1 < 2
      expect(agg.pendingCount, 0);
    });
  });

  group('BadgeDriftAggregator.observe — окно/троттл (AC-3)', () {
    // AC:RL-badge-drift-telemetry/3
    test('N наблюдений в окне → один эмит на границе следующего окна', () {
      final agg = BadgeDriftAggregator(window: const Duration(minutes: 10));
      // окно 1: три наблюдения дрейфа, эмита нет
      expect(agg.observe(5, 1, t0), isNull);
      expect(agg.observe(6, 1, t0.add(const Duration(minutes: 2))), isNull);
      expect(agg.observe(4, 1, t0.add(const Duration(minutes: 4))), isNull);
      expect(agg.pendingCount, 3);

      // первое наблюдение ПОСЛЕ окна → сбрасывает окно 1 (эмит) и начинает окно 2
      final flushed = agg.observe(7, 1, t0.add(const Duration(minutes: 11)));
      expect(flushed, isNotNull);
      expect(flushed!.count, 3);
      expect(flushed.maxDrift, 5); // max(4,5,6) из окна 1
      expect(agg.pendingCount, 1); // окно 2 уже несёт текущее наблюдение
    });

    test('под-пороговое наблюдение после окна тоже сбрасывает накопленное', () {
      final agg = BadgeDriftAggregator(window: const Duration(minutes: 10));
      agg.observe(5, 1, t0); // окно 1: drift=4
      final flushed = agg.observe(2, 2, t0.add(const Duration(minutes: 11))); // drift=0
      expect(flushed, isNotNull);
      expect(flushed!.count, 1);
      expect(agg.pendingCount, 0); // под-пороговое не завело новое окно
    });
  });

  group('AC-4: payload без PII — только числа', () {
    // AC:RL-badge-drift-telemetry/4
    test('эмит несёт count/maxDrift как int, без строк-идентификаторов', () {
      final agg = BadgeDriftAggregator(window: const Duration(minutes: 10));
      agg.observe(9, 1, t0);
      final flushed = agg.observe(3, 1, t0.add(const Duration(minutes: 11)));
      expect(flushed, isNotNull);
      expect(flushed!.count, isA<int>());
      expect(flushed.maxDrift, isA<int>());
    });
  });

  group('AC-5: детектор инертен без мониторинга', () {
    // AC:RL-badge-drift-telemetry/5
    test('reportBadgeDrift при выключенном мониторинге — no-op (не бросает)', () {
      // Monitoring не инициализирован в тесте → isActive=false → ранний return.
      expect(Monitoring.isActive, isFalse);
      expect(
        () => Monitoring.reportBadgeDrift(pushUnread: 9, postSyncRaw: 1, now: t0),
        returnsNormally,
      );
    });
  });
}
