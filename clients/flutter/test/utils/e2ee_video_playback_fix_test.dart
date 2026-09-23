// Юнит-тест механизма, который «расклинивает» крупное E2EE-видео с moov-в-хвосте
// (iPhone .mov), из-за которого libmpv через прокси проваливался в playlist-
// эвристику и виснет («Reading plaintext playlist»). На ПРИЁМЕ download-фолбэка
// (после полной расшифровки в RAM) применяется `Mp4Faststart.process` — moov в
// начало → libmpv читает индекс сразу.
//
// Реальное воспроизведение 161 МБ E2EE + отсутствие «Reading plaintext playlist»
// + устранение per-Range TLS-reconnect в прокси — device/manual (vodozemac +
// libmpv не грузятся в host-`flutter test`), см. AC-2/AC-4 реестра.
//
// Реестр: tests/registry/RL-e2ee-video-proxy-not-playlist.md
// Дизайн: docs/superpowers/specs/2026-08-26-e2ee-large-video-playback-and-download-fix-design.md
//
// ledger:RL-e2ee-video-proxy-not-playlist

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/mp4_faststart.dart';

Uint8List _u32(int v) => (ByteData(4)..setUint32(0, v)).buffer.asUint8List();

Uint8List _box(String type, List<int> payload) {
  final size = 8 + payload.length;
  return Uint8List.fromList([..._u32(size), ...type.codeUnits, ...payload]);
}

/// moov с одним trak→mdia→minf→stbl→stco (одна таблица смещений).
Uint8List _moov(List<int> chunkOffsets) {
  final body = <int>[0, 0, 0, 0, ..._u32(chunkOffsets.length)];
  for (final o in chunkOffsets) {
    body.addAll(_u32(o));
  }
  final stco = _box('stco', body);
  return _box('moov', _box('trak', _box('mdia', _box('minf', _box('stbl', stco)))));
}

int _indexOfType(Uint8List data, String type) {
  final bd = ByteData.sublistView(data);
  var off = 0;
  var idx = 0;
  while (off + 8 <= data.lengthInBytes) {
    final size = bd.getUint32(off);
    final t = String.fromCharCodes(data, off + 4, off + 8);
    if (t == type) return idx;
    off += size == 0 ? data.lengthInBytes - off : size;
    idx++;
  }
  return -1;
}

void main() {
  group('Mp4Faststart расклинивает moov-в-хвосте (фикс playlist-виса)', () {
    // AC:RL-e2ee-video-proxy-not-playlist/1
    test('moov в ХВОСТЕ (iPhone .mov) → перекладывается В НАЧАЛО', () {
      final ftyp = _box('ftyp', List.filled(8, 0));
      final mdat = _box('mdat', List.filled(64, 0x11));
      final moov = _moov([ftyp.length + mdat.length]); // offset внутрь mdat
      final atEnd = Uint8List.fromList([...ftyp, ...mdat, ...moov]);

      // До: moov ПОСЛЕ mdat (клинит воспроизведение).
      expect(
        _indexOfType(atEnd, 'moov') > _indexOfType(atEnd, 'mdat'),
        isTrue,
        reason: 'предусловие: исходник с moov-в-хвосте',
      );

      final out = Mp4Faststart.process(atEnd);
      expect(out, isNotNull, reason: 'должен переложить moov');
      // После: moov ПЕРЕД mdat → libmpv читает индекс сразу, не виснет.
      expect(_indexOfType(out!, 'moov') < _indexOfType(out, 'mdat'), isTrue);
      // Размер сохранён (структурная перекладка без потери данных).
      expect(out.length, atEnd.length);
    });

    // red-proof: уже-faststart НЕ трогаем (иначе бесконечная перекладка/порча).
    test('moov уже В НАЧАЛЕ → process возвращает null (no-op)', () {
      final ftyp = _box('ftyp', List.filled(8, 0));
      final moov = _moov([0]);
      final mdat = _box('mdat', List.filled(64, 0x11));
      final faststart = Uint8List.fromList([...ftyp, ...moov, ...mdat]);
      expect(Mp4Faststart.process(faststart), isNull);
    });

    test('не-MP4 мусор → null (деградация, не порча)', () {
      final junk = Uint8List.fromList(List.generate(128, (i) => i % 256));
      expect(Mp4Faststart.process(junk), isNull);
    });
  });
}
