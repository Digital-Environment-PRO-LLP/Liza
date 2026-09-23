import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// qt-faststart на чистом Dart: переносит атом `moov` (индекс MP4/MOV) в
/// начало файла, сразу после `ftyp`.
///
/// **Зачем.** iPhone и многие камеры пишут `moov` В КОНЕЦ файла (после
/// `mdat` с данными). Для прогрессивного воспроизведения по сети плееру
/// (libmpv) нужен `moov` — без Range-запросов (Synapse их не отдаёт) он
/// вынужден скачать ВЕСЬ файл, чтобы добраться до индекса в хвосте. На
/// тяжёлом видео это чёрный экран на минуты. С `moov` впереди плеер читает
/// индекс сразу и стримит, играя первые секунды почти мгновенно.
///
/// Операция чисто структурная (перекладка байтов + правка таблиц смещений
/// чанков `stco`/`co64`), без перекодирования и потери качества.
///
/// [process] возвращает новый буфер с faststart-раскладкой или `null`, если
/// перекладка не нужна / невозможна / что-то нестандартно (тогда вызывающий
/// шлёт оригинал — деградация, не порча).
class Mp4Faststart {
  /// Контейнер-боксы, в которые надо рекурсивно заходить в поисках
  /// `stco`/`co64`. Остальные боксы трактуем как листья и не разбираем.
  static const _containers = {
    'moov',
    'trak',
    'mdia',
    'minf',
    'stbl',
    'edts',
    'udta',
  };

  /// Порог защиты: не тащим в RAM экстремальные файлы (вся операция держит
  /// оригинал + копию). Видео крупнее — отправляем как есть. 1.5 ГБ.
  static const int _maxBytes = 1536 * 1024 * 1024;

  static Uint8List? process(Uint8List data) {
    try {
      if (data.lengthInBytes > _maxBytes) return null;
      final bd = ByteData.sublistView(data);
      final atoms = _topLevelAtoms(data, bd);
      if (atoms == null) return null;

      final moovIdx = atoms.indexWhere((a) => a.type == 'moov');
      final mdatIdx = atoms.indexWhere((a) => a.type == 'mdat');
      if (moovIdx < 0 || mdatIdx < 0) return null; // нет одного из ключевых
      if (moovIdx < mdatIdx) return null; // уже faststart — ничего не делаем
      if (atoms.where((a) => a.type == 'mdat').length != 1) return null;
      // Фрагментированный MP4 (fMP4): реальные указатели сэмплов лежат в
      // moof/trun (base_data_offset), а не только в moov/stco. Патчить их мы не
      // умеем → молча отдаём оригинал, иначе получили бы валидный по размеру,
      // но БИТЫЙ файл.
      if (atoms.any((a) => a.type == 'moof')) return null;

      final ftypIdx = atoms.indexWhere((a) => a.type == 'ftyp');

      final moov = atoms[moovIdx];
      // Сжатый moov (`cmov`) патчить нельзя — отступаем.
      if (_containsType(data, moov.start + moov.headerSize, moov.end, 'cmov')) {
        return null;
      }

      final moovBytes = Uint8List.sublistView(data, moov.start, moov.end);

      // Новая раскладка: ftyp, moov, затем все прочие атомы в исходном
      // порядке, КРОМЕ старого moov. Считаем, на сколько сдвинется начало
      // mdat → ровно на эту дельту правим смещения чанков.
      final reordered = <_Atom>[];
      if (ftypIdx >= 0) reordered.add(atoms[ftypIdx]);
      final moovInsertAt = reordered.length;
      for (var i = 0; i < atoms.length; i++) {
        if (i == ftypIdx || i == moovIdx) continue;
        reordered.add(atoms[i]);
      }

      var newMdatStart = -1, cursor = 0;
      for (var i = 0; i < reordered.length; i++) {
        if (i == moovInsertAt) cursor += moovBytes.lengthInBytes;
        if (reordered[i].type == 'mdat') newMdatStart = cursor;
        cursor += reordered[i].size;
      }
      final oldMdatStart = atoms[mdatIdx].start;
      if (newMdatStart < 0) return null;
      final delta = newMdatStart - oldMdatStart;
      if (delta == 0) return null;

      // Патчим копию moov: каждый stco(+32)/co64(+64) += delta. Смещения,
      // указывающие ВНЕ сдвигаемой области (< oldMdatStart), означают
      // нестандартную раскладку (данные сэмплов не только в mdat) — там +delta
      // неверен, _patchChunkOffsets вернёт false → отдаём оригинал.
      final patchedMoov = Uint8List.fromList(moovBytes);
      if (!_patchChunkOffsets(
        patchedMoov,
        delta,
        oldMdatStart,
        data.lengthInBytes + delta,
      )) {
        return null;
      }

      // Собираем новый файл.
      final out = BytesBuilder(copy: false);
      for (var i = 0; i < reordered.length; i++) {
        if (i == moovInsertAt) out.add(patchedMoov);
        final a = reordered[i];
        out.add(Uint8List.sublistView(data, a.start, a.end));
      }
      final result = out.toBytes();
      if (result.lengthInBytes != data.lengthInBytes) return null;
      return result;
    } catch (e) {
      if (kDebugMode) {
        // Любая неожиданная структура — молча отдаём оригинал.
        debugPrint('Mp4Faststart: skip ($e)');
      }
      return null;
    }
  }

  /// Разбор top-level атомов. `null` — если структура не похожа на ISO-BMFF.
  static List<_Atom>? _topLevelAtoms(Uint8List data, ByteData bd) {
    final atoms = <_Atom>[];
    var off = 0;
    final len = data.lengthInBytes;
    while (off + 8 <= len) {
      var size = bd.getUint32(off);
      final type = String.fromCharCodes(data, off + 4, off + 8);
      var headerSize = 8;
      if (size == 1) {
        if (off + 16 > len) return null;
        size = bd.getUint64(off + 8);
        headerSize = 16;
      } else if (size == 0) {
        // Атом до конца файла (обычно mdat).
        size = len - off;
      }
      if (size < headerSize || off + size > len) return null;
      // Тип должен быть печатным ASCII — иначе это не атом.
      if (!_isAsciiType(type)) return null;
      atoms.add(_Atom(type, off, off + size, headerSize));
      off += size;
    }
    if (off != len) return null; // хвост не разобрался — не трогаем
    return atoms;
  }

  /// Рекурсивно патчит stco/co64 внутри [box] (буфер уже скопированного
  /// moov). [minValidOffset] = старое начало mdat: каждое исходное смещение
  /// чанка обязано быть >= него (все данные сэмплов в mdat, который сдвигается
  /// на delta). Если меньше — раскладка нестандартная, +delta неверен.
  /// Возвращает false при переполнении/аномалии → отмена ремукса.
  static bool _patchChunkOffsets(
    Uint8List box,
    int delta,
    int minValidOffset,
    int fileLimit,
  ) {
    final bd = ByteData.sublistView(box);

    bool walk(int start, int end) {
      var off = start;
      while (off + 8 <= end) {
        var size = bd.getUint32(off);
        final type = String.fromCharCodes(box, off + 4, off + 8);
        var headerSize = 8;
        if (size == 1) {
          if (off + 16 > end) return false;
          size = bd.getUint64(off + 8);
          headerSize = 16;
        } else if (size == 0) {
          size = end - off;
        }
        if (size < headerSize || off + size > end) return false;
        final bodyStart = off + headerSize;
        if (type == 'stco') {
          // [version+flags:4][count:4][offset:4]×count
          final count = bd.getUint32(bodyStart + 4);
          var p = bodyStart + 8;
          for (var i = 0; i < count; i++) {
            if (p + 4 > off + size) return false;
            final orig = bd.getUint32(p);
            if (orig < minValidOffset) return false;
            final v = orig + delta;
            if (v < 0 || v > 0xFFFFFFFF || v > fileLimit) return false;
            bd.setUint32(p, v);
            p += 4;
          }
        } else if (type == 'co64') {
          final count = bd.getUint32(bodyStart + 4);
          var p = bodyStart + 8;
          for (var i = 0; i < count; i++) {
            if (p + 8 > off + size) return false;
            final orig = bd.getUint64(p);
            if (orig < minValidOffset) return false;
            final v = orig + delta;
            if (v < 0 || v > fileLimit) return false;
            bd.setUint64(p, v);
            p += 8;
          }
        } else if (_containers.contains(type)) {
          if (!walk(bodyStart, off + size)) return false;
        }
        off += size;
      }
      return true;
    }

    // box начинается с собственного заголовка moov — заходим в его тело.
    final headerSize = bd.getUint32(0) == 1 ? 16 : 8;
    return walk(headerSize, box.lengthInBytes);
  }

  static bool _containsType(Uint8List data, int start, int end, String type) {
    final bd = ByteData.sublistView(data);
    var off = start;
    while (off + 8 <= end) {
      var size = bd.getUint32(off);
      final t = String.fromCharCodes(data, off + 4, off + 8);
      if (t == type) return true;
      if (size == 1) {
        if (off + 16 > end) return false;
        size = bd.getUint64(off + 8);
      } else if (size == 0) {
        return false;
      }
      if (size < 8) return false;
      // Заходим внутрь известных контейнеров.
      if (_containers.contains(t)) {
        if (_containsType(data, off + 8, off + size, type)) return true;
      }
      off += size;
    }
    return false;
  }

  static bool _isAsciiType(String t) {
    for (final c in t.codeUnits) {
      if (c < 0x20 || c > 0x7E) return false;
    }
    return true;
  }
}

class _Atom {
  final String type;
  final int start;
  final int end;
  final int headerSize;
  const _Atom(this.type, this.start, this.end, this.headerSize);
  int get size => end - start;
}
