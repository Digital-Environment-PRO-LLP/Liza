import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat_list/chat_list_item.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'e2e_shots.dart';
import 'liza_flows.dart';

/// Страж РЕГРЕССИИ (ledger:RL-chat-list-redacted-preview), LABA-2624.
/// AC:RL-chat-list-redacted-preview/1
/// AC:RL-chat-list-redacted-preview/2
///
/// Сквозь сервер: модератор (создатель группы) удаляет последнее сообщение
/// пользователя UI → в списке чатов строка превью обычным начертанием и с
/// именем МОДЕРАТОРА, а не автора. Host-страж собирает redacted-событие руками;
/// здесь `redacted_because` приходит от настоящего Synapse.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('удалённое модератором сообщение: превью без зачёркивания', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'chat.fluffy.show_no_google': false,
    });

    final actorA = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userA);
    final moderator = await E2eActor.login(
      E2eConfig.homeserver,
      E2eConfig.userB,
    );
    final moderatorName =
        (await moderator.api.getUserProfile(moderator.userId)).displayname ??
        moderator.userId.localpart!;
    final authorName =
        (await actorA.api.getUserProfile(actorA.userId)).displayname ??
        actorA.userId.localpart!;

    const roomName = 'Удаление LABA-2624';
    final roomId = await moderator.createGroupChat([
      actorA.userId,
    ], name: roomName);
    await actorA.joinRoom(roomId);
    final eventId = await actorA.sendText(roomId, 'сообщение под удаление');
    await moderator.api.redactEvent(
      roomId,
      eventId,
      'e2e-redact-${DateTime.now().microsecondsSinceEpoch}',
    );

    app.main();
    await tester.ensureLizaHome();

    final row = find.ancestor(
      of: find.text(roomName),
      matching: find.byType(ChatListItem),
    );
    final preview = find.descendant(
      of: row,
      matching: find.byWidgetPredicate(
        (w) => w is Text && (w.data ?? '').startsWith('Удалено пользователем'),
      ),
    );
    await tester.waitUntil(preview, timeout: const Duration(seconds: 30));
    await snapCandidate(tester, 'chat-list-redacted-preview__moderator');

    final text = tester.widget<Text>(preview.first);
    expect(text.style?.decoration, isNot(TextDecoration.lineThrough));
    // Строка целиком = имя модератора (без displayname клиент показывает
    // localpart с заглавной — сравниваем без учёта регистра). Точное равенство
    // заодно исключает автора: «testuser» — подстрока «testuser2».
    expect(
      text.data!.toLowerCase(),
      'удалено пользователем ${moderatorName.toLowerCase()}',
    );
    expect(moderatorName.toLowerCase(), isNot(authorName.toLowerCase()));

    await actorA.leaveAndForget(roomId);
    await moderator.leaveAndForget(roomId);
  });
}
