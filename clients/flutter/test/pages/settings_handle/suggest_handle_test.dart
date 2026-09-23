import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/settings_handle/settings_handle.dart';

void main() {
  group('suggestHandleFromLocalpart', () {
    test('кандидат предлагается заменой точки на подчёркивание', () {
      expect(
        suggestHandleFromLocalpart('ivan.petrov'),
        'ivan_petrov',
      );
    });

    test('ведущий @ отбрасывается', () {
      expect(
        suggestHandleFromLocalpart('@ivan.petrov'),
        'ivan_petrov',
      );
    });

    test('без точки — кандидата нет', () {
      expect(suggestHandleFromLocalpart('ivanpetrov'), isNull);
    });

    test('кандидат слишком короткий после замены — не предлагаем', () {
      expect(suggestHandleFromLocalpart('a.b'), isNull);
    });
  });
}
