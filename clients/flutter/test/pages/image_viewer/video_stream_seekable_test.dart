// Юнит-тесты на чистые функции стриминг-конфига видео-плеера:
// `buildStreamLavfOpts` (какой `stream-lavf-o` собирается) и `isMmrBackedHost`
// (обслуживает ли хоумсервер медиа через MMR). Реальное поведение libmpv+Range
// завязано на нативные биндинги media_kit → проверяется device/manual
// (RL-video-stream-partial-not-full-download, AC-6..8).
//
// Реестр: tests/registry/RL-video-stream-partial-not-full-download.md
// Дизайн: docs/superpowers/specs/2026-08-18-video-stream-seekable-mmr-partial-load-design.md
//
// ledger:RL-video-stream-partial-not-full-download

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/image_viewer/video_player.dart';

void main() {
  group('isMmrBackedHost', () {
    test('прод-хоумсервер обслуживается MMR', () {
      expect(
        EventVideoPlayerState.isMmrBackedHost('synapse.liza.laba.prodamus.tech'),
        isTrue,
      );
    });

    test('cyber-agro/nadezhda — БЕЗ MMR (свой Synapse)', () {
      expect(EventVideoPlayerState.isMmrBackedHost('liza.cyber-agro.ru'), isFalse);
      expect(EventVideoPlayerState.isMmrBackedHost('nadezhda.liza.ru'), isFalse);
    });

    test('неизвестный/null хост — консервативно НЕ MMR', () {
      expect(EventVideoPlayerState.isMmrBackedHost(null), isFalse);
      expect(EventVideoPlayerState.isMmrBackedHost(''), isFalse);
      expect(EventVideoPlayerState.isMmrBackedHost('example.com'), isFalse);
    });
  });

  group('buildStreamLavfOpts', () {
    // Единица гейта — ORIGIN медиа (mxc-host), а НЕ хоумсервер читателя (уточнено
    // 2026-09-01: федеративное медиа приезжает через прод-MMR как remote_media на
    // диске и режет ОТКРЫТЫЙ Range до 10 МБ → seekable=0 обязателен, иначе ffmpeg
    // зацикливается). Инвариант «MMR-origin → частичная загрузка; не-MMR-origin →
    // seekable=0» сохранён; сменился ВХОД гейта (origin), не поведение функции.
    String opts({required bool encrypted, required bool onMmr}) =>
        EventVideoPlayerState.buildStreamLavfOpts(
          encrypted: encrypted,
          mediaOriginOnMmr: onMmr,
        );

    // AC:RL-video-stream-partial-not-full-download/1
    test('E2EE-путь: seekable=0 НЕ ставится (независимо от origin)', () {
      expect(opts(encrypted: true, onMmr: true), isNot(contains('seekable=0')));
      expect(opts(encrypted: true, onMmr: false), isNot(contains('seekable=0')));
    });

    // AC:RL-video-stream-partial-not-full-download/2
    test('не-E2EE + origin медиа на MMR (local_media/S3): seekable=0 СНЯТ', () {
      expect(opts(encrypted: false, onMmr: true), isNot(contains('seekable=0')));
    });

    // AC:RL-video-stream-partial-not-full-download/3
    test('не-E2EE + origin БЕЗ MMR (федеративное/standalone): seekable=0 СОХРАНЁН',
        () {
      expect(opts(encrypted: false, onMmr: false), contains('seekable=0'));
    });

    // AC:RL-video-stream-partial-not-full-download/4 — fail-safe покрыт через
    // isMmrBackedHost(unknown)=false → onMmr=false → эта же ветка (seekable=0).
    test('fail-safe: не-MMR ветка форсит seekable=0', () {
      final unknown = EventVideoPlayerState.isMmrBackedHost('unknown.host');
      expect(opts(encrypted: false, onMmr: unknown), contains('seekable=0'));
    });

    // AC:RL-video-stream-partial-not-full-download/5
    test('reconnect*-опции сохранены во всех ветках', () {
      for (final e in [true, false]) {
        for (final m in [true, false]) {
          final o = opts(encrypted: e, onMmr: m);
          expect(o, contains('reconnect=1'), reason: 'e=$e m=$m');
          expect(o, contains('reconnect_streamed=1'));
          expect(o, contains('reconnect_on_network_error=1'));
          expect(o, contains('reconnect_delay_max=5'));
        }
      }
    });

    test('seekable=0 идёт ПЕРВЫМ элементом (порядок lavf-опций)', () {
      // Позиция важна: seekable должен применяться до reconnect-логики.
      expect(opts(encrypted: false, onMmr: false), startsWith('seekable=0,'));
    });
  });
}
