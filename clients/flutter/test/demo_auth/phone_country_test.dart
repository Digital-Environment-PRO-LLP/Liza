import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/phone_country.dart';

void main() {
  group('phoneCountryFromLocale', () {
    test('регион из локали даёт свой код страны', () {
      expect(phoneCountryFromLocale(const Locale('hy', 'AM')).prefix, '+374');
      expect(phoneCountryFromLocale(const Locale('en', 'US')).prefix, '+1');
    });

    test('регион неизвестен — остаётся страна по умолчанию', () {
      expect(phoneCountryFromLocale(const Locale('en')).isoCode, 'RU');
      expect(phoneCountryFromLocale(const Locale('en', 'ZZ')).isoCode, 'RU');
    });
  });

  group('normalizeToE164', () {
    test('российский номер с разделителями', () {
      expect(normalizeToE164('+7 (999) 123-45-67'), '+79991234567');
    });

    test('иностранный номер больше не отвергается', () {
      // Ровно этого не умел прежний экран: длина была зашита в 10 цифр.
      expect(normalizeToE164('+995 555 12-34-56'), '+995555123456');
      expect(normalizeToE164('+1 201 555-0123'), '+12015550123');
    });

    test('слишком короткий и слишком длинный — не номер', () {
      expect(normalizeToE164('+7 999'), isNull);
      expect(normalizeToE164('+7999123456789012'), isNull);
      expect(normalizeToE164(''), isNull);
    });
  });
}
