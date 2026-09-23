import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Инвариант перевёрнут 2026-08-27 (было: «шрифт лежит в assets и объявлен»).
// NotoColorEmoji как fallback отключён ещё 2026-08-01 (портил пробел и цифры,
// см. RL-web-font-locale), но объявление в pubspec осталось — и Flutter грузил
// все 10.4 МБ на старте, потому что качает ВСЕ шрифты из FontManifest.
// На вебе это был самый долгий ресурс первого экрана (~2.7 с). Раз глифами он
// всё равно не рисовал, шрифт удалён целиком.
void main() {
  test(
      'AC:RL-web-font-locale/5 — эмодзи-шрифт не объявлен в pubspec: '
      'объявление само по себе тянет 10.4 МБ на старте через FontManifest',
      () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    // Ищем именно ОБЪЯВЛЕНИЕ (`- family: NotoColorEmoji`), а не любое
    // упоминание: в pubspec стоит комментарий, объясняющий, почему шрифта
    // там нет, и он не должен ронять страж.
    final declared = RegExp(
      r'^\s*-\s*family:\s*NotoColorEmoji\s*$',
      multiLine: true,
    ).hasMatch(pubspec);
    expect(
      declared,
      isFalse,
      reason: 'NotoColorEmoji снова объявлен в pubspec.yaml — Flutter будет '
          'грузить его на старте (10.4 МБ) независимо от того, подключён ли '
          'он как fontFamilyFallback. Возвращать только подшрифтом без '
          'ASCII-диапазона (U+0020, U+0023, U+002A, U+0030-0039), иначе '
          'снова разъедутся пробелы и цифры станут квадратиками. '
          'См. tests/registry/RL-web-font-locale.md AC-2.',
    );
  });
}
