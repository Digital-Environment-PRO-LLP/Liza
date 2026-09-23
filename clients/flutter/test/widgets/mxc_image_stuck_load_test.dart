import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/monitoring.dart';
import 'package:liza/widgets/mxc_image.dart';

/// ledger:RL-media-stuck-load-watchdog
///
/// Класс «тихий вечный спиннер»: `MxcImage._load` await'ил download/decrypt БЕЗ
/// таймаута → зависший await (сервер не отдаёт байты, исключения нет) не доходил
/// до `catch` в `_tryLoad` → `_failed` не ставился, `_recordGiveUp` не звался →
/// вечный `placeholder()`, ноль телеметрии. Баг Петра (пересланная галерея: 2/3
/// плитки крутят спиннер вечно, в логе 0 медиа-ошибок) — этого класса.
///
/// Фикс: watchdog-таймаут на сетевую фазу (thumb 20с / full 60с) → существующий
/// `_failed`+tap-to-retry + маркированный сигнал `[media-stuck]` (роутится в
/// «Liza · Медиа»). Здесь застражены ЧИСТЫЕ поверхности решения: агрегатор
/// (leading-edge + дедуп + маркер + PII-safe), классификатор reason и предикат
/// смены identity (защита от γ-ложняка). Тайминг `.timeout()`→`_failed` и
/// кнопка «Повторить» — device/manual (RL: AC-2/AC-3/AC-6-widget).
void main() {
  group('mediaStuckReasonFor — закрытый перечень (AC-1 reason)', () {
    test('TimeoutException → stuck-timeout (зависший await)', () {
      // AC:RL-media-stuck-load-watchdog/1
      expect(mediaStuckReasonFor(TimeoutException('x')), 'stuck-timeout');
    });

    test('иное исключение → give-up (исчерпаны ретраи)', () {
      expect(mediaStuckReasonFor(Exception('boom')), 'give-up');
      expect(mediaStuckReasonFor(StateError('s')), 'give-up');
    });
  });

  group('MediaStuckAggregator — leading-edge + дедуп + маркер', () {
    test('AC-1: первая сдача в окне эмитит ровно один сигнал', () {
      final agg = MediaStuckAggregator(now: () => DateTime(2026, 9, 1, 10));
      final msg = agg.onGiveUp('stuck-timeout', 'user.liza.ru');
      expect(msg, isNotNull);
    });

    test('AC-5: сигнал несёт маркер [media-stuck] + host, БЕЗ media_id (PII)', () {
      // AC:RL-media-stuck-load-watchdog/5
      final agg = MediaStuckAggregator(now: () => DateTime(2026, 9, 1, 10));
      final msg = agg.onGiveUp('stuck-timeout', 'user.liza.ru')!;
      // Маркер обязателен — иначе notifier не сроутит в «Liza · Медиа».
      expect(msg, startsWith('[media-stuck]'));
      expect(msg, contains('reason=stuck-timeout'));
      // host — короткой формой: длинный + прежнее длинное пояснение выталкивали
      // сигнал за 100-символьный предел title GlitchTip (обрубок «вечный спи…»).
      expect(msg, contains('host=user.liza'));
      expect(msg.length, lessThanOrEqualTo(Monitoring.maxAlertTitleLength));
      // PII-safe: только server_name, никаких mxc/media_id в сигнале.
      expect(msg.contains('mxc://'), isFalse);
    });

    test('host отсутствует → сигнал без host-части (не падаем, не пишем null)',
        () {
      final agg = MediaStuckAggregator(now: () => DateTime(2026, 9, 1, 10));
      final msg = agg.onGiveUp('give-up', null)!;
      expect(msg, startsWith('[media-stuck]'));
      expect(msg.contains('host='), isFalse);
      expect(msg.contains('null'), isFalse);
    });

    test('AC-4 (red-proof): N сдач в одном окне → ровно ОДИН сигнал (дедуп)', () {
      var now = DateTime(2026, 9, 1, 10);
      final agg = MediaStuckAggregator(now: () => now);
      final emitted = <String>[];
      // AC:RL-media-stuck-load-watchdog/4
      // Обрыв сети: 10 плиток галереи таймаутят почти одновременно.
      for (var i = 0; i < 10; i++) {
        now = now.add(const Duration(seconds: 1));
        final m = agg.onGiveUp('stuck-timeout', 'user.liza.ru');
        if (m != null) emitted.add(m);
      }
      expect(emitted.length, 1); // leading-edge: не лавина из 10
    });

    test('AC-6 (ядро): по истечении окна защёлка снимается → новый сигнал', () {
      // AC:RL-media-stuck-load-watchdog/6
      var now = DateTime(2026, 9, 1, 10);
      final agg = MediaStuckAggregator(now: () => now);
      expect(agg.onGiveUp('stuck-timeout', 'a'), isNotNull); // окно 1
      expect(agg.onGiveUp('stuck-timeout', 'a'), isNull); // дедуп
      now = now.add(MediaStuckAggregator.window + const Duration(seconds: 1));
      expect(agg.onGiveUp('stuck-timeout', 'a'), isNotNull); // окно 2 — снова
    });
  });

  group('attachmentIdentityChanged — защита от γ (AC-7)', () {
    test('смена uri → identity изменилась (перезапуск загрузки)', () {
      // AC:RL-media-stuck-load-watchdog/7
      final a = MxcImage(uri: Uri.parse('mxc://s/aaa'));
      final b = MxcImage(uri: Uri.parse('mxc://s/bbb'));
      expect(MxcImage.attachmentIdentityChanged(a, b), isTrue);
    });

    test('смена cacheKey → identity изменилась', () {
      final a = MxcImage(uri: Uri.parse('mxc://s/aaa'), cacheKey: 'k1');
      final b = MxcImage(uri: Uri.parse('mxc://s/aaa'), cacheKey: 'k2');
      expect(MxcImage.attachmentIdentityChanged(a, b), isTrue);
    });

    test('всё то же → identity НЕ изменилась (нет лишнего перезапуска)', () {
      final a = MxcImage(uri: Uri.parse('mxc://s/aaa'), cacheKey: 'k1');
      final b = MxcImage(uri: Uri.parse('mxc://s/aaa'), cacheKey: 'k1');
      expect(MxcImage.attachmentIdentityChanged(a, b), isFalse);
    });
  });
}
