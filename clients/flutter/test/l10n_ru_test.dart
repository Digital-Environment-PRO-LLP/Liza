import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _loadArb(String locale) {
  final file = File('lib/l10n/intl_$locale.arb');
  return json.decode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('русская локализация', () {
    late Map<String, dynamic> ru;

    setUp(() => ru = _loadArb('ru'));

    test('нет гендерных костылей вида «(а)»', () {
      final pattern = RegExp(r'\((?:а|ась|ся|о|ы)\)');
      final offenders = <String>[];

      ru.forEach((key, value) {
        if (key.startsWith('@') || value is! String) return;
        if (pattern.hasMatch(value)) offenders.add('$key = $value');
      });

      expect(offenders, isEmpty,
          reason: 'Гендерные костыли должны быть убраны:\n${offenders.join('\n')}');
    });

    test('все ключи из en присутствуют в ru', () {
      final en = _loadArb('en');
      final missing = <String>[];

      for (final key in en.keys) {
        if (key.startsWith('@')) continue;
        if (!ru.containsKey(key)) missing.add(key);
      }

      expect(missing, isEmpty,
          reason: 'Ключи есть в en, но нет в ru — покажется английский:\n'
              '${missing.join('\n')}');
    });

    test('в ru нет непереведённых английских строк', () {
      // «Email» по-русски пишется так же — переводить нечего.
      const allowed = {
        'liza',
        'id',
        'title',
        'alwaysUse24HourFormat',
        'demoAuthChannelEmail',
        // «GIF» — название формата, в русском интерфейсе пишется так же.
        'gifBadge',
      };
      final offenders = <String>[];

      ru.forEach((key, value) {
        if (key.startsWith('@') || value is! String) return;
        if (allowed.contains(key)) return;
        final body = value.replaceAll(RegExp(r'\{[^}]*\}'), '');
        final hasLatin = RegExp(r'[A-Za-z]').hasMatch(body);
        final hasCyrillic = RegExp(r'[А-Яа-яЁё]').hasMatch(body);
        if (hasLatin && !hasCyrillic) offenders.add('$key = $value');
      });

      expect(offenders, isEmpty,
          reason: 'Непереведённые строки:\n${offenders.join('\n')}');
    });

    test('plural-ключи используют русские категории few/many', () {
      const pluralKeys = [
        'numUsersTyping',
        'userAndOthersAreTyping',
        'numChats',
        'filesHaveBeenSaved',
      ];

      for (final key in pluralKeys) {
        final value = ru[key] as String?;
        expect(value, isNotNull, reason: 'Ключ $key отсутствует в ru');
        expect(value, contains('plural'), reason: '$key должен быть plural');
        expect(value, contains('few{'), reason: '$key: нет формы few');
        expect(value, contains('many{'), reason: '$key: нет формы many');
      }
    });

    // AC:RL-auth-otp-resend-timer-mmss/4
    test('плейсхолдеры в ru совпадают с en', () {
      // Шаблон — intl_en.arb: только его `@`-метаданные читает gen-l10n.
      // Переименованный в en плейсхолдер ({seconds} → {time}) при старом
      // имени в ru не падает на сборке — строка молча выводит «{seconds}»
      // как текст. CI-гейта на это нет.
      final en = _loadArb('en');
      // `{name}` или `{name,` (ICU plural/select); тела форм вроде
      // `=1{1 File}` содержат пробел и под шаблон не попадают.
      final placeholder = RegExp(r'\{([A-Za-z0-9_]+)[},]');
      final offenders = <String>[];

      en.forEach((key, value) {
        if (key.startsWith('@') || value is! String) return;
        final ruValue = ru[key];
        if (ruValue is! String) return;
        final enNames = placeholder.allMatches(value).map((m) => m[1]).toSet();
        final ruNames = placeholder
            .allMatches(ruValue)
            .map((m) => m[1])
            .toSet();
        if (enNames.isEmpty && ruNames.isEmpty) return;
        if (!ruNames.containsAll(enNames) || !enNames.containsAll(ruNames)) {
          offenders.add('$key: en=$enNames ru=$ruNames');
        }
      });

      expect(
        offenders,
        isEmpty,
        reason:
            'Набор плейсхолдеров в ru отличается от en:\n'
            '${offenders.join('\n')}',
      );
    });

    test('demoAuthResendIn принимает готовое время, а не секунды', () {
      final en = _loadArb('en');
      for (final arb in {'en': en, 'ru': ru}.entries) {
        final text = arb.value['demoAuthResendIn'] as String;
        expect(text, contains('{time}'), reason: '${arb.key}: нет {time}');
        expect(
          text,
          isNot(contains('{seconds}')),
          reason: '${arb.key}: сырые секунды в таймере (LABA-2526)',
        );
      }
      final meta = en['@demoAuthResendIn'] as Map<String, dynamic>;
      final placeholders = meta['placeholders'] as Map<String, dynamic>;
      expect(placeholders.keys, ['time']);
      expect((placeholders['time'] as Map)['type'], 'String');
    });
  });
}
