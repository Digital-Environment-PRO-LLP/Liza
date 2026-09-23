// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:liza/utils/pending_send_echo.dart';

import 'test_client.dart';

/// ledger:RL-media-send-instant-bubble
///
/// Баг (жалоба 2026-09-03, покадровый разбор записи экрана Samsung S24):
/// между тапом «Прислать» и появлением пузыря видео в ленте проходило 6.9 с,
/// из них 6.3 с экран был БЕЗ ЕДИНОГО индикатора — отправитель считал, что
/// отправка не сработала.
///
/// Корень: `room.sendFileEvent` кладёт pending-пузырь в ленту первым же
/// действием, но принимает УЖЕ ГОТОВЫЙ `MatrixFile` с байтами. Поэтому весь
/// тяжёлый путь (постер → транскод 720p → `readAsBytes`) шёл ДО него, и лента
/// узнавала об отправке последней.
///
/// Фикс: эмитим ТОТ ЖЕ placeholder сами и заранее, с тем же `txid`. Когда SDK
/// эмитнет свой, `Timeline._findEvent` матчит по `event_id` ИЛИ
/// `transaction_id` и заменяет событие НА МЕСТЕ.
void main() {
  late Client client;

  const roomId = '!video:example.invalid';
  const txid = 'txn-pending-echo-1';

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await client.dispose(closeDatabase: true);
  });

  SyncUpdate ourEcho({Map<String, dynamic>? extraContent}) =>
      buildPendingAttachmentSync(
        roomId: roomId,
        senderId: client.userID!,
        txid: txid,
        msgtype: MessageTypes.Video,
        name: '20260801_141619.mp4',
        info: {'mimetype': 'video/mp4', 'size': 45100000},
        extraContent: extraContent,
      );

  /// Ровно та форма, которую строит сам SDK внутри `sendFileEvent`
  /// (`matrix/lib/src/room.dart`). Пре-эмит обязан быть её зеркалом.
  SyncUpdate sdkEcho() => SyncUpdate(
    nextBatch: '',
    rooms: RoomsUpdate(
      join: {
        roomId: JoinedRoomUpdate(
          timeline: TimelineUpdate(
            events: [
              MatrixEvent(
                content: {
                  'msgtype': MessageTypes.Video,
                  'body': '20260801_141619.mp4',
                  'filename': '20260801_141619.mp4',
                  'info': {
                    'mimetype': 'video/mp4',
                    'size': 4200000,
                    'w': 720,
                    'h': 1280,
                    'duration': 24000,
                  },
                },
                type: EventTypes.Message,
                eventId: txid,
                senderId: client.userID!,
                originServerTs: DateTime.now(),
                unsigned: {
                  messageSendingStatusKey: EventStatus.sending.intValue,
                  'transaction_id': txid,
                },
              ),
            ],
          ),
        ),
      },
    ),
  );

  Future<List<Event>> timelineEvents() async {
    final room = client.getRoomById(roomId)!;
    final timeline = await room.getTimeline();
    return timeline.events.where((e) => e.eventId == txid).toList();
  }

  group('AC:RL-media-send-instant-bubble/1 — пузырь ДО тяжёлой подготовки', () {
    test('пре-эмит кладёт событие в ленту сразу, в статусе sending', () async {
      await emitPendingAttachment(client.getRoomById(roomId) ?? Room(id: roomId, client: client), ourEcho());
      final events = await timelineEvents();
      expect(events, hasLength(1));
      expect(events.single.status, EventStatus.sending);
      expect(events.single.messageType, MessageTypes.Video);
      expect(events.single.body, '20260801_141619.mp4');
    });

    test('несёт transaction_id — на нём держится замена на месте', () async {
      await emitPendingAttachment(Room(id: roomId, client: client), ourEcho());
      final events = await timelineEvents();
      expect(events.single.transactionId, txid);
    });
  });

  group('AC:RL-media-send-instant-bubble/3 — ровно N пузырей, не 2N', () {
    test('эмит SDK с тем же txid ЗАМЕНЯЕТ наш, а не добавляет второй',
        () async {
      final room = Room(id: roomId, client: client);
      await emitPendingAttachment(room, ourEcho());
      expect(await timelineEvents(), hasLength(1));

      // Через несколько секунд подготовка закончилась и SDK эмитнул своё.
      await client.database.transaction(() => client.handleSync(sdkEcho()));

      final events = await timelineEvents();
      expect(
        events,
        hasLength(1),
        reason: 'второй пузырь = дубль в ленте у отправителя',
      );
      // И это уже SDK-версия: с реальными размерами после транскода.
      final info = events.single.content.tryGetMap<String, Object?>('info');
      expect(info?['w'], 720);
      expect(info?['h'], 1280);
      expect(info?['duration'], 24000);
    });

    test('RED-PROOF: разъехавшееся зеркало ДАЛО БЫ два пузыря', () async {
      // Доказываем, что тест выше не зелёный «просто так»: если пре-эмит
      // перестанет использовать тот же txid как eventId (например, кто-то
      // сгенерирует свой id «чтобы не конфликтовать»), дедуп Timeline не
      // сработает и отправитель увидит ДВА пузыря на один файл.
      final divergent = SyncUpdate(
        nextBatch: '',
        rooms: RoomsUpdate(
          join: {
            roomId: JoinedRoomUpdate(
              timeline: TimelineUpdate(
                events: [
                  MatrixEvent(
                    content: {
                      'msgtype': MessageTypes.Video,
                      'body': '20260801_141619.mp4',
                      'info': const {'mimetype': 'video/mp4', 'size': 1},
                    },
                    type: EventTypes.Message,
                    eventId: 'txn-DIVERGED',
                    senderId: client.userID!,
                    originServerTs: DateTime.now(),
                    unsigned: {
                      messageSendingStatusKey: EventStatus.sending.intValue,
                      'transaction_id': 'txn-DIVERGED',
                    },
                  ),
                ],
              ),
            ),
          },
        ),
      );
      await emitPendingAttachment(Room(id: roomId, client: client), divergent);
      await client.database.transaction(() => client.handleSync(sdkEcho()));

      final room = client.getRoomById(roomId)!;
      final timeline = await room.getTimeline();
      final bubbles = timeline.events
          .where((e) => e.messageType == MessageTypes.Video)
          .toList();
      expect(
        bubbles,
        hasLength(2),
        reason: 'ровно этот дубль и предотвращает совпадение eventId == txid',
      );
    });
  });

  group('AC:RL-media-send-instant-bubble/4 — призрак не бессмертен', () {
    test('withdraw снимает пузырь, до которого подготовка не дошла', () async {
      final room = Room(id: roomId, client: client);
      await emitPendingAttachment(room, ourEcho());
      expect(await timelineEvents(), hasLength(1));

      await withdrawPendingAttachment(client.getRoomById(roomId)!, txid);

      expect(
        await timelineEvents(),
        isEmpty,
        reason: 'иначе на экране навсегда остаётся «отправляется…»',
      );
    });

    test('withdraw по несуществующему txid не бросает', () async {
      await emitPendingAttachment(Room(id: roomId, client: client), ourEcho());
      await withdrawPendingAttachment(
        client.getRoomById(roomId)!,
        'txn-never-existed',
      );
    });
  });

  group('зеркало SDK — форма события', () {
    test('альбомный extraContent уезжает и в content, и в unsigned', () {
      final update = ourEcho(
        extraContent: {
          'com.liza.gallery': {'id': 'g1', 'i': 0, 'n': 3, 'caption': 'привет'},
          'body': 'привет',
        },
      );
      final event =
          update.rooms!.join![roomId]!.timeline!.events!.single;

      // В content — чтобы лента сразу нарисовала альбомную сетку.
      expect(event.content['com.liza.gallery'], isA<Map<String, dynamic>>());
      expect(event.content['body'], 'привет');
      // В unsigned — как FileSendRequestCredentials.toJson() у SDK, иначе
      // повторная отправка потеряет альбом и подпись.
      expect(event.unsigned!['extra_content'], isA<Map<String, dynamic>>());
    });

    test('shrink_image_max_dimension зеркалит credentials SDK', () {
      final update = buildPendingAttachmentSync(
        roomId: roomId,
        senderId: '@me:example.invalid',
        txid: txid,
        msgtype: MessageTypes.Image,
        name: 'shot.png',
        info: {'mimetype': 'image/png', 'size': 1024},
        shrinkImageMaxDimension: 1600,
      );
      final event = update.rooms!.join![roomId]!.timeline!.events!.single;
      expect(event.unsigned!['shrink_image_max_dimension'], 1600);
    });

    test('без extraContent лишних ключей в unsigned нет', () {
      final update = ourEcho();
      final event = update.rooms!.join![roomId]!.timeline!.events!.single;
      expect(event.unsigned!.containsKey('extra_content'), isFalse);
      expect(
        event.unsigned!.containsKey('shrink_image_max_dimension'),
        isFalse,
      );
      expect(event.unsigned!['transaction_id'], txid);
      expect(
        event.unsigned![messageSendingStatusKey],
        EventStatus.sending.intValue,
      );
    });
  });

  group('AC:RL-media-send-instant-bubble/14 — пре-эмит в тред попадает в тред',
      () {
    const threadRoot = '\$thread-root-1';
    const threadLast = '\$thread-last-1';

    Future<List<Event>> allEvents() async {
      final room = client.getRoomById(roomId)!;
      final timeline = await room.getTimeline();
      return timeline.events;
    }

    test('несёт m.relates_to по формуле SDK (rel_type + is_falling_back)', () {
      final update = buildPendingAttachmentSync(
        roomId: roomId,
        senderId: client.userID!,
        txid: txid,
        msgtype: MessageTypes.Video,
        name: '20260801_141619.mp4',
        info: const {'mimetype': 'video/mp4', 'size': 45100000},
        threadRootEventId: threadRoot,
        threadLastEventId: threadLast,
      );
      final content = update.rooms!.join![roomId]!.timeline!.events!.single
          .content;
      final relates = content['m.relates_to'] as Map<String, Object?>?;
      expect(
        relates,
        isNotNull,
        reason: 'без m.relates_to фильтр ленты выбросит пузырь из треда',
      );
      expect(relates!['event_id'], threadRoot);
      expect(relates['rel_type'], RelationshipTypes.thread);
      expect(relates['is_falling_back'], isTrue);
      expect(
        (relates['m.in_reply_to'] as Map?)?['event_id'],
        threadLast,
        reason: 'зеркало room.dart: fallback-ответ на последнее в треде',
      );
    });

    test('виден в ленте треда и отсутствует в основной', () async {
      final room = Room(id: roomId, client: client);
      await emitPendingAttachment(
        room,
        buildPendingAttachmentSync(
          roomId: roomId,
          senderId: client.userID!,
          txid: txid,
          msgtype: MessageTypes.Video,
          name: '20260801_141619.mp4',
          info: const {'mimetype': 'video/mp4', 'size': 45100000},
          threadRootEventId: threadRoot,
          threadLastEventId: threadLast,
        ),
      );

      final events = await allEvents();
      final inThread = events
          .filterByVisibleInGui(threadId: threadRoot)
          .where((e) => e.eventId == txid);
      final inMain = events
          .filterByVisibleInGui()
          .where((e) => e.eventId == txid);

      expect(
        inThread,
        hasLength(1),
        reason: 'отправка в тред обязана показать пузырь В ТРЕДЕ',
      );
      expect(
        inMain,
        isEmpty,
        reason: 'и не должна засорять основную ленту на всё окно подготовки',
      );
    });

    test('без треда поведение прежнее: основная лента, m.relates_to нет', () async {
      final room = Room(id: roomId, client: client);
      await emitPendingAttachment(room, ourEcho());

      final events = await allEvents();
      expect(
        events.filterByVisibleInGui().where((e) => e.eventId == txid),
        hasLength(1),
      );
      expect(
        events.singleWhere((e) => e.eventId == txid).content
            .containsKey('m.relates_to'),
        isFalse,
      );
    });
  });

  group('AC:RL-media-send-instant-bubble/20 — якорь дрейфа SDK', () {
    test(
        'плейсхолдер sendFileEvent в текущей matrix НЕ несёт m.relates_to — '
        'починка апстрима обязана покраснить этот тест', () {
      // Наше зеркало сознательно кладёт тред РАНЬШЕ, чем это делает SDK: сам
      // SDK добавляет `m.relates_to` только в `sendEvent` (room.dart), а
      // плейсхолдер `sendFileEvent` идёт без него. Если апстрим когда-нибудь
      // починит свой плейсхолдер, пре-эмит начнёт дублировать поле и зеркало
      // придётся пересобрать — этот ассерт об этом и сообщит.
      final event = sdkEcho().rooms!.join![roomId]!.timeline!.events!.single;
      expect(
        event.content.containsKey('m.relates_to'),
        isFalse,
        reason: 'зеркало устарело: SDK-плейсхолдер начал нести тред сам',
      );
    });
  });
}
