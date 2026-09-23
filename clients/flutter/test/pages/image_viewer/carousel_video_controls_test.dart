// Юнит-тесты на чистую функцию форматирования времени видео
// (media-v-format.md §8.9). Рендер CarouselVideoControls завязан на
// media_kit Player (нативные биндинги) — проверяется smoke-тестом на
// устройстве.

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/image_viewer/carousel_video_controls.dart';

void main() {
  group('formatVideoPosition', () {
    test('секунды — с ведущим нулём', () {
      expect(formatVideoPosition(const Duration(seconds: 5)), '0:05');
    });

    test('минуты и секунды', () {
      expect(
        formatVideoPosition(const Duration(minutes: 3, seconds: 7)),
        '3:07',
      );
    });

    test('часы — формат h:mm:ss с ведущими нулями минут', () {
      expect(
        formatVideoPosition(const Duration(hours: 1, minutes: 2, seconds: 9)),
        '1:02:09',
      );
    });

    test('ноль', () {
      expect(formatVideoPosition(Duration.zero), '0:00');
    });

    test('отрицательное клампится в ноль', () {
      expect(formatVideoPosition(const Duration(seconds: -10)), '0:00');
    });

    test('ровно час', () {
      expect(formatVideoPosition(const Duration(hours: 2)), '2:00:00');
    });

    test('минуты не выходят за 60 при переходе через час', () {
      expect(
        formatVideoPosition(const Duration(minutes: 75, seconds: 4)),
        '1:15:04',
      );
    });
  });
}
