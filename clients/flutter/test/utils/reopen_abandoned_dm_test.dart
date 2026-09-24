// ledger:RL-reopen-abandoned-dm-no-duplicate
// AC:RL-reopen-abandoned-dm-no-duplicate/1 AC:RL-reopen-abandoned-dm-no-duplicate/2
// AC:RL-reopen-abandoned-dm-no-duplicate/3
//
// LABA-2633: U1 вышел из DM A и создал новый DM B, U2 принял B и в брошенной A
// нажал «Открыть чат заново» → голый `room.invite` возвращал U1 в A → у пары
// ДВА живых личных чата. Теперь `recreateChat` сначала ищет живой DM
// (`findLiveDirectChat`) и открывает его.
//
// Red-proof:
//   RP-1 (AC-2): вернуть в recreateChat голый `room.invite` → invite == 1,
//     навигации нет, тест красный.
//   RP-2 (AC-1 e/i): заменить поиск на `client.getDirectChatFromUserId` → у A
//     свежее lastEvent, вернётся сама A (exclude не соблюдён) — красный.
//   RP-3 (AC-1 j): убрать сравнение имени → брошенный mini App-чат уводит в
//     ассистента — красный.

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/chat.dart';
import 'package:liza/utils/direct_chat_draft.dart';
import 'test_client.dart';

const _partner = '@bob:example.invalid';
const _other = '@carol:example.invalid';

Event _state(
  Room room,
  String type,
  Map<String, Object?> content, {
  String stateKey = '',
  String? sender,
}) => Event(
  eventId: '\$${type}_${stateKey}_${room.id}',
  senderId: sender ?? room.client.userID!,
  originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
  type: type,
  stateKey: stateKey,
  content: content,
  room: room,
);

/// Комната-DM с [partner]: моё членство [me], партнёра [partnerMembership]
/// (null — member-стейта партнёра нет, как при lazy members).
Room _dm(
  Client client,
  String id, {
  String partner = _partner,
  Membership me = Membership.join,
  String? partnerMembership = 'join',
  String? name,
  int? lastTs,
  bool inDirect = true,
  bool acceptedDirectInvite = false,
  int? joinedCount,
}) {
  final joined =
      joinedCount ??
      (me == Membership.join ? 1 : 0) + (partnerMembership == 'join' ? 1 : 0);
  final invited = partnerMembership == 'invite' ? 1 : 0;
  final room = Room(
    id: id,
    client: client,
    membership: me,
    summary: RoomSummary.fromJson({
      'm.joined_member_count': joined,
      'm.invited_member_count': invited,
    }),
  );
  final own = _state(
    room,
    EventTypes.RoomMember,
    {'membership': me.name, if (me == Membership.invite) 'is_direct': true},
    stateKey: client.userID!,
    sender: me == Membership.invite ? partner : null,
  );
  if (acceptedDirectInvite) {
    // Join поверх личного приглашения: is_direct остаётся только в prev_content.
    own.prevContent = {'membership': 'invite', 'is_direct': true};
  }
  room.setState(own);
  if (partnerMembership != null) {
    room.setState(
      _state(
        room,
        EventTypes.RoomMember,
        {'membership': partnerMembership},
        stateKey: partner,
        sender: partner,
      ),
    );
  }
  if (name != null) {
    room.setState(_state(room, EventTypes.RoomName, {'name': name}));
  }
  if (lastTs != null) {
    room.lastEvent = Event(
      eventId: '\$last_$id',
      senderId: partner,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(lastTs),
      type: EventTypes.Message,
      content: {'msgtype': 'm.text', 'body': 'x'},
      room: room,
    );
  }
  client.rooms.add(room);
  if (inDirect) {
    final direct = Map<String, dynamic>.from(
      client.accountData['m.direct']?.content ?? {},
    );
    direct[partner] = [...(direct[partner] as List? ?? []), id];
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: direct,
    );
  }
  return room;
}

/// Брошенный DM A: я в комнате один, партнёр вышел.
Room _abandoned(Client client, {String? name, int? lastTs}) => _dm(
  client,
  '!abandoned:example.invalid',
  partnerMembership: 'leave',
  name: name,
  lastTs: lastTs,
);

class _FakeChatController extends ChatController {
  _FakeChatController(this.client);

  final Client client;

  // Тяжёлый initState (таймлайн, подписки, Matrix.of) не нужен: проверяем
  // только recreateChat. dispose реального контроллера трогает sendingClient и
  // inputFocus — их и инициализируем.
  @override
  // ignore: must_call_super
  void initState() {
    sendingClient = client;
    inputFocus = FocusNode();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _Host extends ChatPageWithRoom {
  const _Host({super.key, required super.room, required this.client});

  final Client client;

  @override
  // ignore: no_logic_in_create_state
  ChatController createState() => _FakeChatController(client);
}

void main() {
  late Client client;
  late FakeMatrixApi api;

  setUp(() async {
    api = FakeMatrixApi();
    client = await prepareTestClient(loggedIn: true, httpClient: api);
    client.rooms.clear();
    client.accountData.remove('m.direct');
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  group('AC-1 findLiveDirectChat', () {
    test('(a) живой DM, оба join → он', () {
      final a = _abandoned(client);
      _dm(client, '!b:example.invalid');
      expect(
        findLiveDirectChat(client, _partner, exclude: a)?.id,
        '!b:example.invalid',
      );
    });

    test('(b) приглашение от партнёра в новый DM → оно', () {
      final a = _abandoned(client);
      _dm(client, '!b:example.invalid', me: Membership.invite);
      expect(
        findLiveDirectChat(client, _partner, exclude: a)?.id,
        '!b:example.invalid',
      );
    });

    test('(c) других комнат нет → null', () {
      final a = _abandoned(client);
      expect(findLiveDirectChat(client, _partner, exclude: a), isNull);
    });

    test('(d) живой DM только с ДРУГИМ партнёром → null', () {
      final a = _abandoned(client);
      _dm(client, '!c:example.invalid', partner: _other);
      expect(findLiveDirectChat(client, _partner, exclude: a), isNull);
    });

    test('(e) единственный DM — сама брошенная комната → null', () {
      final a = _abandoned(client, lastTs: 9000);
      expect(findLiveDirectChat(client, _partner, exclude: a), isNull);
    });

    test('(f) вторая комната тоже брошена → null', () {
      final a = _abandoned(client);
      _dm(client, '!b:example.invalid', partnerMembership: 'leave');
      expect(findLiveDirectChat(client, _partner, exclude: a), isNull);
    });

    test('(g) я вышел / забанен во второй комнате → null', () {
      for (final me in [Membership.leave, Membership.ban]) {
        client.rooms.clear();
        client.accountData.remove('m.direct');
        final a = _abandoned(client);
        _dm(client, '!b:example.invalid', me: me);
        expect(
          findLiveDirectChat(client, _partner, exclude: a),
          isNull,
          reason: 'me=${me.name}',
        );
      }
    });

    test('(h) две живые: join раньше invite, затем свежее lastEvent', () {
      final a = _abandoned(client);
      _dm(client, '!inv:example.invalid', me: Membership.invite, lastTs: 9000);
      _dm(client, '!old:example.invalid', lastTs: 2000);
      _dm(client, '!new:example.invalid', lastTs: 5000);
      expect(
        findLiveDirectChat(client, _partner, exclude: a)?.id,
        '!new:example.invalid',
      );
    });

    test('(i) у брошенной A lastEvent свежее, чем у живой B → всё равно B', () {
      final a = _abandoned(client, lastTs: 9000);
      _dm(client, '!b:example.invalid', lastTs: 1000);
      expect(
        client.getDirectChatFromUserId(_partner),
        a.id,
        reason: 'SDK-поиск возвращает брошенную A — поэтому он не годится',
      );
      expect(
        findLiveDirectChat(client, _partner, exclude: a)?.id,
        '!b:example.invalid',
      );
    });

    test('(j) mini App-чат и ассистент не подменяют друг друга', () {
      // Брошенный mini App-чат при живом ассистенте (без имени).
      final app = _abandoned(client, name: 'Mini App X');
      _dm(client, '!assistant:example.invalid');
      expect(findLiveDirectChat(client, _partner, exclude: app), isNull);

      // И наоборот: брошенный ассистент при живом mini App-чате.
      client.rooms.clear();
      client.accountData.remove('m.direct');
      final assistant = _abandoned(client);
      _dm(client, '!app:example.invalid', name: 'Mini App X');
      expect(findLiveDirectChat(client, _partner, exclude: assistant), isNull);

      // Одноимённый живой mini App-чат при живом ассистенте — берётся он.
      client.rooms.clear();
      client.accountData.remove('m.direct');
      final abandonedApp = _abandoned(client, name: 'Mini App X');
      _dm(client, '!assistant:example.invalid', lastTs: 9000);
      _dm(client, '!app:example.invalid', name: 'Mini App X');
      expect(
        findLiveDirectChat(client, _partner, exclude: abandonedApp)?.id,
        '!app:example.invalid',
      );
    });

    test(
      '(k) A названа «X», у живой B имени нет → null (старое поведение)',
      () {
        final a = _abandoned(client, name: 'X');
        _dm(client, '!b:example.invalid');
        expect(findLiveDirectChat(client, _partner, exclude: a), isNull);
      },
    );

    test('(l) B ещё не в локальном m.direct, member-стейт совпал → B', () {
      final a = _abandoned(client);
      _dm(
        client,
        '!b:example.invalid',
        inDirect: false,
        acceptedDirectInvite: true,
      );
      expect(
        findLiveDirectChat(client, _partner, exclude: a)?.id,
        '!b:example.invalid',
      );
    });

    test('(m) безымянная группа из двух (не DM, без is_direct) → null', () {
      final a = _abandoned(client);
      _dm(client, '!group:example.invalid', inDirect: false);
      expect(findLiveDirectChat(client, _partner, exclude: a), isNull);
    });

    test(
      '(n) lazy members: member-стейта партнёра нет — живость по summary',
      () {
        final a = _abandoned(client);
        _dm(
          client,
          '!dormant:example.invalid',
          partnerMembership: null,
          joinedCount: 2,
        );
        expect(
          findLiveDirectChat(client, _partner, exclude: a)?.id,
          '!dormant:example.invalid',
        );

        client.rooms.clear();
        client.accountData.remove('m.direct');
        final a2 = _abandoned(client);
        _dm(
          client,
          '!dormant:example.invalid',
          partnerMembership: null,
          joinedCount: 1,
        );
        expect(
          findLiveDirectChat(client, _partner, exclude: a2),
          isNull,
          reason: 'в summary я один — партнёр ушёл',
        );
      },
    );
  });

  group('recreateChat на реальном ChatController', () {
    late int inviteCalls;

    Future<ChatController> pumpChat(WidgetTester tester, Room room) async {
      inviteCalls = 0;
      api.api['POST']!['/client/v3/rooms/${Uri.encodeComponent(room.id)}/invite'] =
          (_) {
            inviteCalls++;
            return {};
          };
      final key = GlobalKey<ChatController>();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => _Host(key: key, room: room, client: client),
          ),
          GoRoute(
            path: '/rooms/:roomid',
            builder: (_, state) =>
                Text('opened ${state.pathParameters['roomid']}'),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
        ),
      );
      await tester.pumpAndSettle();
      return key.currentState!;
    }

    testWidgets('AC-2 живой DM есть → invite не шлём, открываем его', (
      tester,
    ) async {
      final a = _abandoned(client);
      _dm(client, '!b:example.invalid');
      final controller = await pumpChat(tester, a);

      await tester.runAsync(() async {
        controller.recreateChat();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();

      expect(inviteCalls, 0, reason: 'дубль рождался именно этим invite');
      expect(find.text('opened !b:example.invalid'), findsOneWidget);
    });

    testWidgets('AC-3 живого DM нет → ровно одно приглашение в A', (
      tester,
    ) async {
      final a = _abandoned(client);
      _dm(client, '!c:example.invalid', partner: _other);
      final controller = await pumpChat(tester, a);

      await tester.runAsync(() async {
        controller.recreateChat();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();

      expect(inviteCalls, 1);
      expect(find.textContaining('opened'), findsNothing);
    });
  });
}
