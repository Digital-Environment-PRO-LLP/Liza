// ignore_for_file: depend_on_referenced_packages

// Страж нативного гейта подавления APNs-баннера (жалоба 2026-09-16: пуш приехал
// через 8 минут, уже после прочтения). Проверяет РЕАЛЬНЫЙ предикат
// `BackgroundPush.shouldSuppressNativeBanner`, который зовёт натив
// (AppDelegate.willPresent) перед показом.
//
// Ключевой инвариант: подавляем ТОЛЬКО доказуемо лишний баннер. Штатный случай
// «пуш обогнал sync» (события клиент ещё не знает) обязан ПОКАЗАТЬ баннер —
// иначе гейт проглотит новые сообщения, что хуже исходной жалобы.
//
// ledger:RL-macos-push-banner-read-suppress

import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/utils/background_push.dart';

import 'per_user_fake_api.dart';
import 'test_client.dart';

const _userA = '@nadezhda.rozental:nadezhda.liza.ru';
const _room = '!room:nadezhda.liza.ru';

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

/// Кладёт в комнату событие [eventId]; [notificationCount] = 0 означает, что
/// пользователь всё прочитал.
Future<void> _syncEvent(
  Client c,
  String roomId,
  String eventId, {
  required int notificationCount,
}) =>
    c.handleSync(
      SyncUpdate(
        nextBatch: 'b-$eventId',
        rooms: RoomsUpdate(
          join: {
            roomId: JoinedRoomUpdate(
              unreadNotifications: UnreadNotificationCounts(
                notificationCount: notificationCount,
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
                    eventId: eventId,
                    senderId: '@daniel:nadezhda.liza.ru',
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

Map<String, dynamic> _push(String eventId) => {
      'room_id': _room,
      'event_id': eventId,
      'sender': '@daniel:nadezhda.liza.ru',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Client a;
  late BackgroundPush push;

  setUp(() async {
    a = await _client('Liza-1786629781847', _userA);
    push = BackgroundPush.forTest([a]);
  });

  tearDown(() async => a.dispose());

  // AC:RL-macos-push-banner-read-suppress/1
  test('событие известно клиенту и всё прочитано → баннер подавляем', () async {
    const eventId = '\$read-event';
    await _syncEvent(a, _room, eventId, notificationCount: 0);

    expect(await push.shouldSuppressNativeBanner(_push(eventId)), isTrue);
  });

  // AC:RL-macos-push-banner-read-suppress/2
  // AC:RL-macos-push-banner-read-suppress/12 — известный предел: гейт комнатный,
  // прочитанность события A при непрочитанном B в той же комнате не различаем.
  test('событие известно, но комната НЕ прочитана → баннер показываем',
      () async {
    const eventId = '\$unread-event';
    await _syncEvent(a, _room, eventId, notificationCount: 3);

    expect(await push.shouldSuppressNativeBanner(_push(eventId)), isFalse);
  });

  // AC:RL-macos-push-banner-read-suppress/3
  // Red-proof главного риска: пуш штатно обгоняет /sync. Если предикат смотрит
  // только на «непрочитанность комнаты», он подавит НОВОЕ сообщение.
  test('пуш обогнал sync (событие клиенту неизвестно) → баннер показываем даже '
      'при нулевом счётчике непрочитанных', () async {
    await _syncEvent(a, _room, '\$old-read', notificationCount: 0);

    expect(
      await push.shouldSuppressNativeBanner(_push('\$brand-new-event')),
      isFalse,
    );
  });

  // AC:RL-macos-push-banner-read-suppress/4
  test('комната клиенту неизвестна → баннер показываем', () async {
    expect(
      await push.shouldSuppressNativeBanner({
        'room_id': '!unknown:nadezhda.liza.ru',
        'event_id': '\$whatever',
      }),
      isFalse,
    );
  });

  // AC:RL-macos-push-banner-read-suppress/5
  test('баннер уже нарисован локальным уведомлением → дубль подавляем '
      'даже без знания комнаты', () async {
    const eventId = '\$locally-shown';
    push.markLocallyShown(eventId);

    expect(await push.shouldSuppressNativeBanner(_push(eventId)), isTrue);
  });

  // AC:RL-macos-push-banner-read-suppress/6
  test('counts-only пуш (без event_id) гейт не трогает', () async {
    expect(
      await push.shouldSuppressNativeBanner({'room_id': _room}),
      isFalse,
    );
  });

  // AC:RL-macos-push-banner-read-suppress/7
  test('память показанных событий ограничена и не течёт', () async {
    for (var i = 0; i < 250; i++) {
      push.markLocallyShown('\$e$i');
    }

    expect(push.isLocallyShown('\$e249'), isTrue);
    expect(push.isLocallyShown('\$e0'), isFalse,
        reason: 'самые старые id обязаны вытесняться');
  });
}
