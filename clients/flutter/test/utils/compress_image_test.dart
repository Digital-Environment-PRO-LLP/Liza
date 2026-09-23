import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/compress_image.dart';

void main() {
  group('sendImageTargetSize — длинная сторона приводится к 1280', () {
    test('ландшафт 5712×4284 → 1280×960', () {
      final r = sendImageTargetSize(5712, 4284);
      expect(r.width, 1280);
      expect(r.height, 960);
    });

    test('портрет 4284×5712 → 960×1280', () {
      final r = sendImageTargetSize(4284, 5712);
      expect(r.width, 960);
      expect(r.height, 1280);
    });

    test('квадрат 4000×4000 → 1280×1280', () {
      final r = sendImageTargetSize(4000, 4000);
      expect(r.width, 1280);
      expect(r.height, 1280);
    });

    test('широкая панорама — к 1280 приводится длинная сторона, не короткая',
        () {
      final r = sendImageTargetSize(6000, 2000);
      expect(r.width, 1280);
      expect(r.height, 427); // 2000 * 1280/6000 = 426.67
    });

    test('изображение меньше порога не апскейлится', () {
      final r = sendImageTargetSize(800, 600);
      expect(r.width, 800);
      expect(r.height, 600);
    });

    test('ровно на пороге остаётся как есть', () {
      final r = sendImageTargetSize(1280, 720);
      expect(r.width, 1280);
      expect(r.height, 720);
    });
  });
}
