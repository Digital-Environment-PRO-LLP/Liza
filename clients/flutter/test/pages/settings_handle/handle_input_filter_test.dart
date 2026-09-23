// Поле ника не принимает символы, которых нет в формате ника.
//
// Выстрадано: слева от поля стоит декоративный «@» (prefixText), и человек,
// видя его, печатает собачку сам. Значение становилось «@asdasd», не
// проходило валидацию («начиная с буквы») и выглядело необъяснимым отказом:
// на экране ник смотрится правильным.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/settings_handle/settings_handle.dart';

/// Тот же фильтр, что стоит на поле в settings_handle_view.dart.
final _formatter =
    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]'));

String _type(String raw) => _formatter
    .formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(
        text: raw,
        selection: TextSelection.collapsed(offset: raw.length),
      ),
    )
    .text;

void main() {
  group('фильтр ввода ника', () {
    test('собачка отсекается — главный сценарий отказа', () {
      expect(_type('@asdasd'), 'asdasd');
    });

    test('допустимые символы проходят целиком', () {
      expect(_type('ivan_petrov_99'), 'ivan_petrov_99');
    });

    test('кириллица не проходит', () {
      expect(_type('иван'), '');
    });

    test('пробелы и точки отсекаются', () {
      expect(_type('ivan.petrov ok'), 'ivanpetrovok');
    });

    test('верхний регистр сохраняется (нормализует сервер)', () {
      expect(_type('Ivanov'), 'Ivanov');
    });
  });

  group('sanitizeHandleInput — граница сохранения', () {
    test('сигил срезается', () {
      expect(sanitizeHandleInput('@asdasd'), 'asdasd');
    });

    test('целый MXID превращается в localpart', () {
      expect(
        sanitizeHandleInput('@test_furman_8282:bots.liza.ru'),
        'test_furman_8282',
      );
    });

    test('пробелы по краям убираются', () {
      expect(sanitizeHandleInput('  ivanov  '), 'ivanov');
    });

    test('уже чистый ник не меняется', () {
      expect(sanitizeHandleInput('ivan_petrov'), 'ivan_petrov');
    });
  });
}

// Очистка на границе сохранения — страховка поверх фильтра ввода.
// Значение может прийти в поле не только с клавиатуры: подстановка при
// открытии экрана, вставка из буфера, автозаполнение браузера. Фильтр
// ловит ручной ввод, sanitize — всё остальное.
