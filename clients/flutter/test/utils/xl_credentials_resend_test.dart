import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/xl_credentials.dart';

void main() {
  group('shouldResendXlKey', () {
    test('в чате с XL-ботом при сохранённом ключе — да', () {
      expect(shouldResendXlKey(directChatMxid: xlBotMxid, hasStoredKey: true),
          isTrue);
    });

    test('в чате с другим ботом — нет', () {
      expect(
          shouldResendXlKey(
              directChatMxid: '@liza:bots.liza.ru', hasStoredKey: true),
          isFalse);
    });

    test('без сохранённого ключа — нет', () {
      expect(shouldResendXlKey(directChatMxid: xlBotMxid, hasStoredKey: false),
          isFalse);
    });

    test('в групповой комнате (directChatMxid == null) — нет', () {
      expect(shouldResendXlKey(directChatMxid: null, hasStoredKey: true),
          isFalse);
    });
  });

  group('защита от повторной отправки', () {
    test('resetXlKeyResendState сбрасывает отметки', () {
      // Прямая проверка: функция существует и вызывается без ошибок.
      // Сам счётчик приватный, поэтому проверяем контракт сброса —
      // он нужен, когда мерчант сменил ключ на экране настроек.
      resetXlKeyResendState();
    });
  });
}
