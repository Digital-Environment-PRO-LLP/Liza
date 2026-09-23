import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/adaptive_orientation.dart';

void main() {
  group('allowedOrientationsForSize', () {
    test('телефон (короткая сторона < 700dp): только портрет', () {
      // iPhone-подобные размеры + мелкий планшет/складник на границе.
      for (final size in const [
        Size(390, 844),
        Size(844, 390),
        Size(360, 800),
        Size(600, 960), // ниже нового порога 700 -> телефон
        Size(699, 1000),
      ]) {
        expect(
          allowedOrientationsForSize(size),
          const [DeviceOrientation.portraitUp],
          reason: 'size=$size должен трактоваться как телефон',
        );
      }
    });

    test('планшет (короткая сторона >= 700dp): все ориентации', () {
      for (final size in const [
        Size(768, 1024),
        Size(1024, 768),
        Size(700, 1000), // ровно на пороге -> планшет
      ]) {
        expect(
          allowedOrientationsForSize(size),
          const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ],
          reason: 'size=$size должен трактоваться как планшет',
        );
      }
    });

    test('неизмеренный экран (0×0) деградирует к строгому портрету', () {
      expect(
        allowedOrientationsForSize(Size.zero),
        const [DeviceOrientation.portraitUp],
      );
    });
  });
}
