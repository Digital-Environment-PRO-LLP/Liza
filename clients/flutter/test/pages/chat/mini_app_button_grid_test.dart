import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/pages/chat/events/mini_app_choice_content.dart';

// Раскладка кнопок mini App в стиле inline-клавиатуры Liza (грид 2 в ряд).
// rows() — чистая группировка по флагам half; визуальный PNG пишем в /tmp
// (скриншоты не коммитим — CLAUDE.md).

void main() {
  group('MiniAppButtonGrid.rows', () {
    test('detail-карточка: Открыть(full) + 4 действия парами + Назад(full)', () {
      // Открыть, [название|описание], [ссылка|удалить], Назад
      final half = [false, true, true, true, true, false];
      expect(
        MiniAppButtonGrid.rows(half),
        [
          [0],
          [1, 2],
          [3, 4],
          [5],
        ],
      );
    });

    test('нечётное число half: хвостовая одиночная — своим рядом (на всю ширину)', () {
      final half = [false, true, true, true, false];
      expect(
        MiniAppButtonGrid.rows(half),
        [
          [0],
          [1, 2],
          [3],
          [4],
        ],
      );
    });

    test('все full (как список приложений) — вертикальный стек', () {
      expect(
        MiniAppButtonGrid.rows([false, false, false]),
        [
          [0],
          [1],
          [2],
        ],
      );
    });
  });

  testWidgets('выбранная кнопка остаётся активной (паритет Liza: возврат в меню)',
      (tester) async {
    // LABA-2194 п.2: после выбора кнопки inline-клавиатура НЕ застывает —
    // picked-кнопка подсвечена, но остаётся нажимаемой (можно вернуться в меню).
    var pickedTaps = 0;
    var siblingTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MiniAppButtonGrid(
            buttons: [
              MiniAppGridButton(
                label: 'Создать бота',
                picked: true, // уже выбрана ранее
                onPressed: () => pickedTaps++,
              ),
              MiniAppGridButton(
                label: 'Мои боты',
                onPressed: () => siblingTaps++,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Создать бота'));
    await tester.tap(find.text('Мои боты'));
    await tester.pumpAndSettle();

    // Обе кнопки сработали — картинка «выбрано» не блокирует повторные нажатия.
    expect(pickedTaps, 1);
    expect(siblingTaps, 1);
  });

  testWidgets(
      'ledger:RL-botfather-menu-command парные кнопки ряда — одинаковой высоты '
      '(однострочная = двухстрочная соседка, LABA-2198)', (tester) async {
    // BotFather-меню: «Мои боты» (1 строка) рядом с «Мои приложения» (2 строки).
    // До фикса однострочная кнопка была ниже двухстрочной — теперь IntrinsicHeight
    // выравнивает высоту по самой высокой в ряду.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360, // узкий контейнер → длинный лейбл переносится в 2 строки
              child: MiniAppButtonGrid(
                buttons: [
                  MiniAppGridButton(
                    label: 'Мои боты',
                    half: true,
                    onPressed: () {},
                  ),
                  MiniAppGridButton(
                    label: 'Мои приложения инструментов',
                    half: true,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final shortBtn = tester.getRect(find.text('Мои боты'));
    final tallBtn = tester.getRect(find.text('Мои приложения инструментов'));
    // Санити: длинный лейбл действительно перенёсся (иначе тест ничего не ловит).
    expect(tallBtn.height, greaterThan(shortBtn.height),
        reason: 'длинный лейбл должен занимать больше строк, чем короткий');

    // Высота КНОПОК (ClipRRect с фоном), а не текста — должна совпасть.
    final clips = find.byType(ClipRRect);
    expect(clips, findsNWidgets(2));
    final h0 = tester.getSize(clips.at(0)).height;
    final h1 = tester.getSize(clips.at(1)).height;
    expect(h0, moreOrLessEquals(h1, epsilon: 0.5),
        reason: 'парные кнопки ряда должны быть одной высоты');
  });

  testWidgets('screenshot: detail-грид как в Liza', (tester) async {
    tester.view.physicalSize = const Size(440 * 2, 1400 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    // Подгружаем кириллический шрифт (хедлесс-тест иначе рисует □ вместо букв).
    const fontPath = '/System/Library/Fonts/Supplemental/Arial Unicode.ttf';
    String? fontFamily;
    if (File(fontPath).existsSync()) {
      final loader = FontLoader('AppCyr')
        ..addFont(Future.value(File(fontPath).readAsBytesSync().buffer.asByteData()));
      await loader.load();
      fontFamily = 'AppCyr';
    }

    final labels = [
      ('Открыть', false),
      ('Изменить название', true),
      ('Изменить описание', true),
      ('Изменить ссылку', true),
      ('Удалить', true),
      ('Назад к списку', false),
    ];

    // Воспроизводим НОВУЮ продакшн-раскладку (build() в mini_app_choice_content):
    // полупрозрачный пузырь текста + плоская inline-клавиатура, на фоне чата.
    Widget scene(Brightness brightness) {
      final scheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF2F7DF6),
        brightness: brightness,
      );
      final isDark = brightness == Brightness.dark;
      final chatBg = isDark ? const Color(0xFF0E1621) : const Color(0xFFEEF0FA);
      final bubbleColor = isDark
          ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
          : Colors.white.withValues(alpha: 0.62);
      return Theme(
        data: ThemeData(
          colorScheme: scheme,
          useMaterial3: true,
          fontFamily: fontFamily,
        ),
        child: Container(
          color: chatBg,
          padding: const EdgeInsets.all(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.circular(AppConfig.borderRadius),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Тест Надя',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: scheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Описание: —\n'
                        'Прямая ссылка: https://liza.laba.pro/i/p_yEXqGQtDCk\n'
                        'Web App URL: https://forms.yandex.ru/u/66e7f5ce5d2a06d309bf5119/',
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                MiniAppButtonGrid(
                  buttons: [
                    for (var i = 0; i < labels.length; i++)
                      MiniAppGridButton(
                        label: labels[i].$1,
                        half: labels[i].$2,
                        accent: i == 0,
                        onPressed: () {},
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  scene(Brightness.light),
                  scene(Brightness.dark),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Грид собрался в 4 ряда (детальная карточка) — на каждой из двух тем.
    expect(find.byType(MiniAppButtonGrid), findsNWidgets(2));

    final out = Platform.environment['MINIAPP_GRID_SHOT'];
    if (out != null) {
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(out).writeAsBytesSync(bytes!.buffer.asUint8List());
    }
  });
}
