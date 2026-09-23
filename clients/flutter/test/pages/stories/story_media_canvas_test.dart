import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liza/pages/stories/story_media_canvas.dart';
import 'package:liza/utils/stories/story_model.dart';

// Реальный виджет StoryMediaCanvas (Matrix-клиент не нужен — канвас автономен).
// ledger:RL-stories-media-transform
void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 360, height: 640, child: child)),
    ),
  );

  const fg = Key('fg');
  const bg = Key('bg');

  // AC:RL-stories-media-transform/3 — легаси cover: без блюра, медиа во весь кадр.
  testWidgets('background=cover → нет блюр-слоя, foreground во весь кадр', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const StoryMediaCanvas(
          foreground: ColoredBox(key: fg, color: Colors.red),
          background: StoryMediaBackground.cover,
          scale: 1.0,
          translation: Offset.zero,
          mediaAspect: 1.0,
          blurBackground: ColoredBox(key: bg, color: Colors.green),
        ),
      ),
    );
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byKey(fg), findsOneWidget);
    // Блюр-источник не рисуется в cover-режиме.
    expect(find.byKey(bg), findsNothing);
  });

  // Нет аспекта → тоже cover-fallback (нечего letterbox'ить).
  testWidgets('mediaAspect=null → cover-fallback без блюра', (tester) async {
    await tester.pumpWidget(
      wrap(
        const StoryMediaCanvas(
          foreground: ColoredBox(key: fg, color: Colors.red),
          background: StoryMediaBackground.blur,
          scale: 1.0,
          translation: Offset.zero,
          mediaAspect: null,
          blurBackground: ColoredBox(key: bg, color: Colors.green),
        ),
      ),
    );
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byKey(fg), findsOneWidget);
  });

  // AC:RL-stories-media-transform/5 — блюр-фон присутствует, foreground один.
  testWidgets(
    'background=blur → есть ImageFiltered + Transform, один foreground',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          const StoryMediaCanvas(
            foreground: ColoredBox(key: fg, color: Colors.red),
            background: StoryMediaBackground.blur,
            scale: 1.5,
            translation: Offset(0.1, -0.1),
            mediaAspect: 1.0, // квадрат в 9:16 → letterbox + блюр
            blurBackground: ColoredBox(key: bg, color: Colors.green),
          ),
        ),
      );
      expect(find.byType(ImageFiltered), findsOneWidget);
      expect(find.byType(Transform), findsWidgets);
      // Foreground ровно один (media_kit: один Video в дереве — не дублируем).
      expect(find.byKey(fg), findsOneWidget);
      // Блюр-источник тоже присутствует (обёрнут в ImageFiltered).
      expect(find.byKey(bg), findsOneWidget);
    },
  );

  // Битый content (scale=0 от чужого клиента) не схлопывает медиа в точку.
  testWidgets('scale=0 (битый content) → foreground виден, без краша', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const StoryMediaCanvas(
          foreground: ColoredBox(key: fg, color: Colors.red),
          background: StoryMediaBackground.blur,
          scale: 0.0, // corrupt
          translation: Offset.zero,
          mediaAspect: 1.0,
          blurBackground: ColoredBox(key: bg, color: Colors.green),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(fg), findsOneWidget);
    // safeScale поднял до 1.0 → есть Transform без вырождения.
    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    final collapsed = transforms.any(
      (t) => t.transform.getMaxScaleOnAxis() == 0.0,
    );
    expect(collapsed, isFalse);
  });

  // Трансформ применяется к переднему плану (scale отражён в матрице).
  testWidgets('scale>1 → Transform с ненулевым масштабом', (tester) async {
    await tester.pumpWidget(
      wrap(
        const StoryMediaCanvas(
          foreground: ColoredBox(key: fg, color: Colors.red),
          background: StoryMediaBackground.blur,
          scale: 2.0,
          translation: Offset.zero,
          mediaAspect: 9 / 16,
          blurBackground: ColoredBox(key: bg, color: Colors.green),
        ),
      ),
    );
    final transforms = tester.widgetList<Transform>(find.byType(Transform));
    // Хотя бы у одного Transform масштаб по X == 2.0 (наш слой переднего плана).
    final hasScale2 = transforms.any(
      (t) =>
          (t.transform.getMaxScaleOnAxis() - 2.0).abs() < 1e-6 ||
          (t.transform.entry(0, 0) - 2.0).abs() < 1e-6,
    );
    expect(hasScale2, isTrue);
  });
}
