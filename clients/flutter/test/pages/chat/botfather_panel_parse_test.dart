import 'package:flutter_test/flutter_test.dart';
import 'package:liza/pages/chat/botfather_panel.dart';

// Страж РЕГРЕССИИ ledger:RL-botfather-panel-parse.
// Разбор ответа /liza/mybots для панели BotFather: пропуск ботов без строкового
// mxid, фолбэки имён, терпимость к отсутствию ключей.
void main() {
  group('parseMyBots [ledger:RL-botfather-panel-parse]', () {
    test('боты и приложения разбираются, username сохраняется', () {
      final (bots, apps) = parseMyBots({
        'bots': [
          {'mxid': '@bot-miniapp:hs', 'name': 'botMini', 'username': 'bot-miniapp'},
        ],
        'apps': [
          {'app_id': 'a1', 'name': 'Music', 'bot_mxid': '@bot-miniapp:hs', 'bot_name': 'botMini'},
        ],
      });
      expect(bots.single.mxid, '@bot-miniapp:hs');
      expect(bots.single.name, 'botMini');
      expect(bots.single.username, 'bot-miniapp');
      expect(apps.single.name, 'Music');
      expect(apps.single.botMxid, '@bot-miniapp:hs');
    });

    test('бот без строкового mxid пропускается', () {
      final (bots, _) = parseMyBots({
        'bots': [
          {'name': 'no-mxid'},
          {'mxid': 42},
          {'mxid': '@ok:hs', 'name': 'ok'},
        ],
      });
      expect(bots.map((b) => b.mxid), ['@ok:hs']);
    });

    test('имя-фолбэк: bot.name→mxid, app.name→app_id', () {
      final (bots, apps) = parseMyBots({
        'bots': [
          {'mxid': '@x:hs', 'name': '  '},
        ],
        'apps': [
          {'app_id': 'appX'},
        ],
      });
      expect(bots.single.name, '@x:hs');
      expect(apps.single.name, 'appX');
    });

    test('отсутствие ключей bots/apps → пустые списки', () {
      final (bots, apps) = parseMyBots({});
      expect(bots, isEmpty);
      expect(apps, isEmpty);
    });

    test('app: url/id/type/start_path пробрасываются для экрана деталей', () {
      final (_, apps) = parseMyBots({
        'apps': [
          {
            'app_id': 'app_42',
            'name': 'Shop',
            'app_url': 'https://shop.example/',
            'app_type': 'first_party',
            'app_start_path': '/promo',
          },
        ],
      });
      final a = apps.single;
      expect(a.appId, 'app_42');
      expect(a.appUrl, 'https://shop.example/');
      expect(a.appType, 'first_party');
      expect(a.startPath, '/promo');
    });

    test('app без url → appUrl=null, type-фолбэк third_party (кнопка «Открыть» недоступна)', () {
      final (_, apps) = parseMyBots({
        'apps': [
          {'app_id': 'app_1', 'name': 'NoUrl', 'app_url': '  '},
        ],
      });
      expect(apps.single.appUrl, isNull);
      expect(apps.single.appType, 'third_party');
      expect(apps.single.startPath, '');
    });
  });
}
