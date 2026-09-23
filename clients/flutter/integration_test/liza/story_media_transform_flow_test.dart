// Ярус C (device): реальный пинч-зум медиа сториса на НАСТОЯЩЕМ бинаре
// (iOS/Android). Host-тесты (story_media_canvas_test, story_model_test,
// story_overlay_geometry_test) проверяют рендер канваса, round-trip content и
// clamp; здесь — реальный МУЛЬТИТАЧ-жест на живом `StoryComposer` обновляет
// масштаб переднего плана (наблюдаемый эффект, персистится в media.scale).
//
// Системный медиа-пикер (ImagePicker/FilePicker) в integration_test не
// автоматизируется — поэтому монтируем композер напрямую с синтетическим
// изображением (обходим пикер, но жест и рендер — настоящие, на устройстве).
//
// AC:RL-stories-media-transform/12 — ledger:RL-stories-media-transform

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/stories/story_composer.dart';
import 'package:liza/pages/stories/story_media_canvas.dart';

// 1×1 PNG — валидное декодируемое изображение (aspect резолвится).
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, //
  0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, //
  0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, //
  0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, //
  0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'пинч двумя пальцами приближает медиа сториса (масштаб растёт, персист в media.scale) '
    '— ledger:RL-stories-media-transform',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: StoryComposer(
            file: MatrixImageFile(bytes: _png, name: 'fox.png'),
          ),
        ),
      );
      // Ждём резолва аспекта и первой отрисовки канваса.
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // Блюр-фон отрисован (механика MAX — размытый постер под вписанным медиа).
      expect(find.byType(StoryMediaCanvas), findsOneWidget);
      expect(find.byType(ImageFiltered), findsOneWidget);

      final state = tester.state<StoryComposerController>(
        find.byType(StoryComposer),
      );
      expect(state.mediaScale, 1.0, reason: 'старт — без зума');

      // Реальный двухпальцевый пинч: пальцы расходятся от центра канваса.
      final center = tester.getCenter(find.byType(StoryMediaCanvas));
      final g1 = await tester.startGesture(center - const Offset(30, 0));
      final g2 = await tester.startGesture(center + const Offset(30, 0));
      // Несколько шагов расхождения (плавный зум-ин).
      for (var i = 0; i < 5; i++) {
        await g1.moveBy(const Offset(-24, 0));
        await g2.moveBy(const Offset(24, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g1.up();
      await g2.up();
      await tester.pumpAndSettle();

      // Наблюдаемый эффект: масштаб переднего плана вырос (> старта), значит
      // media.scale уйдёт зрителям при публикации (persist в content).
      expect(
        state.mediaScale,
        greaterThan(1.0),
        reason: 'пинч наружу должен приблизить медиа',
      );
    },
  );
}
