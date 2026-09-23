// ledger:RL-channel-peek-live-feed
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/channel_peek.dart';
import 'test_client.dart';

MatrixEvent _post(String id, String body, int ts) => MatrixEvent(
      type: EventTypes.Message,
      eventId: id,
      senderId: '@author:example.invalid',
      originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
      content: {'msgtype': 'm.text', 'body': body},
    );

void main() {
  test('таймлайн строится из peek-событий и принимает новые', () async {
    final client = await prepareTestClient(loggedIn: true);
    addTearDown(client.dispose);

    final room = buildPeekRoom(client, '!channel:example.invalid');
    final events = peekEventsToTimeline([_post('\$a', 'пост', 1000)], room);

    final timeline = buildPeekTimeline(room, events);

    expect(timeline.events, hasLength(1));
    expect(
      timeline.chunk.nextBatch,
      '',
      reason: 'непустой nextBatch включил бы isFragmentedTimeline '
          'и запретил новые события (timeline.dart:360-362)',
    );
    expect(
      timeline.allowNewEvent,
      isTrue,
      reason: 'живой хвост long-poll вставляется в этот же таймлайн',
    );
  });

  test('cancelSubscriptions гасит все подписки пересобранного таймлайна',
      () async {
    // Конструктор Timeline заводит ПЯТЬ подписок на клиентские стримы
    // (timeline.dart:332-351). Peek-лента пересобирается на каждый новый пост
    // long-poll, поэтому без парного cancelSubscriptions экран копил бы по 5
    // живых листенеров каждые ~30 с и держал бы их после ухода с экрана.
    final client = await prepareTestClient(loggedIn: true);
    addTearDown(client.dispose);

    final room = buildPeekRoom(client, '!channel:example.invalid');
    final events = peekEventsToTimeline([_post('\$a', 'пост', 1000)], room);

    final timeline = buildPeekTimeline(room, events);
    // Подписки заведены — иначе тест ниже был бы вечнозелёным по построению.
    expect(timeline.timelineSub, isNotNull);
    expect(timeline.historySub, isNotNull);
    expect(timeline.roomSub, isNotNull);
    expect(timeline.sessionIdReceivedSub, isNotNull);
    expect(timeline.cancelSendEventSub, isNotNull);

    timeline.cancelSubscriptions();

    // Отменённая подписка больше не доставляет события: живой таймлайн
    // добавил бы пришедшее в свой список, отменённый — нет.
    final live = buildPeekTimeline(room, [...events]);
    addTearDown(live.cancelSubscriptions);
    final incoming = peekEventsToTimeline([_post('\$b', 'новый', 3000)], room);
    client.onTimelineEvent.add(incoming.single);
    await Future<void>.delayed(Duration.zero);

    expect(
      timeline.events.map((e) => e.eventId),
      ['\$a'],
      reason: 'после cancelSubscriptions таймлайн глух к стриму',
    );
    expect(
      live.events.map((e) => e.eventId),
      contains('\$b'),
      reason: 'контроль: неотменённый таймлайн событие принимает — значит '
          'предыдущий ассерт проверяет отмену, а не отсутствие доставки',
    );
  });

  test('таймлайн отдаёт тот же список событий, что ему передали', () async {
    final client = await prepareTestClient(loggedIn: true);
    addTearDown(client.dispose);

    final room = buildPeekRoom(client, '!channel:example.invalid');
    final events = peekEventsToTimeline([
      _post('\$new', 'свежий', 2000),
      _post('\$old', 'старый', 1000),
    ], room);

    final timeline = buildPeekTimeline(room, events);

    // Порядок именно тот, что дал экран (reverse-лента: свежее первым) —
    // buildPeekTimeline ничего не пересортировывает.
    expect(
      timeline.events.map((e) => e.eventId),
      ['\$new', '\$old'],
    );
  });
}
