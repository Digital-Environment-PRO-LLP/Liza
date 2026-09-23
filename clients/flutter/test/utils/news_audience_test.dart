// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/config/setting_keys.dart';
import 'package:liza/pages/chat_list/chat_list_item.dart';
import 'package:liza/pages/chat_list/unread_bubble.dart';
import 'package:liza/utils/background_push.dart';
import 'package:liza/utils/chat_topology.dart';
import 'package:liza/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:liza/utils/news_audience.dart';
import 'package:liza/utils/unseen_messages.dart';

import 'test_client.dart';

/// Страж реестра регрессии: ledger:RL-liza-news-platform-audience.
///
/// Адресный пост Liza News (`com.liza.news.audience.platforms`) на устройстве
/// другой платформы не виден нигде: лента, переход по ссылке, превью списка,
/// бейдж, пузырь непрочитанного. Серверный notificationCount при этом вырос —
/// он один на пользователя, — и клиент обязан его не показывать.
void main() {
  const newsBot = '@liza-news:bots.liza.ru';
  const roomId = '!news:bots.liza.ru';
  late Client client;

  // null — Windows/Linux/web: адресный пост им не виден никогда.
  const devices = <String, String>{
    'ios': 'ios',
    'macos': 'macos',
    'android': 'android',
    'windows/web/linux': '',
  };
  const audiences = <String, List<String>?>{
    'всем': null,
    'ios': ['ios'],
    'macos': ['macos'],
    'ios+macos': ['ios', 'macos'],
    'android': ['android'],
  };
  bool expectedVisible(String device, List<String>? audience) =>
      audience == null || audience.contains(device);

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    client = await prepareTestClient(loggedIn: true);
    client.backgroundSync = false;
    await client.abortSync();
  });

  tearDown(() async {
    debugNewsPlatformOverride = null;
    await client.dispose(closeDatabase: true);
  });

  Map<String, Object?> postContent(List<String>? audience) => {
    'msgtype': MessageTypes.Text,
    'body': 'Обновите Liza',
    if (audience != null) newsAudienceKey: {'platforms': audience},
  };

  /// Канал Liza News с постом в хвосте и серверным счётчиком +1.
  Future<Room> newsRoomWithPost(
    List<String>? audience, {
    String sender = newsBot,
  }) async {
    await client.handleSync(
      SyncUpdate(
        nextBatch: 'b-${audience?.join()}-$sender',
        rooms: RoomsUpdate(
          join: {
            roomId: JoinedRoomUpdate(
              unreadNotifications: UnreadNotificationCounts(
                notificationCount: 1,
                highlightCount: 0,
              ),
              state: [
                MatrixEvent(
                  type: EventTypes.RoomCreate,
                  eventId: '\$create',
                  senderId: newsBot,
                  originServerTs: DateTime.now(),
                  content: const {},
                  stateKey: '',
                ),
              ],
              timeline: TimelineUpdate(
                events: [
                  MatrixEvent(
                    type: EventTypes.Message,
                    eventId: '\$post-${audience?.join()}-$sender',
                    senderId: sender,
                    originServerTs: DateTime.now(),
                    content: postContent(audience),
                  ),
                ],
              ),
            ),
          },
        ),
      ),
    );
    return client.getRoomById(roomId)!;
  }

  // AC:RL-liza-news-platform-audience/11
  test(
    'лента: ∀ устройство × ∀ аудитория — пост виден ⇔ его платформа в метке; '
    'переход по ссылке не воскрешает',
    () async {
      for (final device in devices.entries) {
        debugNewsPlatformOverride = device.value;
        for (final audience in audiences.entries) {
          final room = await newsRoomWithPost(audience.value);
          final post = room.lastEvent!;
          final visible = expectedVisible(device.value, audience.value);
          final why = 'устройство=${device.key} аудитория=${audience.key}';
          expect(
            [post].filterByVisibleInGui(),
            hasLength(visible ? 1 : 0),
            reason: why,
          );
          expect(post.isVisibleInGui, visible, reason: why);
          expect(
            [post].filterByVisibleInGui(exceptionEventId: post.eventId),
            hasLength(visible ? 1 : 0),
            reason: '$why (exceptionEventId)',
          );
        }
      }
    },
  );

  // AC:RL-liza-news-platform-audience/12
  test(
    'список чатов: ∀ устройство × ∀ аудитория — превью, непрочитанное и бейдж '
    'есть ⇔ пост виден',
    () async {
      for (final device in devices.entries) {
        debugNewsPlatformOverride = device.value;
        for (final audience in audiences.entries) {
          final room = await newsRoomWithPost(audience.value);
          final visible = expectedVisible(device.value, audience.value);
          final why = 'устройство=${device.key} аудитория=${audience.key}';
          expect(
            previewEventFrom([room.lastEvent!]),
            visible ? isNotNull : isNull,
            reason: why,
          );
          expect(room.hasUnseenMessages, visible, reason: why);
          expect(room.countsTowardAppBadge, visible, reason: why);
          expect(room.hasNewsAudienceHiddenTail, !visible, reason: why);
        }
      }
    },
  );

  // AC:RL-liza-news-platform-audience/13
  testWidgets(
    'реальный UnreadBubble: скрытый пост не рисует «1», видимый — рисует',
    (tester) async {
      Future<bool> bubbleShowsOne(List<String>? audience) async {
        final room = await tester.runAsync(() => newsRoomWithPost(audience));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: UnreadBubble(room: room!)),
          ),
        );
        return find.text('1').evaluate().isNotEmpty;
      }

      debugNewsPlatformOverride = 'android';
      expect(await bubbleShowsOne(['ios', 'macos']), isFalse);
      expect(await bubbleShowsOne(['android']), isTrue);
      expect(await bubbleShowsOne(null), isTrue);
    },
  );

  // AC:RL-liza-news-platform-audience/14
  test(
    'метка от не-бота игнорируется; ручная пометка «непрочитано» остаётся',
    () async {
      debugNewsPlatformOverride = 'android';
      final spoofed = await newsRoomWithPost([
        'ios',
      ], sender: '@someone:x.invalid');
      expect(spoofed.lastEvent!.isHiddenByNewsAudience, isFalse);
      expect([spoofed.lastEvent!].filterByVisibleInGui(), hasLength(1));

      final hidden = await newsRoomWithPost(['ios']);
      expect(hidden.hasNewsAudienceHiddenTail, isTrue);
      // Пометку «непрочитано» приносит sync (account_data комнаты), как с сервера.
      await client.handleSync(
        SyncUpdate(
          nextBatch: 'b-marked',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(
                accountData: [
                  BasicEvent(
                    type: 'm.marked_unread',
                    content: {'unread': true},
                  ),
                ],
              ),
            },
          ),
        ),
      );
      expect(hidden.hasNewsAudienceHiddenTail, isFalse);
      expect(hidden.countsTowardAppBadge, isTrue);
    },
  );

  // AC:RL-liza-news-platform-audience/15
  test(
    'pusher несёт default_payload.platform для каждой платформы; без неё — нет',
    () {
      for (final platform in ['ios', 'macos', 'android']) {
        final props = BackgroundPush.pusherAdditionalProperties(
          'Liza-1786629781847',
          dataMessage: platform == 'android' ? 'android' : 'ios',
          apple: platform != 'android',
          platform: platform,
        );
        expect(props['default_payload']['platform'], platform);
      }
      final legacy = BackgroundPush.pusherAdditionalProperties(
        'Liza windows',
        dataMessage: 'ios',
        apple: false,
      );
      expect(
        (legacy['default_payload'] as Map).containsKey('platform'),
        isFalse,
      );
    },
  );

  test('ядро newsAudienceAllows: невалидная метка = пост для всех', () {
    expect(
      newsAudiencePlatforms({
        newsAudienceKey: {'platforms': []},
      }),
      isNull,
    );
    expect(newsAudiencePlatforms({newsAudienceKey: 'ios'}), isNull);
    expect(newsAudienceAllows(null, null), isTrue);
    expect(newsAudienceAllows(['ios'], null), isFalse);
  });
}
