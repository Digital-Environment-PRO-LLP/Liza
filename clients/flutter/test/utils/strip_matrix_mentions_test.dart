// Страж LABA-2530: разбор упоминаний в превью списка чатов и пушах не ходит
// в сеть. Раньше `stripMatrixMentions` звала SDK-фолбэк
// `unsafeGetUserFromMemoryOrFallback`, который на промахе памяти запускал
// `GET /state/m.room.member` + `GET /profile` — плейсхолдер
// `@username:yourdomain.com` из текста BotFather давал 404 + 403 на каждой
// загрузке web.
//
// ledger:RL-mention-strip-no-network

import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/utils/strip_matrix_mentions.dart';
import 'package:liza/utils/user_handle_service.dart';

import 'test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client client;
  late Room room;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    client = await prepareTestClient(loggedIn: true);
    // Room() по умолчанию partial — как комнаты после холодного старта.
    room = Room(id: '!strip:example.invalid', client: client);
    FakeMatrixApi.calledEndpoints.clear();
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  // SDK-фолбэк запускает запросы fire-and-forget, причём после async-чтения
  // локальной БД. Короткое ожидание дало бы ложно-зелёный тест.
  Future<void> settle() => Future.delayed(const Duration(milliseconds: 300));

  List<String> userLookups() => FakeMatrixApi.calledEndpoints.keys
      .where(
        (k) => k.contains('/profile/') || k.contains('/state/m.room.member/'),
      )
      .toList();

  void setMember(String mxid, {String? displayName}) => room.setState(
    User(mxid, displayName: displayName, membership: 'join', room: room),
  );

  group('stripMatrixMentions', () {
    for (final text in const [
      'Будет использоваться как @username:yourdomain.com',
      'Пример: @user:...',
      'Пиши @bob:example.org.',
      'почта user@host:44188',
      'Спроси @ghost:example.org',
    ]) {
      test(
        'не ходит в сеть: «$text» AC:RL-mention-strip-no-network/1',
        () async {
          stripMatrixMentions(text, room);
          await settle();
          expect(userLookups(), isEmpty);
        },
      );
    }

    test(
      'участник в памяти с именем → ФИО AC:RL-mention-strip-no-network/2',
      () {
        setMember('@bob:example.org', displayName: 'Боб');
        expect(
          stripMatrixMentions('Привет @bob:example.org', room),
          'Привет Боб',
        );
      },
    );

    test('partial-комната, участник только в БД → ФИО без сети '
        'AC:RL-mention-strip-no-network/3', () async {
      const carol = '@carol:example.org';
      await client.database.storeEventUpdate(
        room.id,
        Event(
          type: EventTypes.RoomMember,
          content: {'membership': 'join', 'displayname': 'Кэрол'},
          eventId: '\$carol-member',
          senderId: carol,
          originServerTs: DateTime.now(),
          stateKey: carol,
          room: room,
        ),
        EventUpdateType.state,
        client,
      );
      expect(room.partial, isTrue);
      expect(room.getState(EventTypes.RoomMember, carol), isNull);

      expect(stripMatrixMentions('Спроси $carol', room), 'Спроси carol');
      await settle();
      expect(stripMatrixMentions('Спроси $carol', room), 'Спроси Кэрол');
      expect(userLookups(), isEmpty);
    });

    test(
      'участник без имени → сырой localpart AC:RL-mention-strip-no-network/4',
      () {
        setMember('@my_echo_bot:example.org');
        expect(
          stripMatrixMentions('Бот @my_echo_bot:example.org', room),
          'Бот my_echo_bot',
        );
      },
    );

    test(
      'неизвестный mxid → localpart, сеть 0 AC:RL-mention-strip-no-network/5',
      () async {
        expect(
          stripMatrixMentions('Спроси @ghost:example.org', room),
          'Спроси ghost',
        );
        await settle();
        expect(userLookups(), isEmpty);
      },
    );

    test('ник из кэша → @ник AC:RL-mention-strip-no-network/6', () {
      final handles = UserHandleService(
        baseUrl: 'https://auth.test',
        accessTokenProvider: () => 'token',
        serverNameProvider: () => 'example.org',
        httpClient: MockClient((request) async {
          fail('stripMatrixMentions не должна ходить в сеть: $request');
        }),
      )..rememberHandle('@dave:example.org', 'dave_nick');
      addTearDown(handles.dispose);

      expect(
        stripMatrixMentions('Это @dave:example.org', room, handles: handles),
        'Это @dave_nick',
      );
    });

    test('хвостовая точка остаётся, почта с портом не трогается '
        'AC:RL-mention-strip-no-network/7', () {
      expect(stripMatrixMentions('Пиши @bob:example.org.', room), 'Пиши bob.');
      expect(
        stripMatrixMentions('почта user@host:44188', room),
        'почта user@host:44188',
      );
      expect(
        stripMatrixMentions('Пример: @user:...', room),
        'Пример: @user:...',
      );
    });

    test('пилюля @[Имя] в смешанной строке → Имя '
        'AC:RL-mention-strip-no-network/8', () {
      setMember('@bob:example.org', displayName: 'Боб');
      expect(
        stripMatrixMentions(
          'Спасибо, @[Анна Петрова] и @bob:example.org',
          room,
        ),
        'Спасибо, Анна Петрова и Боб',
      );
    });
  });
}
