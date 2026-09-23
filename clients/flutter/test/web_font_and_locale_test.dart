@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/config/themes.dart';

// ledger:RL-web-font-locale
//
// История (2026-08-01): NotoColorEmoji подключался как fontFamilyFallback ради
// современных эмодзи, но портил ОБЫЧНЫЙ текст — помимо эмодзи в шрифте лежат
// ASCII-глифы:
//   * пробел U+0020 шириной 1.25 em против обычных ~0.25 em -> текст расползался;
//   * цифры 0-9 плюс # и * (база keycap-эмодзи 0️⃣1️⃣#️⃣) -> вместо цифр
//     рисовались цветные квадратики.
// Вырезания одного пробела не хватило (цифры остались), поэтому по решению
// пользователя fallback ВРЕМЕННО отключён в themes.dart.
//
// Страж держит два инварианта: эмодзи-шрифт не подключён, а если его будут
// возвращать — сначала обязана быть вычищена вся ASCII-часть.
void main() {
  /// Кодовые точки cmap шрифта. Полноценный парсер не нужен: проверяем
  /// присутствие конкретных ASCII-глифов и наличие эмодзи.
  Set<int> cmapCodePoints(File file) {
    final d = file.readAsBytesSync();
    int u16(int o) => (d[o] << 8) | d[o + 1];
    int u32(int o) =>
        (d[o] << 24) | (d[o + 1] << 16) | (d[o + 2] << 8) | d[o + 3];

    int? cmapOffset;
    final numTables = u16(4);
    for (var i = 0; i < numTables; i++) {
      final rec = 12 + i * 16;
      if (String.fromCharCodes(d.sublist(rec, rec + 4)) == 'cmap') {
        cmapOffset = u32(rec + 8);
      }
    }
    expect(cmapOffset, isNotNull, reason: 'в шрифте нет таблицы cmap');

    int? sub;
    final n = u16(cmapOffset! + 2);
    for (var i = 0; i < n; i++) {
      final rec = cmapOffset + 4 + i * 8;
      if (u16(rec) == 3 && (u16(rec + 2) == 10 || u16(rec + 2) == 1)) {
        sub = cmapOffset + u32(rec + 4);
      }
    }
    expect(sub, isNotNull, reason: 'не нашёл Unicode-подтаблицу cmap');

    final points = <int>{};
    final format = u16(sub!);
    expect(format, 12, reason: 'неожиданный формат cmap');
    final groups = u32(sub + 12);
    for (var i = 0; i < groups; i++) {
      final g = sub + 16 + i * 12;
      final start = u32(g);
      final end = u32(g + 4);
      // ASCII-диапазон разворачиваем поточечно, эмодзи — только маркер.
      for (var cp = start; cp <= end && cp <= 0x7F; cp++) {
        points.add(cp);
      }
      if (start <= 0x1F600 && 0x1F600 <= end) points.add(0x1F600);
    }
    return points;
  }

  testWidgets(
    'AC:RL-web-font-locale/1 — эмодзи-шрифт НЕ подключён к теме: как fallback '
    'он перехватывает пробел и цифры и портит обычный текст',
    (tester) async {
      for (final brightness in Brightness.values) {
        late ThemeData theme;
        await tester.pumpWidget(
          Builder(
            builder: (context) {
              theme = LizaThemes.buildTheme(context, brightness);
              return const SizedBox();
            },
          ),
        );

        final style = theme.textTheme.bodyMedium;
        expect(
          style?.fontFamily,
          isNot('NotoColorEmoji'),
          reason: 'эмодзи-шрифт стал основным ($brightness)',
        );
        expect(
          style?.fontFamilyFallback ?? const <String>[],
          isNot(contains('NotoColorEmoji')),
          reason: 'NotoColorEmoji вернули в fallback ($brightness). Прежде чем '
              'включать — вычисти из шрифта ВЕСЬ ASCII (U+0020, U+0023, '
              'U+002A, U+0030-0039), иначе цифры снова станут квадратиками, '
              'а пробелы разъедутся. См. AC-2.',
        );
      }
    },
  );

  test(
    'AC:RL-web-font-locale/2 — если шрифт возвращают, в нём не должно быть '
    'ASCII (страж на будущее включение)',
    () {
      final font = File('assets/fonts/NotoColorEmoji.ttf');
      if (!font.existsSync()) return; // шрифт удалили совсем — нечего стеречь

      final themes = File('lib/config/themes.dart').readAsStringSync();
      final enabled = RegExp(
        r"^\s*fontFamilyFallback:\s*const\s*\['NotoColorEmoji'\]",
        multiLine: true,
      ).hasMatch(themes);
      if (!enabled) return; // сейчас отключён — инвариант не применяется

      final points = cmapCodePoints(font);
      final ascii = points.where((cp) => cp <= 0x7F).toList()..sort();
      expect(
        ascii,
        isEmpty,
        reason: 'шрифт снова подключён, но содержит ASCII-глифы '
            '${ascii.map((c) => 'U+${c.toRadixString(16).toUpperCase()}').toList()} '
            '— они перехватят обычный текст',
      );
      expect(
        points,
        contains(0x1F600),
        reason: 'подключать шрифт без эмодзи бессмысленно',
      );
    },
  );
}
