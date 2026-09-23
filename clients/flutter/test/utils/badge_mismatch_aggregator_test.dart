import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/monitoring.dart';

/// Страж клиентского детектора РАСХОЖДЕНИЯ РЕНДЕРА бейджа: клиент-авторитетное
/// `expected` против того, что платформа реально держит на иконке (`shown`,
/// read-back `FlutterNewBadger.getBadge()`). Чистый оконный агрегатор, threshold=1
/// (любое подтверждённое расхождение iconBadge↔expected — дефект).
///
/// ledger:RL-badge-mismatch-signal
void main() {
  final t0 = DateTime(2026, 8, 31, 12, 0, 0);

  group('BadgeMismatchAggregator.delta', () {
    test('AC:RL-badge-mismatch-signal/1: |expected − shown|; 0 при совпадении', () {
      expect(BadgeMismatchAggregator.delta(5, 0), 5);
      expect(BadgeMismatchAggregator.delta(3, 3), 0);
      expect(BadgeMismatchAggregator.delta(0, 2), 2); // залипшая метка при 0
    });
  });

  group('BadgeMismatchAggregator.observe — порог/накопление', () {
    test('AC:RL-badge-mismatch-signal/1: любое расхождение (delta≥1) копится', () {
      final agg = BadgeMismatchAggregator();
      expect(agg.observe(5, 0, t0), isNull); // первое окно — эмита ещё нет
      expect(agg.pendingCount, 1);
      agg.observe(1, 0, t0.add(const Duration(minutes: 1))); // delta=1
      expect(agg.pendingCount, 2);
    });

    test('AC:RL-badge-mismatch-signal/2 (red-proof): совпадение (delta=0) — игнор', () {
      final agg = BadgeMismatchAggregator();
      agg.observe(3, 3, t0);
      agg.observe(0, 0, t0.add(const Duration(seconds: 1)));
      expect(agg.pendingCount, 0);
    });
  });

  group('BadgeMismatchAggregator.observe — окно/троттл', () {
    test('AC:RL-badge-mismatch-signal/2: N расхождений в окне → один эмит', () {
      final agg = BadgeMismatchAggregator(window: const Duration(minutes: 20));
      expect(agg.observe(5, 0, t0), isNull);
      expect(agg.observe(3, 0, t0.add(const Duration(minutes: 5))), isNull);
      expect(agg.observe(1, 0, t0.add(const Duration(minutes: 10))), isNull);
      expect(agg.pendingCount, 3);

      final flushed = agg.observe(2, 0, t0.add(const Duration(minutes: 21)));
      expect(flushed, isNotNull);
      expect(flushed!.count, 3);
      expect(flushed.maxDelta, 5); // max(5,3,1)
      expect(flushed.lastExpected, 1); // последнее наблюдение окна 1
      expect(flushed.lastShown, 0);
      expect(agg.pendingCount, 1); // окно 2 несёт текущее наблюдение
    });
  });

  group('AC:RL-badge-mismatch-signal/3: payload без PII — только числа', () {
    test('эмит несёт count/maxDelta/lastExpected/lastShown как int', () {
      final agg = BadgeMismatchAggregator(window: const Duration(minutes: 20));
      agg.observe(9, 0, t0);
      final flushed = agg.observe(3, 0, t0.add(const Duration(minutes: 21)));
      expect(flushed, isNotNull);
      expect(flushed!.count, isA<int>());
      expect(flushed.maxDelta, isA<int>());
      expect(flushed.lastExpected, isA<int>());
      expect(flushed.lastShown, isA<int>());
    });
  });

  group('AC:RL-badge-mismatch-signal/4: детектор инертен без мониторинга/при null', () {
    test('reportBadgeRenderMismatch при выключенном мониторинге — no-op', () {
      expect(Monitoring.isActive, isFalse);
      expect(
        () => Monitoring.reportBadgeRenderMismatch(
            expected: 5, shown: 0, now: t0),
        returnsNormally,
      );
    });

    test('shown==null (read-back невозможен) — no-op, не бросает', () {
      expect(
        () => Monitoring.reportBadgeRenderMismatch(
            expected: 5, shown: null, now: t0),
        returnsNormally,
      );
    });
  });

  group('title-маркер стабилен и низкой кардинальности', () {
    test('AC:RL-badge-mismatch-signal/5: маркер [badge-mismatch] + платформа, '
        'числа НЕ в title', () {
      expect(Monitoring.badgeMismatchPrefix, '[badge-mismatch]');
      final title = Monitoring.badgeMismatchTitle('ios');
      expect(title.contains('[badge-mismatch]'), isTrue);
      expect(title.contains('ios'), isTrue);
      // числа (expected/shown) НЕ в title — иначе GlitchTip расклеит по значению
      expect(RegExp(r'\d').hasMatch(title.replaceAll('badge-mismatch', '')),
          isFalse);
    });
  });
}
