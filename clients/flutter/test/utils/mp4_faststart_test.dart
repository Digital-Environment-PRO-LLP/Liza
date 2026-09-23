import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/mp4_faststart.dart';

Uint8List _u32(int v) {
  final b = ByteData(4)..setUint32(0, v);
  return b.buffer.asUint8List();
}

Uint8List _box(String type, List<int> payload) {
  final size = 8 + payload.length;
  return Uint8List.fromList([..._u32(size), ...type.codeUnits, ...payload]);
}

/// stco: [version+flags:4][count:4][offset:4]×count
Uint8List _stco(List<int> offsets) {
  final body = <int>[0, 0, 0, 0, ..._u32(offsets.length)];
  for (final o in offsets) {
    body.addAll(_u32(o));
  }
  return _box('stco', body);
}

/// Собирает moov с одним trak→mdia→minf→stbl→stco.
Uint8List _moov(List<int> chunkOffsets) {
  final stco = _stco(chunkOffsets);
  final stbl = _box('stbl', stco);
  final minf = _box('minf', stbl);
  final mdia = _box('mdia', minf);
  final trak = _box('trak', mdia);
  return _box('moov', trak);
}

/// Читает смещения stco из произвольного буфера (рекурсивно по контейнерам).
List<int> _readStco(Uint8List data, int start, int end) {
  final bd = ByteData.sublistView(data);
  const containers = {'moov', 'trak', 'mdia', 'minf', 'stbl'};
  var off = start;
  while (off + 8 <= end) {
    final size = bd.getUint32(off);
    final type = String.fromCharCodes(data, off + 4, off + 8);
    if (type == 'stco') {
      final count = bd.getUint32(off + 12);
      final res = <int>[];
      var p = off + 16;
      for (var i = 0; i < count; i++) {
        res.add(bd.getUint32(p));
        p += 4;
      }
      return res;
    }
    if (containers.contains(type)) {
      final r = _readStco(data, off + 8, off + size);
      if (r.isNotEmpty) return r;
    }
    off += size;
  }
  return const [];
}

List<String> _topTypes(Uint8List data) {
  final bd = ByteData.sublistView(data);
  final types = <String>[];
  var off = 0;
  while (off + 8 <= data.lengthInBytes) {
    final size = bd.getUint32(off);
    types.add(String.fromCharCodes(data, off + 4, off + 8));
    off += size == 0 ? data.lengthInBytes - off : size;
  }
  return types;
}

void main() {
  group('Mp4Faststart', () {
    test('не-faststart (moov в хвосте) → moov уезжает в начало, '
        'смещения чанков сдвигаются на размер moov', () {
      final ftyp = _box('ftyp', List.filled(16, 0));
      // mdat: 8 байт заголовка + 200 байт данных.
      final mdat = _box('mdat', List.filled(200, 7));
      final mdatStart = ftyp.length; // 24
      // Смещения чанков указывают в данные mdat (после его заголовка).
      final origOffsets = [mdatStart + 8, mdatStart + 8 + 100];
      final moov = _moov(origOffsets);

      final input = Uint8List.fromList([...ftyp, ...mdat, ...moov]);
      expect(_topTypes(input), ['ftyp', 'mdat', 'moov']);

      final out = Mp4Faststart.process(input);
      expect(out, isNotNull);
      expect(out!.length, input.length, reason: 'ремукс не меняет размер');
      // Порядок: ftyp, moov, mdat.
      expect(_topTypes(out), ['ftyp', 'moov', 'mdat']);

      // Смещения должны вырасти ровно на размер moov (mdat сдвинулся вниз).
      final patched = _readStco(out, 0, out.length);
      expect(patched, [
        origOffsets[0] + moov.length,
        origOffsets[1] + moov.length,
      ]);
    });

    test('уже faststart (moov перед mdat) → null (ничего не делаем)', () {
      final ftyp = _box('ftyp', List.filled(16, 0));
      final moov = _moov([100, 200]);
      final mdat = _box('mdat', List.filled(200, 7));
      final input = Uint8List.fromList([...ftyp, ...moov, ...mdat]);

      expect(Mp4Faststart.process(input), isNull);
    });

    test('нет moov или mdat → null', () {
      final ftyp = _box('ftyp', List.filled(16, 0));
      final mdat = _box('mdat', List.filled(50, 1));
      expect(
        Mp4Faststart.process(Uint8List.fromList([...ftyp, ...mdat])),
        isNull,
      );
    });

    test('мусор/не ISO-BMFF → null, без исключений', () {
      expect(Mp4Faststart.process(Uint8List.fromList(List.filled(64, 42))),
          isNull);
      expect(Mp4Faststart.process(Uint8List(0)), isNull);
    });

    test('фрагментированный MP4 (есть moof) → null, не порть', () {
      // fMP4: указатели сэмплов в moof/trun, не только в stco — патчить нельзя.
      final ftyp = _box('ftyp', List.filled(16, 0));
      final mdat = _box('mdat', List.filled(200, 7));
      final moof = _box('moof', List.filled(40, 9));
      final moov = _moov([ftyp.length + moof.length + 8]);
      final input =
          Uint8List.fromList([...ftyp, ...mdat, ...moof, ...moov]);
      expect(Mp4Faststart.process(input), isNull);
    });

    test('смещение чанка вне сдвигаемой области (< старого mdat) → null', () {
      // Смещение указывает В ftyp (до mdat) → +delta неверен → bail.
      final ftyp = _box('ftyp', List.filled(16, 0));
      final mdat = _box('mdat', List.filled(200, 7));
      final moov = _moov([4]); // 4 — внутри ftyp, < mdatStart
      final input = Uint8List.fromList([...ftyp, ...mdat, ...moov]);
      expect(Mp4Faststart.process(input), isNull);
    });

    test('co64 (64-битные смещения) тоже патчатся', () {
      // moov с co64 вместо stco.
      Uint8List co64(List<int> offsets) {
        final body = <int>[0, 0, 0, 0, ..._u32(offsets.length)];
        for (final o in offsets) {
          final b = ByteData(8)..setUint64(0, o);
          body.addAll(b.buffer.asUint8List());
        }
        return _box('co64', body);
      }

      final ftyp = _box('ftyp', List.filled(16, 0));
      final mdat = _box('mdat', List.filled(200, 7));
      final mdatStart = ftyp.length;
      final moov = _box(
        'moov',
        _box('trak',
            _box('mdia', _box('minf', _box('stbl', co64([mdatStart + 8]))))),
      );
      final input = Uint8List.fromList([...ftyp, ...mdat, ...moov]);

      final out = Mp4Faststart.process(input);
      expect(out, isNotNull);
      expect(_topTypes(out!), ['ftyp', 'moov', 'mdat']);

      // Читаем co64 обратно (рекурсивно по контейнерам).
      List<int> readCo64(int start, int end) {
        final bd = ByteData.sublistView(out);
        const containers = {'moov', 'trak', 'mdia', 'minf', 'stbl'};
        var off = start;
        while (off + 8 <= end) {
          final size = bd.getUint32(off);
          final type = String.fromCharCodes(out, off + 4, off + 8);
          if (type == 'co64') {
            final count = bd.getUint32(off + 12);
            final res = <int>[];
            var p = off + 16;
            for (var i = 0; i < count; i++) {
              res.add(bd.getUint64(p));
              p += 8;
            }
            return res;
          }
          if (containers.contains(type)) {
            final r = readCo64(off + 8, off + size);
            if (r.isNotEmpty) return r;
          }
          off += size;
        }
        return const [];
      }

      expect(readCo64(0, out.length), [mdatStart + 8 + moov.length]);
    });
  });
}
