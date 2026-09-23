// Страж инварианта автозапуска цепочки голосовых/аудио (RL-audio-autoplay-chain).
//
// Проверяет ЧИСТЫЙ резолвер `nextAudioEventInChain` — «следующее подряд идущее
// аудио» — на реальных Event над списком в порядке newest-first (как
// `filterByVisibleInGui`).
//
// Auto-покрытие здесь: AC-1..6 (резолвер). Требующее живого плеера/звука —
// AC-7 (скорость), AC-8 (стоп-по-ошибке), AC-9 (пауза/тап), AC-10 (слышимый
// переход), AC-11 (loop-guard) — device/manual-ярус (см. RL-audio-autoplay-chain).

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/pages/chat/events/audio_autoplay_service.dart';

import '../../utils/test_client.dart';

// Страж реестра регрессии: ledger:RL-audio-autoplay-chain (см. tests/registry/).
void main() {
  late Client client;
  late Room room;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    room = Room(id: '!chain:example.invalid', client: client);
  });

  var ts = 2000;
  Event evt(
    String id, {
    required String type,
    required Map<String, dynamic> content,
    EventStatus status = EventStatus.synced,
  }) => Event(
    eventId: id,
    senderId: '@a:example.invalid',
    // originServerTs растёт с каждым событием — но порядок в списке задаём мы
    // сами (newest-first), как это делает filterByVisibleInGui.
    originServerTs: DateTime.fromMillisecondsSinceEpoch(ts++),
    type: type,
    content: content,
    room: room,
    status: status,
  );

  Event voice(String id, {EventStatus status = EventStatus.synced}) => evt(
    id,
    type: EventTypes.Message,
    content: {
      'msgtype': MessageTypes.Audio,
      'body': 'voice',
      'url': 'mxc://x/$id',
      'org.matrix.msc3245.voice': <String, dynamic>{},
    },
    status: status,
  );

  Event audioFile(String id) => evt(
    id,
    type: EventTypes.Message,
    content: {'msgtype': MessageTypes.Audio, 'body': 'song', 'url': 'mxc://x/$id'},
  );

  Event text(String id) => evt(
    id,
    type: EventTypes.Message,
    content: {'msgtype': MessageTypes.Text, 'body': 'hi'},
  );

  Event image(String id) => evt(
    id,
    type: EventTypes.Message,
    content: {'msgtype': MessageTypes.Image, 'body': 'pic', 'url': 'mxc://x/$id'},
  );

  Event video(String id) => evt(
    id,
    type: EventTypes.Message,
    content: {'msgtype': MessageTypes.Video, 'body': 'clip', 'url': 'mxc://x/$id'},
  );

  Event fileMsg(String id) => evt(
    id,
    type: EventTypes.Message,
    content: {'msgtype': MessageTypes.File, 'body': 'doc', 'url': 'mxc://x/$id'},
  );

  Event sticker(String id) =>
      evt(id, type: EventTypes.Sticker, content: {'body': 'st'});

  // Служебное событие членства — isCollapsedState == true (тип не Message).
  Event memberJoin(String id) => evt(
    id,
    type: EventTypes.RoomMember,
    content: {'membership': 'join'},
  );

  // Список newest-first: индекс 0 — самое новое (хронологически последнее).
  // «Следующее» после X = более новое = МЕНЬШИЙ индекс.

  test(
      'AC-1: три голосовых подряд — цепочка проходит все переходы, стоп в конце '
      '— AC:RL-audio-autoplay-chain/1', () {
    final v3 = voice('\$v3'), v2 = voice('\$v2'), v1 = voice('\$v1');
    final events = [v3, v2, v1]; // newest-first: v3 самое новое

    expect(nextAudioEventInChain(events, '\$v1')?.eventId, '\$v2');
    expect(nextAudioEventInChain(events, '\$v2')?.eventId, '\$v3');
    expect(nextAudioEventInChain(events, '\$v3'), isNull); // v3 — самое новое
  });

  test('AC-2: разрыв на КАЖДОМ типе не-аудио между аудио — AC:RL-audio-autoplay-chain/2', () {
    for (final breaker in [
      text('\$b'),
      image('\$b'),
      video('\$b'),
      fileMsg('\$b'),
      sticker('\$b'),
    ]) {
      final v2 = voice('\$v2'), v1 = voice('\$v1');
      // newest-first: [v2, breaker, v1] → после v1 идёт breaker → стоп.
      final events = [v2, breaker, v1];
      expect(
        nextAudioEventInChain(events, '\$v1'),
        isNull,
        reason: 'разрыв на ${breaker.type}/${breaker.content['msgtype']}',
      );
    }
  });

  test('AC-3: collapsed-state (вступление) между аудио НЕ рвёт цепочку — AC:RL-audio-autoplay-chain/3', () {
    final v2 = voice('\$v2'), v1 = voice('\$v1');
    final events = [v2, memberJoin('\$m'), v1]; // служебное перешагивается
    expect(nextAudioEventInChain(events, '\$v1')?.eventId, '\$v2');
  });

  test('AC-4: смешанная цепочка голосовое → музыка → голосовое — AC:RL-audio-autoplay-chain/4', () {
    final v2 = voice('\$v2'), song = audioFile('\$song'), v1 = voice('\$v1');
    final events = [v2, song, v1]; // newest-first
    expect(nextAudioEventInChain(events, '\$v1')?.eventId, '\$song');
    expect(nextAudioEventInChain(events, '\$song')?.eventId, '\$v2');
    expect(nextAudioEventInChain(events, '\$v2'), isNull);
  });

  test('AC-5: последнее аудио в чате → null без ошибки — AC:RL-audio-autoplay-chain/5', () {
    final v1 = voice('\$v1'), t = text('\$t');
    final events = [v1, t]; // v1 самое новое
    expect(nextAudioEventInChain(events, '\$v1'), isNull);
  });

  test('AC-6: неотправленное (sending/error) не берётся как следующее — AC:RL-audio-autoplay-chain/6', () {
    final sending = voice('\$vs', status: EventStatus.sending);
    final v1 = voice('\$v1');
    expect(nextAudioEventInChain([sending, v1], '\$v1'), isNull);

    final errored = voice('\$ve', status: EventStatus.error);
    expect(nextAudioEventInChain([errored, v1], '\$v1'), isNull);
  });

  test('неизвестный currentEventId → null', () {
    final events = [voice('\$v2'), voice('\$v1')];
    expect(nextAudioEventInChain(events, '\$nope'), isNull);
  });

  // Контроль «страж ловит регресс»: если бы «строго подряд» ослабили до
  // «ближайшее аудио ниже сквозь не-аудио», AC-2 позеленел бы ложно. Проверяем,
  // что при наличии не-аудио прямо перед следующим аудио результат именно null,
  // а не перескок.
  test('red-proof: перескок через текст к аудио НЕ происходит', () {
    final v2 = voice('\$v2'), v1 = voice('\$v1');
    final events = [v2, text('\$t'), v1];
    final next = nextAudioEventInChain(events, '\$v1');
    expect(next, isNull);
    expect(next?.eventId, isNot('\$v2'));
  });
}
