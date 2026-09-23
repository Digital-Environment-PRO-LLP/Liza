import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';
import 'package:liza/pages/chat/events/message.dart';
import 'package:liza/pages/chat/events/seen_by_receipts_sheet.dart';
import 'package:liza/pages/chat/input_bar.dart';
import 'package:liza/widgets/avatar.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'e2e_shots.dart';
import 'liza_flows.dart';

/// Сквозной сценарий «доставка + прочтение» против локального стека
/// (make local-up && make local-seed-e2e):
/// 1. B (headless-актор) создаёт DM и пишет A.
/// 2. UI A видит сообщение и отвечает через композер.
/// 3. B получает ответ по sync.
/// 4. B шлёт m.read → у A на его последнем сообщении к своей аватарке (видна
///    сразу, п.2.1) добавляется аватарка B и галочка становится done_all.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Liza e2e: доставка и прочтение', () {
    testWidgets('сообщение B → ответ A → receipt B → done_all у A', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });

      // --- Сидинг на сервере ДО старта UI ---
      final actorA = await E2eActor.login(
        E2eConfig.homeserver,
        E2eConfig.userA,
      );
      final actorB = await E2eActor.login(
        E2eConfig.homeserver,
        E2eConfig.userB,
      );
      final roomId = await actorB.createDirectChat(actorA.userId);
      await actorA.joinRoom(roomId);

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final inbound = 'e2e ping $stamp';
      final outbound = 'e2e pong $stamp';
      await actorB.sendText(roomId, inbound);

      try {
        // --- UI юзера A ---
        app.main();
        await tester.ensureLizaHome();

        // Тайл DM находим по превью последнего сообщения (имя собеседника
        // в тайле — не отдельный Text, а часть строки «testuser2: e2e ping…»).
        final roomTile = find.textContaining(inbound);
        await tester.waitUntil(roomTile);
        await tester.tap(roomTile.first);
        await tester.waitUntil(find.byType(ChatView));

        // 1) Входящее сообщение видно (пузырь — RichText).
        await tester.waitUntil(
          find.textContaining(inbound, findRichText: true),
        );

        // 2) Ответ через композер.
        final input = find.descendant(
          of: find.byType(InputBar),
          matching: find.byType(TextField),
        );
        await tester.waitUntil(input);
        await tester.enterText(input.first, outbound);
        await tester.pump(const Duration(milliseconds: 300));
        final sendButton = find.byIcon(Icons.send_outlined);
        if (sendButton.evaluate().isNotEmpty) {
          await tester.tap(sendButton.first);
        } else {
          await tester.testTextInput.receiveAction(TextInputAction.done);
        }
        await tester.pump(const Duration(milliseconds: 300));

        // 3) B получает ответ по sync.
        final replyEvent = await actorB.waitForEvent(
          roomId,
          (e) => e.type == 'm.room.message' && e.content['body'] == outbound,
        );

        // Своё отправленное сообщение — одна галочка (done), пока B не прочитал.
        // Своя аватарка под ним видна сразу (п.2.1; в DM есть и кластер B под
        // его сообщением). done_all (прочитано собеседником) ещё НЕ должно быть.
        await tester.waitUntil(find.byIcon(Icons.done_rounded));
        expect(find.byType(SeenByAvatars), findsWidgets);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);

        // 4) B читает → галочка становится done_all, и в кластере на граничном
        // сообщении A появляется вторая аватарка (B рядом с моей).
        await actorB.sendReadReceipt(roomId, replyEvent.eventId);

        await tester.waitUntil(
          find.byIcon(Icons.done_all_rounded),
          timeout: const Duration(seconds: 30),
        );

        // Тап по кластеру → окно «кто и когда прочитал» со списком читателей.
        await tester.tap(find.byType(SeenByAvatars).first);
        await tester.waitUntil(find.byType(ReadReceiptsList));
        expect(
          find.descendant(
            of: find.byType(ReadReceiptsList),
            matching: find.byType(Avatar),
          ),
          findsWidgets,
        );

        // Кейс зелёный и экран квитанций устоялся — снимаем кандидат-эталон
        // (Ярус B) во временную папку. Приёмка в tests/screenshots/ — вручную
        // через snap-feature.sh после сверки глазами.
        await snapCandidate(tester, 'receipts-indicators__seen-by-cluster');
      } finally {
        // Не плодим комнаты между прогонами.
        await actorA.leaveAndForget(roomId);
        await actorB.leaveAndForget(roomId);
        await actorB.logout();
        await actorA.logout();
      }
    });
  });
}
