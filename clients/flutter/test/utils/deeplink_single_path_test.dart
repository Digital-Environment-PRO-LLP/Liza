import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ledger:RL-deeplink-single-path
//
// Баг (2026-08-02): на Android практически любая инвайт-ссылка открывала
// карточку/поиск пользователя вместо целевого объекта, на iOS/macOS — нет.
//
// Причина — ДВА одновременных пути обработки одного Intent:
//   A) FlutterActivity → NavigationChannel.setInitialRoute /
//      pushRouteInformation → go_router;
//   B) тот же Intent → плагин app_links → chat_list.dart:_processIncomingUris.
//
// Путь A на Android включён ПО УМОЛЧАНИЮ: FlutterActivityLaunchConfigs
// .deepLinkEnabled(Bundle) при отсутствии метаданных возвращает true. На
// iOS/macOS дефолт FlutterDeepLinkingEnabled = false — отсюда расхождение
// платформ.
//
// go_router матчит маршрут только по `uri.path` и теряет host, поэтому для
// custom-scheme (`liza://invite/<code>` → path `/<code>`) путь A всегда мажет
// → onException → go('/') → гонка с путём B → всеядный fallback
// openMatrixToUrl → бессигильная строка трактуется SDK как user-id.
//
// Инвариант: путь обработки ссылок ОДИН — ручной (B). Структурный тест по
// исходникам, как media_content_protection_test.dart и
// viewer_search_content_protection_test.dart: поднять FlutterActivity и
// проверить реальный Intent в unit-окружении невозможно.
void main() {
  String compact(String path) {
    final file = File(path);
    expect(
      file.existsSync(),
      isTrue,
      reason: 'Тест должен запускаться из clients/flutter/',
    );
    return file.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
  }

  group(
    'платформенный deep-linking выключен [ledger:RL-deeplink-single-path]',
    () {
      test('AndroidManifest объявляет flutter_deeplinking_enabled=false '
          '[AC:RL-deeplink-single-path/4]', () {
        final manifest = compact('android/app/src/main/AndroidManifest.xml');
        expect(
          manifest.contains(
            '<meta-data android:name="flutter_deeplinking_enabled" '
            'android:value="false" />',
          ),
          isTrue,
          reason:
              'без этой метаданной движок включает платформенный deep-linking '
              'по умолчанию, и Intent обрабатывается дважды (go_router + '
              'app_links) — на custom-scheme это открывает карточку '
              'пользователя вместо цели',
        );
      });

      test('iOS/macOS не включают FlutterDeepLinkingEnabled '
          '[AC:RL-deeplink-single-path/5]', () {
        // Отсутствие ключа ≠ «выключено»: движок iOS (Flutter 3.41,
        // FlutterSharedApplication.isFlutterDeepLinkingEnabled) при
        // отсутствии ключа возвращает YES. Под UIScene это особенно опасно —
        // необработанную роутером ссылку движок отдаёт системе, и
        // https://me.liza.ru/... уходит в Safari. Поэтому на iOS ключ обязан
        // стоять явно в false, а значение true запрещено на обеих платформах.
        final deepLinkTrue = RegExp(
          r'<key>FlutterDeepLinkingEnabled</key>\s*<true/>',
        );
        final deepLinkFalse = RegExp(
          r'<key>FlutterDeepLinkingEnabled</key>\s*<false/>',
        );
        for (final path in const [
          'ios/Runner/Info.plist',
          'macos/Runner/Info.plist',
        ]) {
          final file = File(path);
          if (!file.existsSync()) continue;
          expect(
            deepLinkTrue.hasMatch(file.readAsStringSync()),
            isFalse,
            reason:
                '$path не должен включать платформенный deep-linking — '
                'ссылки разбирает app_links → _processIncomingUris',
          );
        }
        expect(
          deepLinkFalse.hasMatch(
            File('ios/Runner/Info.plist').readAsStringSync(),
          ),
          isTrue,
          reason: 'на iOS без явного false движок включает deep-linking сам',
        );
      });
    },
  );

  group('единственный путь разбирает все типы ссылок '
      '[ledger:RL-deeplink-single-path]', () {
    test('_processIncomingUris ветвится по всем трём парсерам '
        '[AC:RL-deeplink-single-path/6]', () {
      final source = compact('lib/pages/chat_list/chat_list.dart');
      // Сторис — главный риск регрессии: до этой правки ветки не было
      // вовсе, ссылку /s/<code> целиком обрабатывал путь A (go_router), и
      // выключение платформенного deep-linking сломало бы её.
      expect(
        source.contains('final storyCode = parseStoryLinkCode(uri);'),
        isTrue,
        reason:
            'без ветки сторис `me.liza.ru/s/<code>` и `liza://story/<code>` '
            'падают во всеядный fallback openMatrixToUrl',
      );
      expect(
        source.contains("context.go('/s/\$storyCode');"),
        isTrue,
        reason: 'сторис-код обязан уходить во внутренний роут /s/:code',
      );
      expect(
        source.contains('final inviteCode = parseInviteCode(uri);'),
        isTrue,
      );
      expect(source.contains("context.go('/i/\$inviteCode');"), isTrue);
      expect(
        source.contains('final channelHandle = parseChannelHandle(uri);'),
        isTrue,
      );
      expect(source.contains("context.go('/c/\$channelHandle');"), isTrue);
    });

    test('внутренние роуты /i/:code, /s/:code, /c/:handle сохранены '
        '[AC:RL-deeplink-single-path/7]', () {
      // Их НЕЛЬЗЯ удалять вместе с платформенным deep-linking: именно в них
      // ведёт внутренняя навигация из _processIncomingUris.
      final routes = compact('lib/config/routes.dart');
      expect(routes.contains("path: '/i/:code'"), isTrue);
      expect(routes.contains("path: '/s/:code'"), isTrue);
      expect(routes.contains("path: '/c/:handle'"), isTrue);
    });
  });
}
