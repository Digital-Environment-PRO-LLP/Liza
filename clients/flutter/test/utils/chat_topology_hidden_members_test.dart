// ledger:RL-participant-hidden-from-list
// Скрытие участника из витрины списка (LABA-2381). Страж на РЕАЛЬНЫХ
// предикатах chat_topology (не реплика): фильтр visibleParticipants,
// isMemberHiddenFor, hiddenMemberIds, canHideMembers + живучесть state через
// partial-sync. Red-proof — в комментариях к каждой группе.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/chat_topology.dart';

import 'test_client.dart';

void main() {
  late Client client;
  late Room room;
  // «Зритель» = текущий залогиненный пользователь (FakeMatrixApi назначает id
  // сам — берём его из client.userID, а не хардкодим).
  late String me;
  const spam = '@spam:example.invalid';
  const bot = '@bot:example.invalid';
  const otherAdmin = '@boss:example.invalid';

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    me = client.userID!;
    room = Room(id: '!r:example.invalid', client: client);
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  void setHidden(List<String> ids) {
    room.setState(
      StrippedStateEvent(
        type: hiddenMembersState,
        stateKey: '',
        senderId: '@creator:example.invalid',
        content: {'user_ids': ids},
      ),
    );
  }

  void setPowerLevels(Map<String, int> users) {
    room.setState(
      Event(
        eventId: '\$pl',
        senderId: '@creator:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        type: EventTypes.RoomPowerLevels,
        content: {'users': users, 'users_default': 0},
        room: room,
        stateKey: '',
      ),
    );
  }

  User user(String id) => User(id, membership: 'join', room: room);

  group('isMemberHiddenFor (чистый предикат)', () {
    // Red-proof: убрать `memberId != viewerId` — AC-2 покраснеет (сам себя
    // скроет); убрать `hiddenIds.contains` — AC-1 покраснеет.
    test(
      'AC:RL-participant-hidden-from-list/1 скрытый скрыт для зрителя-не-себя '
      '(∀ обычный/бот/админ id)',
      () {
        final hidden = {spam, bot, otherAdmin};
        for (final target in hidden) {
          expect(
            isMemberHiddenFor(
              hiddenIds: hidden,
              memberId: target,
              viewerId: me,
            ),
            isTrue,
            reason: '$target должен быть скрыт для $me',
          );
        }
      },
    );

    test('AC:RL-participant-hidden-from-list/2 скрытый видит СЕБЯ', () {
      expect(
        isMemberHiddenFor(hiddenIds: {spam}, memberId: spam, viewerId: spam),
        isFalse,
        reason: 'себя из своего же списка не убираем',
      );
    });

    test('AC:RL-participant-hidden-from-list/3 глобально: второй админ '
        '(не автор скрытия) тоже не видит скрытого', () {
      expect(
        isMemberHiddenFor(
          hiddenIds: {spam},
          memberId: spam,
          viewerId: otherAdmin,
        ),
        isTrue,
        reason: 'скрытие в room state видят все зрители, не только скрывший',
      );
    });

    test('не в списке — виден', () {
      expect(
        isMemberHiddenFor(hiddenIds: {spam}, memberId: bot, viewerId: me),
        isFalse,
      );
    });
  });

  group('hiddenMemberIds / visibleParticipants (реальный Room)', () {
    test('пустой state → никого не скрывает (нулевая регрессия)', () {
      expect(room.hiddenMemberIds, isEmpty);
      final participants = [user(me), user(spam), user(bot)];
      expect(
        room.visibleParticipants(participants).map((u) => u.id),
        containsAll([me, spam, bot]),
      );
    });

    test('AC:RL-participant-hidden-from-list/1 visibleParticipants убирает '
        'скрытого', () {
      setHidden([spam]);
      expect(room.hiddenMemberIds, {spam});
      final visible = room
          .visibleParticipants([user(me), user(spam), user(bot)])
          .map((u) => u.id)
          .toList();
      expect(visible, isNot(contains(spam)));
      expect(visible, containsAll([me, bot]));
    });

    test('AC:RL-participant-hidden-from-list/2 visibleParticipants оставляет '
        'СЕБЯ, даже если ты скрыт', () {
      setHidden([me, spam]);
      final visible = room
          .visibleParticipants([user(me), user(spam)])
          .map((u) => u.id)
          .toList();
      expect(visible, contains(me), reason: 'зритель видит себя');
      expect(visible, isNot(contains(spam)));
    });
  });

  group('canHideMembers (гейт PL>=100)', () {
    // Red-proof: понизить порог до 50 — тест на moderator покраснеет.
    test('AC:RL-participant-hidden-from-list/6 PL=100 → можно скрывать', () {
      setPowerLevels({me: 100});
      expect(room.canHideMembers, isTrue);
    });

    test('AC:RL-participant-hidden-from-list/6 PL=50 (модератор) → нельзя', () {
      setPowerLevels({me: 50});
      expect(room.canHideMembers, isFalse);
    });

    test('AC:RL-participant-hidden-from-list/6 PL=0 → нельзя', () {
      setPowerLevels({me: 0});
      expect(room.canHideMembers, isFalse);
    });
  });

  group('живучесть state через partial-sync (M3, importantStateEvents)', () {
    test('AC:RL-participant-hidden-from-list/1 hidden_members переживает sync '
        'без открытия таймлайна', () async {
      const roomId = '!grp:example.invalid';
      await client.handleSync(
        SyncUpdate(
          nextBatch: 'b1',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(
                state: [
                  MatrixEvent(
                    type: EventTypes.RoomCreate,
                    eventId: '\$c',
                    senderId: '@boss:example.invalid',
                    originServerTs: DateTime.now(),
                    content: const {},
                    stateKey: '',
                  ),
                  MatrixEvent(
                    type: hiddenMembersState,
                    eventId: '\$h',
                    senderId: '@boss:example.invalid',
                    originServerTs: DateTime.now(),
                    content: const {
                      'user_ids': [spam],
                    },
                    stateKey: '',
                  ),
                ],
              ),
            },
          ),
        ),
      );

      final synced = client.getRoomById(roomId);
      expect(synced, isNotNull);
      expect(
        synced!.partial,
        isTrue,
        reason:
            'таймлайн не открывали — комната partial, именно этот путь '
            'терял бы скрытие без importantStateEvents',
      );
      expect(
        synced.getState(hiddenMembersState),
        isNotNull,
        reason: 'скрытие обязано пережить гейт importantStateEvents',
      );
      expect(synced.hiddenMemberIds, {spam});
    });
  });

  group('nextHiddenMemberIds read-before-write мерж (M5)', () {
    // Красит: если бы setMemberHidden затирал список целиком (без мержа),
    // добавление spam потеряло бы bot — этот тест поймал бы.
    test('AC:RL-participant-hidden-from-list/4 скрыть добавляет к списку, '
        'вернуть — убирает, не трогая соседей', () {
      final afterHide = nextHiddenMemberIds({bot}, spam, hidden: true);
      expect(
        afterHide,
        {bot, spam},
        reason: 'read-before-write мержит, не затирает существующего bot',
      );

      final afterUnhide = nextHiddenMemberIds(afterHide, bot, hidden: false);
      expect(afterUnhide, {
        spam,
      }, reason: 'возврат убирает только bot, spam остаётся');
    });

    test('повторное скрытие того же — без дублей (Set)', () {
      expect(nextHiddenMemberIds({spam}, spam, hidden: true), {spam});
    });
  });
}
