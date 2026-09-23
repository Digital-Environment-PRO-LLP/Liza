import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'liza_flows.dart';

/// LABA-1898 device-flow: сообщение, отправленное ДО принятия приглашения, видно
/// в таймлайне после join (не только в превью списка чатов). Живой прогон против
/// локального стека (make local-up && make local-seed-e2e).
///
/// Сценарий (AC-8):
/// 1. B (headless-актор testuser2) создаёт ГРУППУ, приглашает A (testuser) и
///    СРАЗУ пишет сообщение — A ещё только приглашён, не вступил.
/// 2. UI A видит приглашённую группу в списке, тапает → принимает инвайт (join).
/// 3. Открывается чат, и сообщение B ВИДНО В ТАЙМЛАЙНЕ (инвариант LABA-1898).
///    Без фикса лента после join пуста — сообщение осталось за prev_batch-гэпом.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LABA-1898: до-join сообщение видно в таймлайне после принятия '
      'приглашения', (tester) async {
    SharedPreferences.setMockInitialValues({
      'chat.fluffy.show_no_google': false,
    });

    // --- Сидинг на сервере ДО старта UI ---
    final actorA = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userA);
    final actorB = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userB);

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final groupName = 'LABA1898 $stamp';
    final preJoinMessage = 'до-join сообщение $stamp';

    // B создаёт группу и приглашает A. A НЕ вступает (никакого actorA.joinRoom).
    final roomId = await actorB.createGroupChat(
      [actorA.userId],
      name: groupName,
    );
    // Сообщение уходит, пока A только приглашён — корень бага LABA-1898.
    await actorB.sendText(roomId, preJoinMessage);

    try {
      // --- UI юзера A ---
      app.main();
      await tester.ensureLizaHome();

      // Приглашённая группа видна в списке чатов по своему имени.
      final inviteTile = find.textContaining(groupName);
      await tester.waitUntil(inviteTile, timeout: const Duration(seconds: 40));
      await tester.tap(inviteTile.first);
      await tester.pump(const Duration(milliseconds: 700));

      // Принять приглашение, если показан экран/кнопка accept (тап по тайлу в
      // списке уже инициирует join, но на экране чата инвайт-баннер возможен).
      for (final label in ['Принять', 'Присоединиться', 'Accept', 'Join']) {
        final btn = find.text(label);
        if (btn.evaluate().isNotEmpty) {
          await tester.tap(btn.first);
          await tester.pump(const Duration(milliseconds: 700));
          break;
        }
      }

      // Открылся чат.
      await tester.waitUntil(
        find.byType(ChatView),
        timeout: const Duration(seconds: 40),
      );

      // ГЛАВНЫЙ инвариант LABA-1898: до-join сообщение видно В ТАЙМЛАЙНЕ.
      await tester.waitUntil(
        find.textContaining(preJoinMessage, findRichText: true),
        timeout: const Duration(seconds: 40),
      );
    } finally {
      await actorA.logout();
      await actorB.logout();
    }
  });
}
