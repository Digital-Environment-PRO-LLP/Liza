// Страж детекции мёртвого reconnect (stalled-reconnect) по МОНОТОННОЙ stream-pos.
// Инцидент 2026-09-01: 230МБ видео reconnect'ило вечно, watchdog по
// paused-for-cache=yes считал «живым» → тихий провал без сигнала/«Повторить».
//
// Мультикейс ∀ (иначе ложно-зелёный): живой-медленный / mid-reconnect-alive /
// paused-растущий / reconnect-forever-dead / streamPos-недоступна / reset.
// Переиспользует формулу RL-e2ee-video-proxy-resume (терминал только при 0
// прогресса; счётчик сброс на любом росте) — чистый детектор, без mpv/виджета.
//
// Реестр: tests/registry/RL-video-stalled-reconnect-terminal.md
// ledger:RL-video-stalled-reconnect-terminal

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/image_viewer/video_player.dart';

void main() {
  StalledReconnectDetector make() => StalledReconnectDetector(thresholdTicks: 8);

  // AC:RL-video-stalled-reconnect-terminal/1
  test('AC-1: живой-медленный (stream-pos растёт каждый тик при paused-for-cache) '
      '→ 0 терминалов (не рубим живой)', () {
    final d = make();
    var pos = 1000000;
    var fired = false;
    for (var i = 0; i < 30; i++) {
      pos += 500000; // байты растут (медленно, но идут)
      if (d.observe(streamPos: pos, pausedForCache: true)) fired = true;
    }
    expect(fired, isFalse);
  });

  // AC:RL-video-stalled-reconnect-terminal/2
  test('AC-2: mid-reconnect-alive (рывковая докачка 10МБ→reset→+15МБ, но растёт) '
      '→ 0 терминалов', () {
    final d = make();
    // рывки: несколько тиков без роста, потом скачок — как reconnect с resume
    final bursts = [10, 10, 25, 25, 25, 40, 40, 60, 60, 60, 60, 90];
    var fired = false;
    for (final mb in bursts) {
      // каждый шаг байты БОЛЬШЕ предыдущего максимума (resume идёт вперёд)
      if (d.observe(streamPos: mb * 1000000, pausedForCache: true)) fired = true;
    }
    expect(fired, isFalse, reason: 'живая рывковая докачка — не стрелл');
  });

  // AC:RL-video-stalled-reconnect-terminal/4  (главный: мёртвый reconnect)
  test('AC-4: reconnect-forever-dead (stream-pos ЗАСТЫЛ при paused-for-cache) → '
      'ровно 1 терминал после порога, не раньше', () {
    final d = make();
    const stuck = 10485796; // застрял на 10МБ (как в логе 230МБ)
    // первый замер задаёт lastPos, терминал не может сработать раньше threshold
    var fireTick = -1;
    for (var i = 0; i < 20; i++) {
      if (d.observe(streamPos: stuck, pausedForCache: true)) {
        fireTick = i;
        break;
      }
    }
    // lastPos ставится на 1-м observe, счётчик растёт со 2-го → терминал на 9-м (i=8)
    expect(fireTick, 8, reason: '8 тиков (16с) нулевого роста → терминал');
    // повторно НЕ дублирует
    var again = false;
    for (var i = 0; i < 10; i++) {
      if (d.observe(streamPos: stuck, pausedForCache: true)) again = true;
    }
    expect(again, isFalse, reason: 'один сигнал на сессию');
  });

  // AC:RL-video-stalled-reconnect-terminal/3
  test('AC-3: НЕ paused-for-cache (играет) → 0 терминалов + сброс счётчика', () {
    final d = make();
    const stuck = 5000000;
    // накопили почти до порога при paused
    for (var i = 0; i < 7; i++) {
      d.observe(streamPos: stuck, pausedForCache: true);
    }
    expect(d.pendingTicks, greaterThan(0));
    // один тик «играет» (не paused) — сброс
    expect(d.observe(streamPos: stuck, pausedForCache: false), isFalse);
    expect(d.pendingTicks, 0, reason: 'проигрывание сбрасывает стрелл-счётчик');
  });

  // AC:RL-video-stalled-reconnect-terminal/6
  test('AC-6: stream-pos недоступна (<0, локальный файл/не стрим) → не терминалит', () {
    final d = make();
    var fired = false;
    for (var i = 0; i < 20; i++) {
      if (d.observe(streamPos: -1, pausedForCache: true)) fired = true;
    }
    expect(fired, isFalse);
  });

  // AC:RL-video-stalled-reconnect-terminal/7
  test('AC-7: reset() снимает защёлку → после «Повторить» детект снова работает', () {
    final d = make();
    const stuck = 3000000;
    for (var i = 0; i < 12; i++) {
      d.observe(streamPos: stuck, pausedForCache: true);
    }
    d.reset();
    expect(d.pendingTicks, 0);
    // снова стрелл → снова срабатывает
    var fired = false;
    for (var i = 0; i < 12; i++) {
      if (d.observe(streamPos: stuck, pausedForCache: true)) fired = true;
    }
    expect(fired, isTrue, reason: 'после reset детектор снова терминалит');
  });
}
