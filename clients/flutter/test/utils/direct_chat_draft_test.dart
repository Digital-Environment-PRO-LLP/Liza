// ledger:RL-direct-chat-draft-on-first-send
// AC:RL-direct-chat-draft-on-first-send/1 AC:RL-direct-chat-draft-on-first-send/3
//
// Страж правила «личный чат/запрос — только с первым сообщением»: чистая
// маршрутизация directChatTarget (join-DM → реальная комната, иначе →
// черновик). Покрывает AC-1 (тап не-контакту НЕ ведёт в комнату, ведёт в
// /rooms/newchat) и AC-3 (существующий join-DM → реальная комната).
// Дедуп материализации (AC-4, ретрай после federation-fail AC-7) — в общей
// воронке ensureDirectChat, страж test/utils/direct_chat_ensure_test.dart.
//
// Red-proof:
//   RP-1 (AC-1): если directChatTarget вернул бы /rooms/<userId> вместо
//     /rooms/newchat/<userId> — упадёт (тап создавал бы «реальную» цель).
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/direct_chat_draft.dart';

void main() {
  group('directChatTarget', () {
    test('AC-3: есть присоединённый DM → реальная комната', () {
      expect(
        directChatTarget(userId: '@bob:server', joinedRoomId: '!room:server'),
        '/rooms/!room:server',
      );
    });

    test('AC-1: нет DM → черновик /rooms/newchat, а НЕ реальная комната', () {
      final target = directChatTarget(userId: '@bob:server');
      expect(target, startsWith('/rooms/newchat/'));
      // MXID закодирован → @ и : не ломают путь.
      expect(target, '/rooms/newchat/${Uri.encodeComponent('@bob:server')}');
      expect(target, isNot(contains('/rooms/@bob')));
    });

    test('AC-1: invite-DM (joinedRoomId == null) тоже ведёт в черновик', () {
      // Вызывающий передаёт joinedRoomId только для membership==join; invite-DM
      // → null → черновик (там startDirectChat сам сделает join).
      expect(
        directChatTarget(userId: '@bob:server', joinedRoomId: null),
        startsWith('/rooms/newchat/'),
      );
    });
  });
}
