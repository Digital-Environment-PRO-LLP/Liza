import 'package:flutter/services.dart';

import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import 'package:liza/utils/phone_country.dart';

/// Живое форматирование телефона по ходу ввода.
///
/// Раскладка национальной части берётся из `phone_numbers_parser` — это
/// чистый Dart (единственная зависимость — `meta`), метаданные libphonenumber
/// лежат константами прямо в пакете. Нативных биндингов нет, поэтому web-сборка
/// работает так же, как мобильная, — ровно то, чего не давал сам libphonenumber
/// (см. отказ от него в [PhoneCountry]).
///
/// ## Почему форматирование не ломает вставку и backspace
///
/// Прошлая попытка правила текст «на лету» (дописывала разделители после
/// последнего введённого символа) и потому зависела от того, КАК он появился:
/// вставка целого номера из буфера и удаление разделителя backspace ломали
/// каретку. Здесь другой принцип — форматтер не редактирует правку, а
/// пересобирает поле целиком:
///
/// 1. из нового значения берутся ТОЛЬКО цифры (плюс — отдельным флагом);
/// 2. они заново раскладываются по маске страны;
/// 3. каретка ставится после того же ПО СЧЁТУ разделителя-независимого
///    символа (цифры), что и до форматирования.
///
/// Из этого следует и корректный backspace: удаление разделителя само по себе
/// ничего не меняет (разделители — производные), поэтому перед пересборкой
/// стирается ближайшая цифра слева. Иначе курсор «залипал» бы на скобке.
class PhoneInputFormatter extends TextInputFormatter {
  PhoneInputFormatter({PhoneCountry? country})
      : country = country ?? kDefaultPhoneCountry;

  /// Страна меняется, когда её уточнил резолвер по IP или человек набрал
  /// другой код: маска обязана следовать за кодом, а не за первым выбором.
  PhoneCountry country;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final oldDigits = _digitsOf(oldValue.text);
    final isDeletion = newValue.text.length < oldValue.text.length;

    final replacement = _replacingAutoPrefix(oldValue, newValue, oldDigits);
    if (replacement != null) newValue = replacement;
    var digits = _digitsOf(newValue.text);

    // Backspace по разделителю: цифр не убавилось, значит человек стёр скобку
    // или дефис. Сами по себе они ничего не значат — форматтер вернул бы их
    // на место, и клавиша выглядела бы сломанной. Стираем цифру слева.
    if (replacement == null &&
        isDeletion &&
        digits.length == oldDigits.length &&
        digits.isNotEmpty) {
      final caret = newValue.selection.baseOffset;
      final digitsBefore = _digitsOf(
        newValue.text.substring(0, caret.clamp(0, newValue.text.length)),
      ).length;
      if (digitsBefore > 0) {
        digits = digits.substring(0, digitsBefore - 1) +
            digits.substring(digitsBefore);
      }
    }

    // Ведущий плюс: человек может стереть код страны и вписать свой, поэтому
    // плюс не прибит гвоздями. Плюс в середине номера игнорируется — кроме
    // вставки поверх одного лишь кода страны (см. [_replacingAutoPrefix]).
    final hasPlus = newValue.text.trimLeft().startsWith('+') ||
        (newValue.text.isEmpty && oldValue.text.startsWith('+'));

    // Больше kPhoneMaxDigits цифр номер не станет: сервер и Keycloak его
    // отвергнут. Правка отклоняется ЦЕЛИКОМ, а не обрезается — обрезанная
    // вставка превратилась бы в правдоподобный чужой номер (LABA-2524).
    // `00` без плюса — международный префикс набора, `normalizeToE164` его
    // снимает, поэтому эти две цифры в лимит не входят. Условие «цифр не
    // убавилось», а не «прибавилось»: плюс, дописанный к 17-значной
    // `00`-форме, цифр не добавляет, но лимит опускает до 15.
    final cap =
        kPhoneMaxDigits + (!hasPlus && digits.startsWith('00') ? 2 : 0);
    if (digits.length > cap && digits.length >= oldDigits.length) {
      return oldValue;
    }

    // Каретка считается в цифрах: разделители подвижны, цифры — нет.
    final rawCaret = newValue.selection.baseOffset;
    final digitsBeforeCaret = rawCaret < 0
        ? digits.length
        : _digitsOf(newValue.text.substring(0, rawCaret.clamp(0, newValue.text.length)))
            .length
            .clamp(0, digits.length);

    final formatted = _format(digits, hasPlus: hasPlus);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: _offsetAfterDigits(formatted, digitsBeforeCaret),
      ),
    );
  }

  /// Вставка номера с `+` в поле, где стоит ТОЛЬКО подставленный код страны,
  /// заменяет этот код, а не приклеивается к нему.
  ///
  /// Поле предзаполнено «+7 », и человек вставляет из контактов свой же номер
  /// «+79151234567». Без замены выходило `+779151234567`: `normalizeToE164`
  /// его принимал (код 7, длина в диапазоне), и СМС уходило в никуда без
  /// единой ошибки (LABA-2524). Правило намеренно узкое: плюс, набранный
  /// посреди уже начатого номера, по-прежнему ничего не стирает, а замену
  /// значения целиком (автозаполнение) оно не трогает вовсе.
  static TextEditingValue? _replacingAutoPrefix(
    TextEditingValue oldValue,
    TextEditingValue newValue,
    String oldDigits,
  ) {
    final old = oldValue.text;
    if (!old.trimLeft().startsWith('+') || oldDigits.isEmpty) return null;
    if (phoneCountryByDialPrefix(oldDigits)?.dialCode != oldDigits) return null;

    final selection = oldValue.selection;
    if (!selection.isValid) return null;
    final start = selection.start.clamp(0, old.length);
    final end = selection.end.clamp(start, old.length);
    final before = old.substring(0, start);
    final after = old.substring(end);
    final text = newValue.text;
    if (text.length < before.length + after.length ||
        !text.startsWith(before) ||
        !text.endsWith(after)) {
      return null;
    }
    final fragment =
        text.substring(before.length, text.length - after.length);
    final plus = fragment.indexOf('+');
    if (plus < 0) return null;
    final pasted = fragment.substring(plus);
    // Одиночный набранный «+» — не номер: без цифр он стёр бы код страны,
    // хотя раньше просто игнорировался.
    if (_digitsOf(pasted).isEmpty) return null;
    return TextEditingValue(
      text: pasted,
      selection: TextSelection.collapsed(offset: pasted.length),
    );
  }

  /// Раскладывает цифры по маске: код страны + национальная часть.
  String _format(String digits, {required bool hasPlus}) {
    if (digits.isEmpty) return hasPlus ? '+' : '';

    final dial = _dialCodeOf(digits);
    if (dial == null) {
      // Код страны ещё не набран целиком (или он не из справочника) —
      // раскладывать нечего, показываем как есть.
      return hasPlus ? '+$digits' : digits;
    }

    final nsn = digits.substring(dial.dialCode.length);
    if (nsn.isEmpty) return '${hasPlus ? '+' : ''}${dial.dialCode}';

    final iso = _isoCodeOf(dial);
    final body = iso == null ? nsn : _formatNsn(nsn, iso);
    return '${hasPlus ? '+' : ''}${dial.dialCode} $body';
  }

  /// Национальная часть по метаданным страны.
  ///
  /// Пакет отдаёт номер без изменений, если он длиннее любого известного
  /// формата (человек ошибся или страна определена неверно) — тогда режем
  /// сами группами по 3, чтобы длинная строка цифр оставалась читаемой.
  String _formatNsn(String nsn, IsoCode iso) {
    final formatted = PhoneNumberFormatter.formatNsn(nsn, iso);
    if (formatted != nsn) return formatted;
    return _groupBy3(nsn);
  }

  static String _groupBy3(String digits) {
    if (digits.length <= 3) return digits;
    final parts = <String>[];
    for (var i = 0; i < digits.length; i += 3) {
      parts.add(
        digits.substring(i, (i + 3).clamp(0, digits.length)),
      );
    }
    return parts.join(' ');
  }

  /// Страна по началу номера. Текущая — в приоритете: её код мог совпасть с
  /// чужим (`+7` у России и Казахстана, `+1` у США и Канады), и уточнение по
  /// IP не должно теряться от того, что справочник вернёт соседа.
  PhoneCountry? _dialCodeOf(String digits) {
    if (digits.startsWith(country.dialCode)) return country;
    return phoneCountryByDialPrefix(digits);
  }

  static IsoCode? _isoCodeOf(PhoneCountry country) {
    for (final iso in IsoCode.values) {
      if (iso.name == country.isoCode) return iso;
    }
    return null;
  }

  static String _digitsOf(String raw) => raw.replaceAll(RegExp(r'\D'), '');

  /// Позиция в отформатированной строке сразу после [count]-й цифры.
  static int _offsetAfterDigits(String formatted, int count) {
    if (count <= 0) {
      // Перед первой цифрой, но за ведущим плюсом: вставать левее плюса
      // человеку незачем — оттуда всё равно ничего не набрать.
      return formatted.startsWith('+') ? 1 : 0;
    }
    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      if (_isDigit(formatted[i])) {
        seen++;
        if (seen == count) return i + 1;
      }
    }
    return formatted.length;
  }

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}
