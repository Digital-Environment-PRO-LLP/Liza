// Юниты на чистые функции HEIC-детектора. Реальная конверсия через
// flutter_image_compress опирается на нативные биндинги (ImageIO/MediaCodec),
// которых нет в test-окружении — это покрывается smoke-тестами на устройстве,
// см. plans/media-v-format.md §M1.HEIC шаг 6.

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/heic_converter.dart';

void main() {
  group('isHeicMimeType', () {
    test('распознаёт image/heic, image/heif и sequence-варианты', () {
      expect(isHeicMimeType('image/heic'), isTrue);
      expect(isHeicMimeType('image/heif'), isTrue);
      expect(isHeicMimeType('image/heic-sequence'), isTrue);
      expect(isHeicMimeType('image/heif-sequence'), isTrue);
    });

    test('case-insensitive (часть платформ возвращает IMAGE/HEIC)', () {
      expect(isHeicMimeType('IMAGE/HEIC'), isTrue);
      expect(isHeicMimeType('Image/Heif'), isTrue);
    });

    test('не путает с другими image/*', () {
      expect(isHeicMimeType('image/jpeg'), isFalse);
      expect(isHeicMimeType('image/png'), isFalse);
      expect(isHeicMimeType('image/webp'), isFalse);
      expect(isHeicMimeType('image/avif'), isFalse);
      expect(isHeicMimeType('application/pdf'), isFalse);
    });

    test('null и пустая строка → false', () {
      expect(isHeicMimeType(null), isFalse);
      expect(isHeicMimeType(''), isFalse);
    });
  });

  group('isHeicFile (по расширению)', () {
    test('детектит .heic / .heif в любом регистре', () {
      expect(isHeicFile('IMG_1234.heic'), isTrue);
      expect(isHeicFile('photo.HEIC'), isTrue);
      expect(isHeicFile('image.heif'), isTrue);
      expect(isHeicFile('/abs/path/to/file.HEIF'), isTrue);
    });

    test('не реагирует на другие расширения', () {
      expect(isHeicFile('photo.jpg'), isFalse);
      expect(isHeicFile('photo.png'), isFalse);
      expect(isHeicFile('heic.txt'), isFalse);
      expect(isHeicFile('photo.heic.txt'), isFalse);
    });

    test('пустая строка → false', () {
      expect(isHeicFile(''), isFalse);
    });
  });

  group('convertHeicFiles', () {
    test('не-HEIC файлы возвращаются без изменений', () async {
      final jpeg = XFile.fromData(
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
        name: 'photo.jpg',
        path: 'photo.jpg',
        mimeType: 'image/jpeg',
      );
      final png = XFile.fromData(
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]),
        name: 'image.png',
        path: 'image.png',
        mimeType: 'image/png',
      );

      final result = await convertHeicFiles([jpeg, png]);

      expect(result, hasLength(2));
      expect(result[0].name, equals('photo.jpg'));
      expect(result[0].mimeType, equals('image/jpeg'));
      expect(result[1].name, equals('image.png'));
      expect(result[1].mimeType, equals('image/png'));
    });

    test('пустой список → пустой список', () async {
      final result = await convertHeicFiles([]);
      expect(result, isEmpty);
    });

    test(
      'HEIC при отсутствии нативной поддержки fallback-ит на оригинал '
      '(сервер должен принять image/heic в allow-list)',
      () async {
        // В test-окружении flutter_image_compress нет нативных биндингов,
        // поэтому либо вернётся null (на Linux/Windows host), либо упадёт
        // на iOS/Android-симуляции. В любом случае оригинал должен дойти
        // до получателя без потери — это контракт convertHeicFiles.
        final heic = XFile.fromData(
          Uint8List.fromList([0, 0, 0, 24, 102, 116, 121, 112, 104, 101, 105, 99]),
          name: 'IMG_0001.heic',
          path: 'IMG_0001.heic',
          mimeType: 'image/heic',
        );

        final result = await convertHeicFiles([heic]);

        expect(result, hasLength(1));
        // Либо успешно сконвертилось в jpg, либо вернулся оригинал.
        // Обе ветки корректны — тест проверяет, что список не теряется.
        final out = result.single;
        expect(
          out.name == 'IMG_0001.jpg' || out.name == 'IMG_0001.heic',
          isTrue,
          reason: 'Файл должен либо сконвертироваться, либо остаться '
              'оригиналом — но не пропасть. Получено: "${out.name}"',
        );
      },
    );
  });
}
