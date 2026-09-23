import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';
import 'package:liza/pages/chat/events/message_link_preview.dart';
import 'package:liza/pages/chat/input_bar.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'liza_flows.dart';

/// E2E «Copy Message Link» (паритет с Liza) против локального стека
/// (make local-up && make local-seed-e2e). A — UI (testuser), B/C — акторы.
///
/// Страж РЕГРЕССИИ (ledger:RL-message-link) — UI-уровень: копирование ссылки
/// из «…»-меню, превью в композере и карточка в пузыре. Формат ссылки сторожит
/// юнит-тест test/utils/message_link_test.dart (тоже ledger:RL-message-link).
///
/// Сквозной путь пользователя:
///   1. B шлёт сообщение M в группу.
///   2. A: long-press M → «Скопировать ссылку на сообщение» → в буфере
///      matrix.to-ссылка на событие M.
///   3. A вставляет ссылку в композер → над инпутом карточка-превью с именем
///      группы и фрагментом M.
///   4. A отправляет → в ленте сообщение-ссылка рендерится карточкой, а не
///      сырым URL.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> closeChatToList(WidgetTester tester) async {
    final back = find.byType(BackButton);
    if (back.evaluate().isNotEmpty) {
      await tester.tap(back.first);
    }
    for (
      var i = 0;
      i < 20 && find.byType(ChatView).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  group('Liza e2e: ссылка на сообщение', () {
    testWidgets('copy link → превью в композере → карточка в ленте', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });

      final actorA = await E2eActor.login(
        E2eConfig.homeserver,
        E2eConfig.userA,
      );
      final actorB = await E2eActor.login(
        E2eConfig.homeserver,
        E2eConfig.userB,
      );
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final groupName = 'e2e link $stamp';
      final roomId = await actorB.createGroupChat([
        actorA.userId,
      ], name: groupName);
      await actorA.joinRoom(roomId);

      final target = 'link target $stamp';
      final targetEventId = await actorB.sendText(roomId, target);

      try {
        app.main();
        await tester.ensureLizaHome();
        final roomTile = find.textContaining(target);
        await tester.waitUntil(roomTile);
        await tester.tap(roomTile.first);
        await tester.waitUntil(find.byType(ChatView));
        // macOS — двухколоночный режим: список чатов виден рядом с чатом, и
        // текст сообщения совпал бы с тайлом списка. Скоупим в ChatView.
        final messageInChat = find.descendant(
          of: find.byType(ChatView),
          matching: find.textContaining(target, findRichText: true),
        );
        await tester.waitUntil(messageInChat);

        // 2. Выделяем сообщение B и копируем ссылку через «…»-меню.
        await tester.longPress(messageInChat.first);
        await tester.pump(const Duration(milliseconds: 400));
        // Режим выделения включился → в тулбаре есть иконка «копировать».
        await tester.waitUntil(find.byIcon(Icons.copy_outlined));
        // Иконка PopupMenuButton адаптивна (more_horiz на macOS/iOS,
        // more_vert на Android) — берём «…»-меню именно из ChatView
        // (в колоночном режиме у списка чатов есть своё меню).
        final moreButton = find.descendant(
          of: find.byType(ChatView),
          matching: find.byWidgetPredicate((w) => w is PopupMenuButton),
        );
        await tester.waitUntil(moreButton);
        await tester.tap(moreButton.first);
        await tester.pump(const Duration(milliseconds: 500));
        final copyLinkItem = find.text('Скопировать ссылку на сообщение');
        await tester.waitUntil(copyLinkItem);
        await tester.tap(copyLinkItem);
        await tester.pump(const Duration(milliseconds: 400));

        final clip = await Clipboard.getData(Clipboard.kTextPlain);
        final copied = clip?.text ?? '';
        expect(copied, contains('matrix.to/#/'));
        expect(
          copied,
          contains(targetEventId),
          reason: 'ссылка должна указывать ровно на событие M',
        );

        // 3. Вставляем ссылку в композер → карточка-превью над инпутом.
        final input = find.descendant(
          of: find.byType(InputBar),
          matching: find.byType(TextField),
        );
        await tester.waitUntil(input);
        await tester.enterText(input.first, copied);
        await tester.pump(const Duration(milliseconds: 500));

        await tester.waitUntil(
          find.byType(MessageLinkPreview),
          timeout: const Duration(seconds: 10),
        );
        expect(
          find.descendant(
            of: find.byType(MessageLinkPreview),
            matching: find.textContaining(groupName),
          ),
          findsOneWidget,
          reason: 'в карточке — имя группы (источник, как канал в Liza)',
        );

        // 4. Отправляем → композерное превью уходит, в ленте остаётся карточка.
        await tester.tap(find.byIcon(Icons.send_outlined).first);
        await tester.pump(const Duration(milliseconds: 600));

        // Карточка резолвит тело события асинхронно — ждём фрагмент.
        await tester.waitUntil(
          find.descendant(
            of: find.byType(MessageLinkPreview),
            matching: find.textContaining(target),
          ),
          timeout: const Duration(seconds: 15),
        );
      } finally {
        await closeChatToList(tester);
        await actorA.leaveAndForget(roomId);
        await actorB.leaveAndForget(roomId);
        await actorB.logout();
        await actorA.logout();
      }
    });
  });
}
