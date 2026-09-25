// ignore_for_file: depend_on_referenced_packages

// Страж клиентской ноги «почисти шторку» (Надежда Р. за Сашу Н., 2026-09-24):
// прочитал на одном устройстве — на других уведомления этого чата исчезают.
// Два входа, одно определение «прочитано» (`isUnreadOrInvited`):
//  - тихий clearing-пуш (Sygnal шлёт его на свою квитанцию) → sync → снять
//    прочитанные → отпустить натив (`clearingDone`) при ЛЮБОМ исходе;
//  - живой клиент: чат перестал быть непрочитанным между двумя sync → снять
//    его уведомления, не дожидаясь активации окна.
// Непрочитанное не снимается никогда; при мультиаккаунте — только своё.
// howItWoks/pushes.md §21.
//
// ledger:RL-push-clear-read-elsewhere

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/utils/background_push.dart';
import 'package:liza/utils/push_helper.dart';

import 'per_user_fake_api.dart';
import 'test_client.dart';

const _userA = '@aleksandr.novokshonov:synapse.liza.laba.prodamus.tech';
const _userB = '@sasha.second:nadezhda.liza.ru';
const _read = '!read:synapse.liza.laba.prodamus.tech';
const _unread = '!unread:synapse.liza.laba.prodamus.tech';
const _roomB = '!b:nadezhda.liza.ru';

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

Future<void> _room(Client c, String roomId, {required int unread}) =>
    c.handleSync(
      SyncUpdate(
        nextBatch: 'b-$roomId-$unread',
        rooms: RoomsUpdate(
          join: {
            roomId: JoinedRoomUpdate(
              unreadNotifications: UnreadNotificationCounts(
                notificationCount: unread,
                highlightCount: 0,
              ),
              state: [
                MatrixEvent(
                  type: EventTypes.RoomCreate,
                  eventId: '\$create-$roomId',
                  senderId: c.userID!,
                  originServerTs: DateTime.now(),
                  content: {'creator': c.userID},
                  stateKey: '',
                ),
              ],
              timeline: TimelineUpdate(
                events: [
                  MatrixEvent(
                    type: EventTypes.Message,
                    eventId: '\$m-$roomId',
                    senderId: '@nadezhda:nadezhda.liza.ru',
                    originServerTs: DateTime.now(),
                    content: {'msgtype': 'm.text', 'body': 'привет'},
                  ),
                ],
              ),
            ),
          },
        ),
      ),
    );

Map<String, dynamic> _clearing(String clientName, {int unread = 1}) => {
      'aps': {'content-available': 1},
      'counts': {'unread': unread},
      'liza_clear': 1,
      pushClientNameKey: clientName,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client a;
  late Client b;

  setUp(() async {
    a = await _client('Liza ios', _userA);
    b = await _client('Liza-1786629781847', _userB);
    await _room(a, _read, unread: 0);
    await _room(a, _unread, unread: 2);
    await _room(b, _roomB, unread: 1);
  });

  tearDown(() async {
    await a.dispose();
    await b.dispose();
  });

  test('маркер clearing-пуша распознаётся во всех формах APNs userInfo', () {
    for (final v in [1, '1', true]) {
      expect(isClearingPush({'liza_clear': v}), isTrue, reason: '$v');
    }
    for (final raw in [
      <String, dynamic>{},
      {'liza_clear': 0},
      {'event_id': r'$e', 'room_id': _read},
    ]) {
      expect(isClearingPush(raw), isFalse, reason: '$raw');
    }
  });

  test('apple-pusher объявляет capability, android — нет (Sygnal шлёт '
      'clearing только объявившим)', () {
    final apple = BackgroundPush.pusherAdditionalProperties(
      'Liza ios',
      dataMessage: 'ios',
      apple: true,
    );
    final android = BackgroundPush.pusherAdditionalProperties(
      'Liza android',
      dataMessage: 'android',
      apple: false,
    );
    expect(apple['default_payload'][pushClearCapabilityKey], 1);
    expect(
      (android['default_payload'] as Map).containsKey(pushClearCapabilityKey),
      isFalse,
    );
  });

  // AC:RL-push-clear-read-elsewhere/1
  test('clearing-пуш: снимаются ровно прочитанные показанные чаты; '
      'непрочитанный и неизвестный клиенту — остаются', () async {
    final push = BackgroundPush.forTest([a]);
    final cancelled = <String>[];
    final synced = <String>[];
    var done = 0;
    final dropped = await push.handleClearingPush(
      _clearing('Liza ios'),
      sync: (c) async => synced.add(c.clientName),
      delivered: () async => [_read, _unread, '!unknown:x', _read],
      cancel: (roomId) async => cancelled.add(roomId),
      done: (_) async => done++,
    );
    expect(synced, ['Liza ios']);
    expect(cancelled, [_read]);
    expect(dropped, [_read]);
    expect(done, 1);
  });

  // AC:RL-push-clear-read-elsewhere/2
  test('clearingDone ровно один раз ∀ исход sync {успел, ошибка, завис} '
      'и при сбое самой чистки', () async {
    final push = BackgroundPush.forTest([a]);
    final outcomes = <String, Future<void> Function(Client)>{
      'успел': (_) async {},
      'ошибка': (_) async => throw Exception('sync failed'),
      'завис': (_) => Completer<void>().future,
    };
    for (final entry in outcomes.entries) {
      var done = 0;
      final cancelled = <String>[];
      await push.handleClearingPush(
        _clearing('Liza ios'),
        sync: entry.value,
        syncTimeout: const Duration(milliseconds: 50),
        delivered: () async => [_read, _unread],
        cancel: (roomId) async => cancelled.add(roomId),
        done: (_) async => done++,
      );
      expect(done, 1, reason: entry.key);
      expect(cancelled, [_read], reason: entry.key);
    }

    var done = 0;
    await push.handleClearingPush(
      _clearing('Liza ios'),
      sync: (_) async {},
      delivered: () async => throw Exception('natively unavailable'),
      done: (_) async => done++,
    );
    expect(done, 1, reason: 'сбой чистки');
  });

  // AC:RL-push-clear-read-elsewhere/2
  test('clearingDone отпускает окно ИМЕННО своего пуша: id от натива '
      'возвращается как есть ∀ пуш {A, B}', () async {
    final push = BackgroundPush.forTest([a]);
    final released = <String?>[];
    for (final id in ['A', 'B']) {
      await push.handleClearingPush(
        {..._clearing('Liza ios'), pushClearIdKey: id},
        sync: (_) async {},
        delivered: () async => const [],
        done: (clearingId) async => released.add(clearingId),
      );
    }
    expect(released, ['A', 'B']);
  });

  // AC:RL-push-clear-read-elsewhere/3
  test('мультиаккаунт: clearing аккаунта A синкает только A и не трогает '
      'непрочитанное B', () async {
    final push = BackgroundPush.forTest([a, b]);
    final synced = <String>[];
    final cancelled = <String>[];
    await push.handleClearingPush(
      _clearing('Liza ios'),
      sync: (c) async => synced.add(c.clientName),
      delivered: () async => [_read, _roomB],
      cancel: (roomId) async => cancelled.add(roomId),
      done: (_) async {},
    );
    expect(synced, ['Liza ios']);
    expect(cancelled, [_read]);
  });

  // AC:RL-push-clear-read-elsewhere/4
  test('clearing-пуш идёт мимо pushHelper, гейта баннера и дедупа', () async {
    final push = BackgroundPush.forTest([a]);
    final delivered = <String>[];
    final cleared = <Map<String, dynamic>>[];
    final raw = _clearing('Liza ios', unread: 0);
    for (var i = 0; i < 2; i++) {
      final out = await push.handleApnsMessage(
        raw,
        deliver: (r) async => delivered.add('$r'),
        retract: (_) async => fail('retract по clearing-пушу'),
        clearing: (r) async => cleared.add(r),
      );
      expect(out.decision, ApnsBannerDecision.noEvent);
      expect(out.duplicate, isFalse);
    }
    expect(cleared.length, 2, reason: 'каждый clearing обработан, не дедуп');
    expect(delivered, isEmpty, reason: 'pushHelper (cancelAll) не зовётся');
    expect(push.isNativelyReceived(''), isFalse);
  });

  // AC:RL-push-clear-read-elsewhere/5
  test('живой клиент: чат стал прочитанным между sync → его уведомления '
      'сняты; непрочитанный и чужой аккаунт — нет', () async {
    final push = BackgroundPush.forTest([a, b]);
    final cancelled = <String>[];
    Future<void> cancel(Client c, String roomId) async =>
        cancelled.add('${c.clientName}|$roomId');

    expect(
      await push.clearNotificationsOfRoomsReadSinceLastSync(a, cancel: cancel),
      isEmpty,
      reason: 'первый sync — только снимок',
    );
    await push.clearNotificationsOfRoomsReadSinceLastSync(b, cancel: cancel);

    // На другом устройстве прочитан _unread (квитанция приехала sync'ом).
    await _room(a, _unread, unread: 0);
    final read =
        await push.clearNotificationsOfRoomsReadSinceLastSync(a, cancel: cancel);
    await push.clearNotificationsOfRoomsReadSinceLastSync(b, cancel: cancel);

    expect(read, [_unread]);
    expect(cancelled, ['Liza ios|$_unread']);

    // Повторный sync без изменений — ничего не снимаем.
    await push.clearNotificationsOfRoomsReadSinceLastSync(a, cancel: cancel);
    expect(cancelled.length, 1);

    // Выход аккаунта: снимок забыт — первый sync нового входа только снимает
    // снимок, а не сравнивает со старой сессией.
    push.forgetReadSnapshot(a.clientName);
    expect(
      await push.clearNotificationsOfRoomsReadSinceLastSync(a, cancel: cancel),
      isEmpty,
    );
  });
}
