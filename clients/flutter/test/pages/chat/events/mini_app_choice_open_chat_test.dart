import 'package:flutter_test/flutter_test.dart';

// Тестируем чистые хелперы парсинга кнопки. Если _MiniAppButton/_isEnabled
// приватны — вынеси проверку валидности mxid в top-level функцию
// isValidMatrixUserId(String?) в том же файле и тестируй её.
import 'package:liza/pages/chat/events/mini_app_choice_content.dart';

void main() {
  test('mxid вида @bot:server валиден', () {
    expect(isValidMatrixUserId('@botfather:example.test'), isTrue);
  });
  test('пустой и кривой mxid невалиден', () {
    expect(isValidMatrixUserId(null), isFalse);
    expect(isValidMatrixUserId('botfather'), isFalse);
    expect(isValidMatrixUserId('@noserver'), isFalse);
  });
}
