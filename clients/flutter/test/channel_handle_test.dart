import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/channel_handle.dart';

// Страж реестра регрессии: ledger:RL-channel-handle (см. tests/registry/).
// Правила ника здесь — зеркало серверных из
// servers/auth-proxy/app/invites/handle_validator.py. Расхождение даёт
// молчаливый баг: клиент пропускает ник, который сервер отвергнет (или
// наоборот), и пользователь видит необъяснимую ошибку сохранения.
void main() {
  group('validateChannelHandle', () {
    test('принимает минимально короткий валидный ник — ledger:RL-channel-handle',
        () {
      expect(validateChannelHandle('rozen'), null);
    });

    test('принимает цифры и подчёркивание', () {
      expect(validateChannelHandle('rozental_2026'), null);
    });

    test('нормализует регистр перед проверкой', () {
      expect(validateChannelHandle('RoZental'), null);
    });

    test('отвергает слишком короткий', () {
      expect(validateChannelHandle('abcd'), ChannelHandleError.tooShort);
    });

    test('отвергает слишком длинный', () {
      expect(validateChannelHandle('a' * 33), ChannelHandleError.tooLong);
    });

    test('принимает максимальную длину', () {
      expect(validateChannelHandle('a' * 32), null);
    });

    test('отвергает кириллицу', () {
      expect(validateChannelHandle('розенталь'), ChannelHandleError.badFormat);
    });

    test('отвергает ведущую цифру', () {
      expect(validateChannelHandle('2rozental'), ChannelHandleError.badFormat);
    });

    test('отвергает решётку', () {
      expect(validateChannelHandle('#rozental'), ChannelHandleError.badFormat);
    });

    test('отвергает резервные слова', () {
      for (final word in ['admin', 'api', 'support', 'help', 'liza']) {
        expect(validateChannelHandle(word), ChannelHandleError.reserved,
            reason: word);
      }
    });
  });

  group('channelHandleUrl', () {
    test('собирает URL с префиксом /c/', () {
      expect(
        channelHandleUrl('rozental', landingBase: 'https://me.liza.ru'),
        'https://me.liza.ru/c/rozental',
      );
    });

    test('не сдваивает слэш при базе со слэшем', () {
      expect(
        channelHandleUrl('rozental', landingBase: 'https://me.liza.ru/'),
        'https://me.liza.ru/c/rozental',
      );
    });
  });

  group('suggestHandleFrom', () {
    test('транслитерирует кириллицу', () {
      expect(suggestHandleFrom('Розенталь'), 'rozental');
    });

    test('заменяет пробелы подчёркиванием', () {
      expect(suggestHandleFrom('Публичный канал'), 'publichnyi_kanal');
    });

    test('выбрасывает недопустимые символы', () {
      expect(suggestHandleFrom('Канал!!! №1'), 'kanal_1');
    });

    test('обрезает по максимальной длине', () {
      expect(suggestHandleFrom('a' * 50).length, lessThanOrEqualTo(32));
    });

    test('пустое имя даёт пустую подсказку', () {
      expect(suggestHandleFrom(''), '');
    });
  });
}
