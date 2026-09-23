// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/chat_topology.dart';

import 'test_client.dart';

/// Полностью замьюченная комната не копит бейдж (RL-badge-muted-room-excluded).
///
/// Корень (прод 2026-09-09): мьют в Matrix — PROSPECTIVE-only. Override-правило
/// `global/override/<room_id>` с пустыми actions гасит генерацию НОВЫХ
/// push-actions, но СТАРЫЕ строки `event_push_summary.notif_count` не чистит
/// ничто, кроме read-ресипта, а клиент шлёт ресипт только при ОТКРЫТИИ комнаты.
/// Замьюченную комнату пользователь не открывает ⇒ число на иконке становится
/// НЕСНИМАЕМЫМ. Замер на проде: у @aleksandr.novokshonov 8 из 16 notif-комнат
/// замьючены; таких пользователей на инстансе — 26.
///
/// Прежний код полагался на допущение из собственного комментария
/// («notificationCount == 0 ⟺ muted»), которое прод опровергает.
///
/// `mentionsOnly` — это то, что ставит КНОПКА мьюта в UI (прод: 665 правил у 88
/// юзеров против 367 у 29 для `dontNotify`). Там в бейдж идут ТОЛЬКО упоминания
/// (`highlightCount > 0`): считать всё — оставить неснимаемый остаток, исключить
/// всё — спрятать упоминания, ради которых режим и выбран.
///
/// ledger:RL-badge-muted-room-excluded
void main() {
  late Client client;

  const roomId = '!muted:example.invalid';

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  Room newRoom() => Room(id: roomId, client: client)
    ..setState(
      Event(
        eventId: '\$create',
        senderId: '@creator:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        type: EventTypes.RoomCreate,
        content: {},
        room: Room(id: roomId, client: client),
        stateKey: '',
      ),
    );

  /// Кладёт `m.push_rules` в account data так, как их отдаёт сервер.
  /// [actions] пустой ⇒ SDK читает это как [PushRuleState.dontNotify].
  void setRoomPushRule(String ruleId, List<Object?> actions,
      {String kind = 'override'}) {
    client.accountData['m.push_rules'] = BasicEvent(
      type: 'm.push_rules',
      content: {
        'global': {
          kind: [
            {
              'rule_id': ruleId,
              'default': false,
              'enabled': true,
              'conditions': [
                {
                  'kind': 'event_match',
                  'key': 'room_id',
                  'pattern': ruleId,
                },
              ],
              'actions': actions,
            },
          ],
        },
      },
    );
  }

  group('countsTowardAppBadge: полный мьют', () {
    test(
        'AC:RL-badge-muted-room-excluded/1 замьюченная комната с застрявшим '
        'notif>0 и БЕЗ ресипта → НЕ в бейдж (иначе число неснимаемо)', () {
      final room = newRoom()..notificationCount = 3;
      setRoomPushRule(roomId, const []);

      expect(room.pushRuleState, PushRuleState.dontNotify); // sanity
      expect(room.countsTowardAppBadge, isFalse);
    });

    test(
        'AC:RL-badge-muted-room-excluded/2 RED-PROOF: та же комната БЕЗ мьюта '
        '→ в бейдж (правка не глушит обычные непрочитанные)', () {
      final room = newRoom()..notificationCount = 3;
      // Правило есть, но действия непустые → notify, не мьют.
      setRoomPushRule(roomId, const ['notify']);

      expect(room.pushRuleState, isNot(PushRuleState.dontNotify));
      expect(room.countsTowardAppBadge, isTrue);
    });

    test(
        'AC:RL-badge-muted-room-excluded/3 мьют ДРУГОЙ комнаты не влияет '
        '(правило матчится по room_id, а не «есть хоть какой-то мьют»)', () {
      final room = newRoom()..notificationCount = 2;
      setRoomPushRule('!other:example.invalid', const []);

      expect(room.countsTowardAppBadge, isTrue);
    });

    test(
        'AC:RL-badge-muted-room-excluded/4 инвайт в замьюченную комнату всё '
        'равно в бейдж (инвайт нельзя «не заметить»)', () {
      final room = newRoom()
        ..notificationCount = 0
        ..membership = Membership.invite;
      setRoomPushRule(roomId, const []);

      expect(room.countsTowardAppBadge, isTrue);
    });

    test(
        'AC:RL-badge-muted-room-excluded/5 markedUnread в замьюченной комнате '
        'остаётся в бейдже (ручная пометка сильнее мьюта)', () {
      final room = newRoom()..notificationCount = 0;
      setRoomPushRule(roomId, const []);
      room.roomAccountData['m.marked_unread'] = BasicEvent(
        type: 'm.marked_unread',
        content: {'unread': true},
      );

      expect(room.markedUnread, isTrue);
      expect(room.countsTowardAppBadge, isTrue);
    });

    test(
        'AC:RL-badge-muted-room-excluded/7 mentionsOnly (то, что ставит КНОПКА '
        'мьюта в UI) со СТАРЫМ остатком и БЕЗ упоминаний → НЕ в бейдж', () {
      // Кнопка «Отключить уведомления» зовёт setPushRuleState(mentionsOnly), а
      // не dontNotify. Прод 2026-09-09: 665 таких правил у 88 юзеров против
      // 367 у 29 для dontNotify — то есть это ОСНОВНАЯ форма мьюта.
      final room = newRoom()
        ..notificationCount = 3
        ..highlightCount = 0;
      setRoomPushRule(roomId, const ['dont_notify'], kind: 'room');

      expect(room.pushRuleState, PushRuleState.mentionsOnly); // sanity
      expect(room.countsTowardAppBadge, isFalse);
    });

    test(
        'AC:RL-badge-muted-room-excluded/8 mentionsOnly С упоминанием → В бейдж '
        '(режим выбран именно ради упоминаний — прятать их нельзя)', () {
      final room = newRoom()
        ..notificationCount = 3
        ..highlightCount = 1;
      setRoomPushRule(roomId, const ['dont_notify'], kind: 'room');

      expect(room.pushRuleState, PushRuleState.mentionsOnly);
      expect(room.countsTowardAppBadge, isTrue);
    });
  });
}
