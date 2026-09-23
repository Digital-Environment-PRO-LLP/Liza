import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat_list/chat_list_body.dart';
import 'package:liza/utils/url_launcher.dart';

import 'liza_flows.dart';

/// Страж РЕГРЕССИИ (ledger:RL-message-link-non-member-no-join).
/// Сквозная проверка инварианта LABA-2217 на устройстве: открытие
/// matrix.to-ссылки на сообщение в комнате, участником которой залогиненный
/// пользователь НЕ является, должно показывать информационный экран
/// «вы не участник этого чата» и НЕ предлагать вступить (никакой кнопки
/// «Войти в чат» / «Join room»).
///
/// В отличие от receipts_test не требует второго актора и m.read — детерминированно
/// и не зависит от тайминга sync. `!fake:local` заведомо отсутствует у юзера A
/// (getRoomById → null → ветка notMemberInfo в openMatrixToUrl).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Liza e2e: message-link у не-участника (LABA-2217)', () {
    testWidgets('!roomId, которого нет у юзера → инфо-экран без «Войти в чат»', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });

      app.main();
      await tester.ensureLizaHome();

      // Контекст из-под MatrixWidget (список чатов уже на экране).
      final context = tester.element(find.byType(ChatListViewBody));

      // Ссылка на сообщение в чужой комнате — юзер A в ней не состоит.
      const link =
          r'https://matrix.to/#/!nonexistentRoom:local/$fakeEvent12345';
      UrlLauncher(context, link).launchUrl();

      // Дожидаемся информационного диалога (заголовок — ru или en).
      await tester.waitUntil(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              (w.data == 'Вы не участник этого чата' ||
                  w.data == 'You are not in this chat'),
        ),
        timeout: const Duration(seconds: 15),
      );

      // Инвариант безопасности: НИКАКОЙ кнопки вступления в чат.
      for (final joinLabel in const [
        'Войти в чат',
        'Join room',
        'Присоединиться',
        'Присоединиться к чату',
      ]) {
        expect(
          find.text(joinLabel),
          findsNothing,
          reason: 'message-link не должен предлагать вступление ($joinLabel)',
        );
      }

      // Есть кнопка подтверждения (Ok/Ок) — диалог закрывается ею.
      final okButton = find.byWidgetPredicate(
        (w) => w is Text && (w.data == 'Ок' || w.data == 'Ok'),
      );
      expect(okButton, findsWidgets);
      await tester.tap(okButton.first);
      await tester.pump(const Duration(milliseconds: 400));

      // Диалог закрылся — снова список чатов, без экрана комнаты.
      expect(find.byType(ChatListViewBody), findsOneWidget);
    });
  });
}
