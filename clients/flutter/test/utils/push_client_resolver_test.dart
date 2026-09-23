// ignore_for_file: depend_on_referenced_packages

// Страж маршрутизации пуша/тапа к аккаунту-адресату при мультиаккаунте на одном
// устройстве. Инцидент 2026-09-03: у второго/третьего аккаунта Нади не было
// pusher-ов, а обработчик пуша был привязан к первому клиенту. Спека —
// docs/superpowers/specs/2026-09-03-stories-push-multiaccount-design.md.
//
// ledger:RL-push-multiaccount-routing

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/push_client_resolver.dart';
import 'package:liza/utils/push_helper.dart';

import 'per_user_fake_api.dart';
import 'test_client.dart';

const _prod = '@nadya:synapse.liza.laba.prodamus.tech';
const _n2 = '@nadezhda.rozental:nadezhda.liza.ru';
const _n3 = '@rozental.nadezhda:nadezhda.liza.ru';

Future<Client> _client(String name, String userId) {
  final host = userId.split(':').last;
  return prepareTestClient(
    loggedIn: true,
    clientName: name,
    userId: userId,
    homeserver: Uri.parse('https://$host'),
    httpClient: PerUserFakeMatrixApi(userId: userId, homeserverHost: host),
  );
}

Future<void> _join(Client c, String roomId) => c.handleSync(
      SyncUpdate(
        nextBatch: 'b-${c.clientName}-$roomId',
        rooms: RoomsUpdate(
          join: {
            roomId: JoinedRoomUpdate(
              state: [
                MatrixEvent(
                  type: EventTypes.RoomCreate,
                  eventId: '\$c-$roomId',
                  senderId: c.userID!,
                  originServerTs: DateTime.now(),
                  content: const {},
                  stateKey: '',
                ),
              ],
            ),
          },
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client a, b, c;

  setUp(() async {
    a = await _client('Liza android', _prod);
    b = await _client('Liza-1786629781847', _n2);
    c = await _client('Liza-1787253958881', _n3);
  });

  tearDown(() async {
    await a.dispose();
    await b.dispose();
    await c.dispose();
  });

  group('clientForPush', () {
    // AC:RL-push-multiaccount-routing/1
    test('client_name → клиент с этим именем ∀ позиций в списке', () {
      for (final order in [
        [a, b, c],
        [b, a, c],
        [c, b, a],
      ]) {
        for (final target in [a, b, c]) {
          expect(
            clientForPush(clients: order, clientName: target.clientName),
            same(target),
            reason: 'порядок ${order.map((x) => x.clientName)} → '
                '${target.clientName}',
          );
        }
      }
    });

    // AC:RL-push-multiaccount-routing/1
    test('client_name → клиент независимо от типа пуша (комната может не '
        'быть у клиента)', () {
      // clearing без room_id, сторис/сообщение с чужой комнатой — ключ решает.
      expect(clientForPush(clients: [a, b, c], clientName: b.clientName),
          same(b));
      expect(
        clientForPush(
          clients: [a, b, c],
          clientName: c.clientName,
          roomId: '!unknown:nadezhda.liza.ru',
        ),
        same(c),
      );
    });

    // AC:RL-push-multiaccount-routing/2
    test('без client_name: единственный клиент с комнатой; sender исключён',
        () async {
      const room = '!dm:nadezhda.liza.ru';
      await _join(b, room);
      expect(
        clientForPush(clients: [a, b, c], roomId: room),
        same(b),
        reason: 'комната есть только у b',
      );
      // Личный чат №2↔№1: комната у a и b, отправитель — b → адресат a.
      await _join(a, room);
      expect(
        clientForPush(clients: [a, b, c], roomId: room, senderId: b.userID),
        same(a),
      );
    });

    // AC:RL-push-multiaccount-routing/3
    test('без client_name и ≥2 кандидатов → детерминированно первый', () async {
      const stories = '!stories:synapse.liza.laba.prodamus.tech';
      await _join(b, stories);
      await _join(c, stories);
      expect(
        clientForPush(clients: [a, b, c], roomId: stories, senderId: a.userID),
        same(b),
      );
      expect(
        clientForPush(clients: [a, c, b], roomId: stories, senderId: a.userID),
        same(c),
      );
    });

    // AC:RL-push-multiaccount-routing/3
    test('ни ключа, ни комнаты → первый клиент (совместимость)', () {
      expect(clientForPush(clients: [b, a]), same(b));
      expect(
        clientForPush(clients: [b, a], clientName: 'нет такого'),
        same(b),
      );
    });
  });

  group('pushNotificationId', () {
    // AC:RL-push-multiaccount-routing/6
    test('два аккаунта в одной комнате → два разных id; тот же аккаунт → тот же',
        () {
      const room = '!r:nadezhda.liza.ru';
      final idB = pushNotificationId(b.clientName, room);
      final idC = pushNotificationId(c.clientName, room);
      expect(idB, isNot(equals(idC)));
      expect(pushNotificationId(b.clientName, room), idB);
      // старый одноклиентный id (roomId.hashCode) не совпадает с новым
      expect(idB, isNot(equals(room.hashCode)));
    });
  });

  // ledger:RL-push-active-room-native-suppress
  group('nativeActiveRoomPayload', () {
    test('открытый чат на переднем плане → комната и аккаунт для willPresent '
        '(AC:RL-push-active-room-native-suppress/1)', () {
      expect(
        nativeActiveRoomPayload(
          activeRoomId: '!support:s',
          clientName: 'Liza macos',
          foreground: true,
          clientCount: 1,
        ),
        {'roomId': '!support:s', 'clientName': 'Liza macos', 'singleClient': true},
      );
      expect(
        nativeActiveRoomPayload(
          activeRoomId: '!support:s',
          clientName: 'Liza macos-2',
          foreground: true,
          clientCount: 2,
        )!['singleClient'],
        isFalse,
        reason: 'при мультиаккаунте пуш без client_name не глушим',
      );
    });

    test('фон или ни один чат не открыт → сброс, уведомления не глушатся '
        '(AC:RL-push-active-room-native-suppress/2)', () {
      for (final (room, foreground) in [
        ('!support:s', false),
        (null, true),
        (null, false),
      ]) {
        expect(
          nativeActiveRoomPayload(
            activeRoomId: room,
            clientName: 'Liza ios',
            foreground: foreground,
            clientCount: 1,
          ),
          isNull,
          reason: 'room=$room foreground=$foreground',
        );
      }
    });
  });

  group('pushInActiveRoomFor', () {
    // AC:RL-push-multiaccount-routing/5
    test('гасит баннер только если активная комната принадлежит адресату', () {
      const room = '!dm:nadezhda.liza.ru';
      bool f({required String clientName, String? active, String? activeClient,
          bool resumed = true}) =>
          pushInActiveRoomFor(
            roomId: room,
            activeRoomId: active,
            activeClientName: activeClient,
            clientName: clientName,
            resumed: resumed,
          );
      // активен b в этой комнате, пуш адресован b → haptic-only
      expect(f(clientName: 'b', active: room, activeClient: 'b'), isTrue);
      // активен b в этой комнате, пуш адресован a (та же общая комната) → баннер
      expect(f(clientName: 'a', active: room, activeClient: 'b'), isFalse);
      // другая комната / не resumed → баннер
      expect(f(clientName: 'b', active: '!other:x', activeClient: 'b'), isFalse);
      expect(f(clientName: 'b', active: room, activeClient: 'b', resumed: false),
          isFalse);
      // одноклиентная совместимость: activeClientName == null → как раньше
      expect(f(clientName: 'b', active: room), isTrue);
    });
  });

  group('pusherAppendFor', () {
    // AC:RL-push-multiaccount-pusher-per-client/2
    test('append=true ТОЛЬКО при ≥2 своих аккаунтов на одном хоумсервере', () {
      // 1 клиент
      expect(pusherAppendFor(a, [a]), isFalse);
      // 2 на разных HS
      expect(pusherAppendFor(a, [a, b]), isFalse);
      expect(pusherAppendFor(b, [a, b]), isFalse);
      // 2 на одном HS
      expect(pusherAppendFor(b, [b, c]), isTrue);
      expect(pusherAppendFor(c, [b, c]), isTrue);
      // 3 как у Нади: prod — false, оба nadezhda — true
      expect(pusherAppendFor(a, [a, b, c]), isFalse);
      expect(pusherAppendFor(b, [a, b, c]), isTrue);
      expect(pusherAppendFor(c, [a, b, c]), isTrue);
      // не зависит от порядка
      expect(pusherAppendFor(b, [c, a, b]), isTrue);
    });
  });

  group('pushClientNameFromRaw', () {
    // AC:RL-push-multiaccount-routing/1
    test('ключ читается из сырой карты; PushNotification.fromJson его теряет',
        () {
      final raw = <String, dynamic>{
        'room_id': '!r:x',
        'event_id': r'$e',
        'client_name': 'Liza-1786629781847',
      };
      expect(pushClientNameFromRaw(raw), 'Liza-1786629781847');
      expect(pushClientNameFromRaw({'client_name': ''}), isNull);
      expect(pushClientNameFromRaw(null), isNull);
      // red-proof: типизированный объект ключ не несёт — читать надо сырьё
      expect(PushNotification.fromJson(raw).toJson().containsKey('client_name'),
          isFalse);
    });
  });
}
