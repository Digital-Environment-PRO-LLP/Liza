import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/widgets/mxc_image.dart';

/// Регресс: в E2EE-комнате картинки от части клиентов приходят с пустым
/// `info.mimetype`. detectFileType (по MIME) их не распознавал → полноэкранный
/// просмотр (isThumbnail:false) оставался пустым. Фикс — fallback на sniff
/// магических байтов. Этот тест фиксирует, что sniff узнаёт реальные форматы и
/// при этом НЕ принимает видео за картинку (иначе MxcImage качал бы видео
/// целиком и пытался отрисовать его как изображение).
void main() {
  Uint8List bytes(List<int> head) {
    final b = Uint8List(16);
    for (var i = 0; i < head.length; i++) {
      b[i] = head[i];
    }
    return b;
  }

  group('MxcImage.looksLikeImageMagic — узнаёт изображения', () {
    test('JPEG (FF D8 FF)', () {
      expect(MxcImage.looksLikeImageMagic(bytes([0xFF, 0xD8, 0xFF, 0xE0])), isTrue);
    });

    test('PNG', () {
      expect(
        MxcImage.looksLikeImageMagic(
          bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ),
        isTrue,
      );
    });

    test('GIF', () {
      expect(
        MxcImage.looksLikeImageMagic(bytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])),
        isTrue,
      );
    });

    test('BMP', () {
      expect(MxcImage.looksLikeImageMagic(bytes([0x42, 0x4D, 0x00, 0x00])), isTrue);
    });

    test('WebP (RIFF....WEBP)', () {
      expect(
        MxcImage.looksLikeImageMagic(
          bytes([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50]),
        ),
        isTrue,
      );
    });

    test('HEIC (ftyp + heic brand)', () {
      expect(
        MxcImage.looksLikeImageMagic(
          bytes([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x68, 0x65, 0x69, 0x63]),
        ),
        isTrue,
      );
    });
  });

  group('MxcImage.looksLikeImageMagic — НЕ принимает не-изображения', () {
    test('MP4-видео (ftyp + isom brand) не матчит', () {
      expect(
        MxcImage.looksLikeImageMagic(
          bytes([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6F, 0x6D]),
        ),
        isFalse,
      );
    });

    test('PDF не матчит', () {
      expect(
        MxcImage.looksLikeImageMagic(bytes([0x25, 0x50, 0x44, 0x46, 0x2D])),
        isFalse,
      );
    });

    test('слишком короткий буфер не падает и не матчит', () {
      expect(MxcImage.looksLikeImageMagic(Uint8List.fromList([0xFF, 0xD8])), isFalse);
    });
  });
}
