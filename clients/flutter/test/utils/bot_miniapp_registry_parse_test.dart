import 'package:flutter_test/flutter_test.dart';
import 'package:liza/pages/chat/events/mini_app_choice_content.dart';
import 'package:liza/utils/bot_miniapp_registry.dart';

// Страж РЕГРЕССИИ ledger:RL-bot-miniapp-registry (+ ledger:RL-bot-miniapp-button-config).
// Разбор ответа /liza/mybots в карту botMxid → MiniAppLaunch: кнопки «Открыть»
// (список) и «Открыть» (композер) показываются ⇔ у бота есть валидный app_url;
// их видимость/название настраивает владелец через BotFather (button-config поля).
void main() {
  group('parseBotMiniApps [ledger:RL-bot-miniapp-registry]', () {
    test('app с bot_mxid и app_url попадает в карту по mxid бота', () {
      final map = parseBotMiniApps({
        'apps': [
          {
            'app_id': 'a1',
            'name': 'Магазин',
            'bot_mxid': '@shopbot:hs',
            'app_url': 'https://shop.example',
            'app_type': 'third_party',
            'app_start_path': '#!/tproduct/1',
          },
        ],
      });
      final launch = map['@shopbot:hs'];
      expect(launch, isNotNull);
      expect(launch!.appUrl, 'https://shop.example');
      expect(launch.appId, 'a1');
      expect(launch.appName, 'Магазин');
      expect(launch.appType, 'third_party');
      expect(launch.appStartPath, '#!/tproduct/1');
    });

    test('app без bot_mxid или без app_url пропускается (нет кнопки)', () {
      final map = parseBotMiniApps({
        'apps': [
          {'app_id': 'noBot', 'name': 'X', 'app_url': 'https://a'},
          {'app_id': 'noUrl', 'name': 'Y', 'bot_mxid': '@b:hs'},
          {'app_id': 'emptyUrl', 'bot_mxid': '@c:hs', 'app_url': ''},
        ],
      });
      expect(map, isEmpty);
    });

    test('несколько app у одного бота → берём первый (свежий, created_at DESC)', () {
      final map = parseBotMiniApps({
        'apps': [
          {'app_id': 'new', 'bot_mxid': '@b:hs', 'app_url': 'https://new'},
          {'app_id': 'old', 'bot_mxid': '@b:hs', 'app_url': 'https://old'},
        ],
      });
      expect(map['@b:hs']!.appUrl, 'https://new');
    });

    test('фолбэки: пустое имя→«Mini App», пустой тип→third_party', () {
      final map = parseBotMiniApps({
        'apps': [
          {'bot_mxid': '@b:hs', 'app_url': 'https://a', 'name': '  ', 'app_type': ''},
        ],
      });
      expect(map['@b:hs']!.appName, 'Mini App');
      expect(map['@b:hs']!.appType, 'third_party');
    });

    test('небезопасный app_start_path отбрасывается (→ главная)', () {
      final map = parseBotMiniApps({
        'apps': [
          {
            'bot_mxid': '@b:hs',
            'app_url': 'https://a',
            'app_start_path': 'javascript:alert(1)',
          },
        ],
      });
      expect(map['@b:hs']!.appStartPath, '');
    });

    test('button-config: по умолчанию обе кнопки включены, названия null', () {
      final launch = parseBotMiniApps({
        'apps': [
          {'bot_mxid': '@b:hs', 'app_url': 'https://a'},
        ],
      })['@b:hs']!;
      expect(launch.composerButtonEnabled, isTrue);
      expect(launch.listButtonEnabled, isTrue);
      expect(launch.composerButtonLabel, isNull);
      expect(launch.listButtonLabel, isNull);
    });

    test('button-config: enabled=false прячет кнопку, кастомный label читается', () {
      final launch = parseBotMiniApps({
        'apps': [
          {
            'bot_mxid': '@b:hs',
            'app_url': 'https://a',
            'composer_button_enabled': false,
            'composer_button_label': 'Магазин',
            'list_button_enabled': true,
            'list_button_label': 'Открыть магазин',
          },
        ],
      })['@b:hs']!;
      expect(launch.composerButtonEnabled, isFalse);
      expect(launch.composerButtonLabel, 'Магазин');
      expect(launch.listButtonEnabled, isTrue);
      expect(launch.listButtonLabel, 'Открыть магазин');
    });

    test('button-config: пустой/пробельный label → null (клиент даст дефолт)', () {
      final launch = parseBotMiniApps({
        'apps': [
          {
            'bot_mxid': '@b:hs',
            'app_url': 'https://a',
            'composer_button_label': '   ',
            'list_button_label': '',
          },
        ],
      })['@b:hs']!;
      expect(launch.composerButtonLabel, isNull);
      expect(launch.listButtonLabel, isNull);
    });

    test('терпимость к отсутствию ключа apps и к мусору', () {
      expect(parseBotMiniApps({}), isEmpty);
      expect(parseBotMiniApps({'apps': 'not-a-list'}), isEmpty);
      expect(
        parseBotMiniApps({
          'apps': ['string', 42, null],
        }),
        isEmpty,
      );
    });

    // Плашка/кнопка обновляются СРАЗУ после вкл/выкл/переименования: карточка
    // настроек (btncfg_*) приходит после применения на сервере → триггерит
    // перечитку реестра (эндпоинт не пушит события). Тут — предикат-детектор.
    test('isButtonConfigCard: ловит btncfg_*, не ловит прочие/null', () {
      expect(isButtonConfigCard('btncfg_app1'), isTrue);
      expect(isButtonConfigCard('btncfg_'), isTrue);
      expect(isButtonConfigCard('myapps_detail_app1'), isFalse);
      expect(isButtonConfigCard('botfather_welcome'), isFalse);
      expect(isButtonConfigCard(null), isFalse);
      expect(isButtonConfigCard(''), isFalse);
    });
  });
}
