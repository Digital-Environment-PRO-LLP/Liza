import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liza/widgets/mxc_image.dart';

/// ledger:RL-mxc-image-cache-selfheal-attachment
///
/// Регрессия (2026-07-27): фикс self-heal MR !228 чинил только путь
/// `downloadMxcCached` (аватары/uri), а превью и картинки из СОБЫТИЯ грузятся
/// вторым путём — `event.downloadAndDecryptAttachment` (кэш SDK `getFile`/
/// `storeFile`). Дисковый файл-кэш SDK не перезаписывает существующий файл и не
/// чистится `clearCache`, поэтому не-картинка, осевшая с кодом 200 во время
/// переезда медиа на MMR, «залипала» навсегда → `Image.memory` каждый раз падал
/// «Invalid image data». Сборка 3699 картинки НЕ починила именно поэтому.
///
/// `isPoisonedImageCache` — предикат, на котором держится self-heal второго пути
/// (сброс `deleteFile` + одноразовая перекачка). Тест защищает его решения.
void main() {
  Uint8List bytes(List<int> head, {int pad = 16}) {
    final l = List<int>.from(head);
    while (l.length < pad) {
      l.add(0);
    }
    return Uint8List.fromList(l);
  }

  final jpeg = bytes([0xFF, 0xD8, 0xFF, 0xE0]);
  final png = bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  final jsonErr = bytes('{"errcode":"M_'.codeUnits); // тело-ошибка матрикса
  final html = bytes('<!DOCTYPE htm'.codeUnits);

  bool poisoned({
    required bool wasInLocalStore,
    required bool isThumbnail,
    String msgtype = 'm.image',
    String mimeType = 'image/jpeg',
    required Uint8List b,
  }) =>
      MxcImage.isPoisonedImageCache(
        wasInLocalStore: wasInLocalStore,
        isThumbnail: isThumbnail,
        msgtype: msgtype,
        mimeType: mimeType,
        bytes: b,
      );

  group('isPoisonedImageCache — второй путь (вложение из события)', () {
    test('кэшированная не-картинка под превью → лечим', () {
      expect(
        poisoned(wasInLocalStore: true, isThumbnail: true, b: jsonErr),
        isTrue,
      );
      expect(
        poisoned(wasInLocalStore: true, isThumbnail: true, b: html),
        isTrue,
      );
    });

    test('кэшированная не-картинка под полноразмер (не видео) → лечим', () {
      expect(
        poisoned(wasInLocalStore: true, isThumbnail: false, b: jsonErr),
        isTrue,
      );
    });

    test('настоящая картинка из кэша → НЕ трогаем (JPEG/PNG)', () {
      expect(
        poisoned(wasInLocalStore: true, isThumbnail: true, b: jpeg),
        isFalse,
      );
      expect(
        poisoned(wasInLocalStore: true, isThumbnail: false, b: png),
        isFalse,
      );
    });

    test('свежескачанное (не из кэша) НЕ лечим — перекачка не поможет, зациклит',
        () {
      expect(
        poisoned(wasInLocalStore: false, isThumbnail: true, b: jsonErr),
        isFalse,
      );
    });

    test('видео целиком (полноразмер) — не-картинка ожидаема, НЕ трогаем', () {
      expect(
        poisoned(
          wasInLocalStore: true,
          isThumbnail: false,
          msgtype: 'm.video',
          mimeType: 'video/mp4',
          b: bytes([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70]),
        ),
        isFalse,
      );
    });

    test('превью видео — это картинка: битый кэш превью всё равно лечим', () {
      expect(
        poisoned(
          wasInLocalStore: true,
          isThumbnail: true,
          msgtype: 'm.video',
          mimeType: 'video/mp4',
          b: jsonErr,
        ),
        isTrue,
      );
    });
  });
}
