import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/client_download_content_extension.dart';

/// ledger:RL-mxc-image-cache-selfheal
///
/// Регрессия: во время переезда медиа на MMR (2026-07) клиент получал `200 OK`
/// с телом-НЕ-картинкой (JSON-ошибка / HTML) и кэшировал его; `downloadMxcCached`
/// потом отдавал кэш без перепроверки → `Image.memory` падал «Invalid image data»,
/// и «ранее загруженные» превью залипали битыми навсегда. Фикс: кэшировать и
/// отдавать из кэша только настоящие картинки (magic-байты), иначе — перекачать.
/// Этот тест защищает детектор, на котором держится self-heal.
void main() {
  Uint8List b(List<int> head, {int pad = 16}) {
    final l = List<int>.from(head);
    while (l.length < pad) {
      l.add(0);
    }
    return Uint8List.fromList(l);
  }

  group('looksLikeCacheableImage — настоящие картинки', () {
    test('JPEG', () => expect(looksLikeCacheableImage(b([0xFF, 0xD8, 0xFF, 0xE0])), isTrue));
    test('PNG', () => expect(looksLikeCacheableImage(b([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])), isTrue));
    test('GIF', () => expect(looksLikeCacheableImage(b([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])), isTrue));
    test('BMP', () => expect(looksLikeCacheableImage(b([0x42, 0x4D])), isTrue));
    test('WebP', () => expect(looksLikeCacheableImage(b([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50])), isTrue));
    test('HEIC/ISOBMFF ftyp', () => expect(looksLikeCacheableImage(b([0, 0, 0, 0x20, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63])), isTrue));
  });

  group('looksLikeCacheableImage — НЕ картинки (не кэшировать/перекачать)', () {
    test('JSON matrix-ошибка', () {
      final json = Uint8List.fromList('{"errcode":"M_NOT_FOUND","error":"Not found"}'.codeUnits);
      expect(looksLikeCacheableImage(json), isFalse);
    });
    test('HTML прокси-страница', () {
      final html = Uint8List.fromList('<html><body>502 Bad Gateway</body></html>'.codeUnits);
      expect(looksLikeCacheableImage(html), isFalse);
    });
    test('пустое тело', () => expect(looksLikeCacheableImage(Uint8List(0)), isFalse));
    test('слишком короткое', () => expect(looksLikeCacheableImage(Uint8List.fromList([0xFF, 0xD8])), isFalse));
    test('бинарный мусор/обрезок', () => expect(looksLikeCacheableImage(b([0x00, 0x01, 0x02, 0x03, 0x04])), isFalse));
  });
}
