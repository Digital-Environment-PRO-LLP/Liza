import 'package:flutter_test/flutter_test.dart';
import 'package:liza/config/app_config.dart';

// Страж РЕГРЕССИИ ledger:RL-liza-bot-api-base-per-homeserver.
// Панель BotFather должна ходить на Liza Bot API, СОВПАДАЮЩИЙ с homeserver'ом
// комнаты (в одном приложении бывают local и prod аккаунты). Иначе prod-токен
// уходит в локальный бот → 401 (регресс, чинился в 5a37af6e).
void main() {
  group(
    'AppConfig.lizaBotApiBaseForHomeserver [ledger:RL-liza-bot-api-base-per-homeserver]',
    () {
      test('локальные хосты → локальный порт', () {
        expect(
          AppConfig.lizaBotApiBaseForHomeserver('synapse.liza.local'),
          'http://localhost:9997',
        );
        expect(
          AppConfig.lizaBotApiBaseForHomeserver('liza.local'),
          'http://localhost:9997',
        );
        expect(
          AppConfig.lizaBotApiBaseForHomeserver('localhost'),
          'http://localhost:9997',
        );
        expect(
          AppConfig.lizaBotApiBaseForHomeserver('127.0.0.1'),
          'http://localhost:9997',
        );
      });

      test('prod/компанейские хосты → prod-хост', () {
        expect(
          AppConfig.lizaBotApiBaseForHomeserver(
            'synapse.liza.laba.prodamus.tech',
          ),
          'https://bot.tech.liza.ru',
        );
        expect(
          AppConfig.lizaBotApiBaseForHomeserver('nadezhda.liza.ru'),
          'https://bot.tech.liza.ru',
        );
      });

      test('null → prod-хост (безопасный дефолт)', () {
        expect(
          AppConfig.lizaBotApiBaseForHomeserver(null),
          'https://bot.tech.liza.ru',
        );
      });
    },
  );
}
