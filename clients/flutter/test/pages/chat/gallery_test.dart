// Юниты на чистые функции альбома (media-v-format.md §8.5):
// парсеры поля `com.liza.gallery` и расчёт колонок сетки. Рендер
// `GalleryBubble` и группировка в ленте опираются на `Event`/`Timeline`
// и проверяются smoke-тестом на устройстве.

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat/events/gallery.dart';

void main() {
  group('galleryIdFromContent', () {
    test('извлекает id из корректного поля', () {
      final content = <String, Object?>{
        'msgtype': 'm.image',
        galleryContentKey: {'id': 'abc123', 'i': 0, 'n': 5},
      };
      expect(galleryIdFromContent(content), 'abc123');
    });

    test('null, если поля нет (обычное m.image)', () {
      expect(galleryIdFromContent({'msgtype': 'm.image'}), isNull);
    });

    test('null, если поле есть, но без id', () {
      expect(
        galleryIdFromContent({
          galleryContentKey: {'i': 0, 'n': 3},
        }),
        isNull,
      );
    });
  });

  group('galleryIndexFromContent', () {
    test('извлекает индекс', () {
      expect(
        galleryIndexFromContent({
          galleryContentKey: {'id': 'x', 'i': 3, 'n': 5},
        }),
        3,
      );
    });

    test('0 по умолчанию, если индекса нет', () {
      expect(galleryIndexFromContent({'msgtype': 'm.image'}), 0);
    });
  });

  group('galleryCountFromContent', () {
    test('извлекает n из корректного поля', () {
      expect(
        galleryCountFromContent({
          galleryContentKey: {'id': 'x', 'i': 0, 'n': 5},
        }),
        5,
      );
    });

    test('null, если n отсутствует', () {
      expect(
        galleryCountFromContent({
          galleryContentKey: {'id': 'x', 'i': 0},
        }),
        isNull,
      );
    });

    test('null, если поля gallery нет', () {
      expect(galleryCountFromContent({'msgtype': 'm.image'}), isNull);
    });
  });

  group('galleryCaptionFromContent', () {
    test('извлекает подпись с первого элемента', () {
      expect(
        galleryCaptionFromContent({
          galleryContentKey: {'id': 'x', 'i': 0, 'n': 2, 'caption': 'Привет'},
        }),
        'Привет',
      );
    });

    test('null, если подписи нет (элемент i>0)', () {
      expect(
        galleryCaptionFromContent({
          galleryContentKey: {'id': 'x', 'i': 1, 'n': 2},
        }),
        isNull,
      );
    });
  });

  group('galleryColumnsFor', () {
    test('1 фото — 1 колонка', () {
      expect(galleryColumnsFor(1), 1);
    });

    test('2-4 фото — 2 колонки', () {
      expect(galleryColumnsFor(2), 2);
      expect(galleryColumnsFor(3), 2);
      expect(galleryColumnsFor(4), 2);
    });

    test('5+ фото — 3 колонки', () {
      expect(galleryColumnsFor(5), 3);
      expect(galleryColumnsFor(10), 3);
    });
  });
}
