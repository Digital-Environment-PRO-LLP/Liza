import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/phone_country.dart';
import 'package:liza/utils/phone_input_formatter.dart';

/// Прогоняет строку через форматтер посимвольно — так, как её набирает
/// человек: каждый символ дописывается в конец, каретка идёт следом.
TextEditingValue _typeAll(PhoneInputFormatter mask, String input) {
  var value = TextEditingValue.empty;
  for (final char in input.split('')) {
    final caret = value.selection.baseOffset.clamp(0, value.text.length);
    final next = value.text.substring(0, caret) +
        char +
        value.text.substring(caret);
    value = mask.formatEditUpdate(
      value,
      TextEditingValue(
        text: next,
        selection: TextSelection.collapsed(offset: caret + 1),
      ),
    );
  }
  return value;
}

/// Вставка из буфера: всё содержимое приезжает ОДНИМ изменением, каретка —
/// в конец вставленного. Именно этот путь ломала прежняя попытка маски.
TextEditingValue _paste(
  PhoneInputFormatter mask,
  String pasted, {
  TextEditingValue? into,
}) {
  final old = into ?? TextEditingValue.empty;
  final caret = old.selection.baseOffset.clamp(0, old.text.length);
  final next =
      old.text.substring(0, caret) + pasted + old.text.substring(caret);
  return mask.formatEditUpdate(
    old,
    TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret + pasted.length),
    ),
  );
}

/// Backspace: удаляет символ слева от каретки — какой бы он ни был.
TextEditingValue _backspace(PhoneInputFormatter mask, TextEditingValue value) {
  final caret = value.selection.baseOffset;
  if (caret <= 0) return value;
  final next =
      value.text.substring(0, caret - 1) + value.text.substring(caret);
  return mask.formatEditUpdate(
    value,
    TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: caret - 1),
    ),
  );
}

void main() {
  group('PhoneInputFormatter — раскладка по странам', () {
    test('российский номер разбивается по формату страны', () {
      final mask = PhoneInputFormatter();
      expect(_typeAll(mask, '+79151234567').text, '+7 915 123-45-67');
    });

    test('американский номер — скобки и дефис, а не российская раскладка', () {
      final mask = PhoneInputFormatter(
        country: phoneCountryByIso('US')!,
      );
      expect(_typeAll(mask, '+12015550123').text, '+1 (201) 555-0123');
    });

    test('немецкий номер длиннее российского и не обрезается', () {
      final mask = PhoneInputFormatter(country: phoneCountryByIso('DE')!);
      final value = _typeAll(mask, '+4915112345678');
      expect(value.text, startsWith('+49 '));
      expect(_digits(value.text), '4915112345678');
    });

    test('французский номер — группы по две цифры', () {
      final mask = PhoneInputFormatter(country: phoneCountryByIso('FR')!);
      expect(_typeAll(mask, '+33612345678').text, '+33 6 12 34 56 78');
    });

    test('страна следует за набранным кодом, а не за начальной установкой',
        () {
      // Маска создана «российской», но человек стёр код и набрал британский.
      final mask = PhoneInputFormatter();
      mask.country = phoneCountryByDialPrefix('+44')!;
      expect(_typeAll(mask, '+447400123456').text, '+44 7400 123456');
    });

    test('неизвестный код страны не ломает ввод — цифры идут как есть', () {
      final mask = PhoneInputFormatter();
      // +599 (Кюрасао) в справочнике kPhoneCountries отсутствует.
      final value = _typeAll(mask, '+5991234567');
      expect(_digits(value.text), '5991234567');
    });
  });

  group('PhoneInputFormatter — вставка из буфера', () {
    test('номер в E.164 вставляется целиком и раскладывается', () {
      final mask = PhoneInputFormatter();
      final value = _paste(mask, '+79151234567');
      expect(value.text, '+7 915 123-45-67');
      expect(value.selection.baseOffset, value.text.length);
    });

    test('вставка уже форматированного номера не задваивает разделители', () {
      final mask = PhoneInputFormatter();
      expect(_paste(mask, '+7 (915) 123-45-67').text, '+7 915 123-45-67');
    });

    test('вставка с пробелами и скобками из адресной книги', () {
      final mask = PhoneInputFormatter(country: phoneCountryByIso('US')!);
      expect(_paste(mask, '+1 201 555 0123').text, '+1 (201) 555-0123');
    });

    test('вставка национальной части поверх подставленного кода страны', () {
      final mask = PhoneInputFormatter();
      // Поле уже содержит «+7 » (автоподстановка), человек вставляет остаток.
      final prefilled = _typeAll(mask, '+7');
      final value = _paste(mask, '9151234567', into: prefilled);
      expect(value.text, '+7 915 123-45-67');
    });

    test('вставка не теряет ни одной цифры длинного иностранного номера', () {
      final mask = PhoneInputFormatter(country: phoneCountryByIso('IN')!);
      final value = _paste(mask, '+918123456789');
      expect(_digits(value.text), '918123456789');
    });
  });

  // ledger:RL-login-phone-input-max-digits
  // AC:RL-login-phone-input-max-digits/1 AC:RL-login-phone-input-max-digits/2
  // AC:RL-login-phone-input-max-digits/3 AC:RL-login-phone-input-max-digits/4
  // AC:RL-login-phone-input-max-digits/5 AC:RL-login-phone-input-max-digits/6
  group('PhoneInputFormatter — не больше kPhoneMaxDigits цифр (LABA-2524)', () {
    String digitsOf(int count) =>
        List.generate(count, (i) => '${(i + 1) % 10}').join();

    test('AC-1: цифра сверх лимита не набирается — RU, DE, неизвестный код',
        () {
      for (final (iso, typed) in const [
        ('RU', '+79151234567890123'),
        ('DE', '+491511234567890123'),
        ('RU', '+59912345678901234'),
      ]) {
        final mask = PhoneInputFormatter(country: phoneCountryByIso(iso)!);
        final value = _typeAll(mask, typed);
        final expected = _digits(typed).substring(0, kPhoneMaxDigits);
        expect(_digits(value.text), expected, reason: typed);
      }
    });

    test('AC-2: слишком длинная вставка отклоняется целиком, а не режется', () {
      const prefilled = TextEditingValue(
        text: '+7 ',
        selection: TextSelection.collapsed(offset: 3),
      );
      for (final count in const [16, 20, 24]) {
        final long = digitsOf(count);
        expect(
          _paste(PhoneInputFormatter(), long),
          TextEditingValue.empty,
          reason: 'пустое поле, $count цифр',
        );
        expect(
          _paste(PhoneInputFormatter(), '+$long', into: prefilled),
          prefilled,
          reason: 'поверх «+7 », $count цифр с плюсом',
        );
        expect(
          _paste(PhoneInputFormatter(), long, into: prefilled),
          prefilled,
          reason: 'поверх «+7 », $count цифр без плюса',
        );
      }
    });

    test('AC-3: всё, что принимает normalizeToE164, маска тоже принимает', () {
      const accepted = [
        // RL-login-phone-invalid-inline AC-5.
        '+4512345678', '+4930901820', '+375251234567', '+972581234567',
        '+972501234567', '+7 (999) 123-45-67', '+995 555 12-34-56',
        '+1 201 555-0123',
        // RL-login-phone-invalid-inline AC-6 — национальные формы.
        '+7 891 512 345 67', '+7 880 055 535 35', '89151234567',
        '9151234567', '007 999 123 45 67',
        // `00` не входит в лимит: 16 и 17 цифр в поле, 14 и 15 значимых.
        '0044 7911 123456', '00491511234567890',
        // Ровно на границе.
        '+491511234567890',
      ];
      for (final input in accepted) {
        final e164 = normalizeToE164(input);
        expect(e164, isNotNull, reason: 'список обязан быть валиден: $input');
        final value = _paste(PhoneInputFormatter(), input);
        expect(_digits(value.text), _digits(input), reason: input);
        expect(normalizeToE164(value.text), e164, reason: input);
      }
    });

    test('AC-4: граница — ровно kPhoneMaxDigits, а не литерал', () {
      final atLimit = digitsOf(kPhoneMaxDigits);
      final overLimit = digitsOf(kPhoneMaxDigits + 1);
      expect(_digits(_paste(PhoneInputFormatter(), '+$atLimit').text), atLimit);
      expect(
        _paste(PhoneInputFormatter(), '+$overLimit'),
        TextEditingValue.empty,
      );
    });

    test('AC-5: на лимите backspace работает, после него цифра набирается',
        () {
      final mask = PhoneInputFormatter();
      final full = _typeAll(mask, '+791512345678901');
      expect(_digits(full.text), hasLength(kPhoneMaxDigits));

      final shorter = _backspace(mask, full);
      expect(_digits(shorter.text), '79151234567890');

      final retyped = mask.formatEditUpdate(
        shorter,
        TextEditingValue(
          text: '${shorter.text}9',
          selection: TextSelection.collapsed(offset: shorter.text.length + 1),
        ),
      );
      expect(_digits(retyped.text), '791512345678909');

      // Backspace по разделителю тоже проходит на полном номере.
      final separator = full.text.lastIndexOf(RegExp(r'[\s\-]'));
      final afterSeparator = _backspace(
        mask,
        full.copyWith(selection: TextSelection.collapsed(offset: separator + 1)),
      );
      expect(_digits(afterSeparator.text), hasLength(kPhoneMaxDigits - 1));
    });

    test('AC-6: плюс перед 17-значной 00-формой не проходит', () {
      final mask = PhoneInputFormatter();
      final zeros = _paste(mask, '00491511234567890');
      expect(_digits(zeros.text), hasLength(kPhoneMaxDigits + 2));

      final withPlus = mask.formatEditUpdate(
        zeros,
        TextEditingValue(
          text: '+${zeros.text}',
          selection: const TextSelection.collapsed(offset: 1),
        ),
      );
      expect(withPlus, zeros);
    });
  });

  // ledger:RL-login-phone-input-max-digits
  // AC:RL-login-phone-input-max-digits/7 AC:RL-login-phone-input-max-digits/8
  // AC:RL-login-phone-input-max-digits/9
  group('PhoneInputFormatter — вставка поверх подставленного кода', () {
    const prefilledEnd = TextEditingValue(
      text: '+7 ',
      selection: TextSelection.collapsed(offset: 3),
    );
    const prefilledStart = TextEditingValue(
      text: '+7 ',
      selection: TextSelection.collapsed(offset: 0),
    );

    test('AC-7: номер с плюсом заменяет «+7 », а не приклеивается к нему', () {
      for (final into in const [prefilledEnd, prefilledStart]) {
        for (final (pasted, e164) in const [
          ('+79151234567', '+79151234567'),
          ('+7 915 123-45-67', '+79151234567'),
          ('+49 151 12345678', '+4915112345678'),
          ('+86 131 2345 6789', '+8613123456789'),
          ('+491511234567890', '+491511234567890'),
        ]) {
          final value = _paste(PhoneInputFormatter(), pasted, into: into);
          final where = 'каретка ${into.selection.baseOffset}: $pasted';
          expect(normalizeToE164(value.text), e164, reason: where);
          expect(value.selection.baseOffset, value.text.length, reason: where);
        }
      }
      final german =
          _paste(PhoneInputFormatter(), '+49 151 12345678', into: prefilledEnd);
      expect(german.text, startsWith('+49 '));
    });

    test('AC-8: национальная часть поверх «+7 » по-прежнему дописывается', () {
      for (final pasted in const ['9151234567', '8 915 123-45-67']) {
        final value = _paste(PhoneInputFormatter(), pasted, into: prefilledEnd);
        expect(normalizeToE164(value.text), '+79151234567', reason: pasted);
      }
    });

    test('AC-9: плюс посреди начатого номера не стирает набранное', () {
      final mask = PhoneInputFormatter();
      final started = _typeAll(mask, '+791512');
      final value = mask.formatEditUpdate(
        started,
        TextEditingValue(
          text: '${started.text}+',
          selection: TextSelection.collapsed(offset: started.text.length + 1),
        ),
      );
      expect(value.text, started.text);

      // Одиночный «+» сразу за подставленным «+7 » — нажатие клавиши, а не
      // вставка номера: код страны остаётся на месте.
      for (final into in const [prefilledEnd, prefilledStart]) {
        final caret = into.selection.baseOffset;
        final typed = PhoneInputFormatter().formatEditUpdate(
          into,
          TextEditingValue(
            text: '${into.text.substring(0, caret)}+${into.text.substring(caret)}',
            selection: TextSelection.collapsed(offset: caret + 1),
          ),
        );
        expect(_digits(typed.text), '7', reason: 'каретка $caret');
      }
    });

    test('автозаполнение целым значением идёт обычным путём', () {
      final value = PhoneInputFormatter().formatEditUpdate(
        prefilledEnd,
        const TextEditingValue(
          text: '+79151234567',
          selection: TextSelection.collapsed(offset: 12),
        ),
      );
      expect(value.text, '+7 915 123-45-67');
    });
  });

  group('PhoneInputFormatter — backspace', () {
    test('удаляет цифру, а не только разделитель', () {
      final mask = PhoneInputFormatter();
      var value = _typeAll(mask, '+79151234567');
      expect(value.text, '+7 915 123-45-67');

      value = _backspace(mask, value);
      expect(_digits(value.text), '791512345 6'.replaceAll(' ', ''));
      expect(value.text, '+7 915 123-45-6');
    });

    test('backspace по разделителю стирает цифру слева, а не залипает', () {
      final mask = PhoneInputFormatter();
      // «+7 915 123-45-67», каретка сразу после дефиса перед «45».
      var value = _typeAll(mask, '+79151234567');
      final dashOffset = value.text.indexOf('-') + 1;
      value = TextEditingValue(
        text: value.text,
        selection: TextSelection.collapsed(offset: dashOffset),
      );

      final after = _backspace(mask, value);
      // Стёрлась цифра «3» — последняя перед дефисом.
      expect(_digits(after.text), '791512' '4567');
      expect(after.text, '+7 915 124-56-7');
    });

    test('повторный backspace очищает поле до плюса и не зацикливается', () {
      final mask = PhoneInputFormatter();
      var value = _typeAll(mask, '+79151234567');
      for (var i = 0; i < 40; i++) {
        value = _backspace(mask, value);
      }
      expect(_digits(value.text), isEmpty);
    });

    test('удаление из середины сдвигает хвост, а не рвёт номер', () {
      final mask = PhoneInputFormatter();
      var value = _typeAll(mask, '+79151234567');
      // Каретка после «915» (4 цифры набрано: 7,9,1,5).
      value = TextEditingValue(
        text: value.text,
        selection: TextSelection.collapsed(
          offset: value.text.indexOf('5') + 1,
        ),
      );
      final after = _backspace(mask, value);
      expect(_digits(after.text), '791' '1234567');
    });
  });

  group('PhoneInputFormatter — наружу уходит корректный E.164', () {
    test('отформатированный российский номер нормализуется обратно', () {
      final mask = PhoneInputFormatter();
      final value = _typeAll(mask, '+79151234567');
      expect(normalizeToE164(value.text), '+79151234567');
    });

    test('американский — скобки не мешают нормализации', () {
      final mask = PhoneInputFormatter(country: phoneCountryByIso('US')!);
      final value = _typeAll(mask, '+12015550123');
      expect(normalizeToE164(value.text), '+12015550123');
    });

    test('вставленный номер даёт тот же E.164, что и набранный вручную', () {
      final typed = _typeAll(PhoneInputFormatter(), '+79151234567');
      final pasted = _paste(PhoneInputFormatter(), '+7 (915) 123-45-67');
      expect(
        normalizeToE164(pasted.text),
        normalizeToE164(typed.text),
      );
      expect(normalizeToE164(pasted.text), '+79151234567');
    });

    test('неполный номер в E.164 не превращается', () {
      final mask = PhoneInputFormatter();
      final value = _typeAll(mask, '+7915');
      expect(normalizeToE164(value.text), isNull);
    });
  });

  group('phoneCountryByDialPrefix', () {
    test('длинный код побеждает короткий', () {
      expect(phoneCountryByDialPrefix('+375291234567')?.isoCode, 'BY');
      expect(phoneCountryByDialPrefix('+380501234567')?.isoCode, 'UA');
    });

    test('код-двойник разрешается первым в справочнике', () {
      expect(phoneCountryByDialPrefix('+79151234567')?.isoCode, 'RU');
      expect(phoneCountryByDialPrefix('+12015550123')?.isoCode, 'US');
    });

    test('пустая строка и код вне справочника дают null', () {
      expect(phoneCountryByDialPrefix(''), isNull);
      expect(phoneCountryByDialPrefix('+599'), isNull);
    });
  });
}

String _digits(String raw) => raw.replaceAll(RegExp(r'\D'), '');
