import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Подтверждение отключения комментариев (спек 2026-07-30, §1.1): действие
// деструктивное по восприятию, поэтому требует явного подтверждения.
// Ключ обязан быть в ОБОИХ arb: CI-гейта на рассинхрон en/ru нет.
void main() {
  Map<String, dynamic> arb(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  test('ключи подтверждения есть и в en, и в ru', () {
    final en = arb('lib/l10n/intl_en.arb');
    final ru = arb('lib/l10n/intl_ru.arb');
    for (final key in [
      'disableChannelCommentsConfirmTitle',
      'disableChannelCommentsConfirmText',
    ]) {
      expect(en.containsKey(key), isTrue, reason: '$key отсутствует в en');
      expect(ru.containsKey(key), isTrue, reason: '$key отсутствует в ru');
      expect((ru[key] as String).isNotEmpty, isTrue);
    }
  });
}
