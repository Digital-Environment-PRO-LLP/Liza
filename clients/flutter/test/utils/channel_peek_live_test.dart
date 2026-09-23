// ledger:RL-channel-peek-live-feed
// AC:RL-channel-peek-live-feed/3
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/channel_peek.dart';
import 'test_client.dart';

void main() {
  group('живой хвост ленты (long-poll)', () {
    late Client client;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
    });

    tearDown(() async => client.dispose());

    test('новые события отдаются подписчику и токен продвигается', () async {
      final room = buildPeekRoom(client, '!channel:example.invalid');
      final received = <Event>[];
      var call = 0;

      final stream = ChannelPeekStream(
        client: client,
        roomId: '!channel:example.invalid',
        room: room,
        from: 's0',
        onEvents: received.addAll,
        // Подменяем сетевой вызов: тест проверяет ЦИКЛ, а не HTTP.
        fetch: (from, roomId) async {
          call++;
          if (call == 1) {
            return PeekEventsResponse(
              chunk: [
                MatrixEvent(
                  type: EventTypes.Message,
                  eventId: '\$live',
                  senderId: '@author:example.invalid',
                  originServerTs: DateTime.fromMillisecondsSinceEpoch(2000),
                  content: {'msgtype': 'm.text', 'body': 'новый пост'},
                ),
              ],
              end: 's1',
              start: from,
            );
          }
          // Второй виток: держим цикл, пока тест не остановит поток.
          await Future<void>.delayed(const Duration(milliseconds: 50));
          return PeekEventsResponse(chunk: const [], end: 's1', start: from);
        },
      );

      stream.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await stream.dispose();

      expect(received.map((e) => e.body), ['новый пост']);
      expect(stream.token, 's1', reason: 'токен обязан продвинуться на end');
    });

    test('dispose останавливает цикл', () async {
      final room = buildPeekRoom(client, '!channel:example.invalid');
      var calls = 0;

      final stream = ChannelPeekStream(
        client: client,
        roomId: '!channel:example.invalid',
        room: room,
        from: 's0',
        onEvents: (_) {},
        fetch: (from, roomId) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return PeekEventsResponse(chunk: const [], end: from, start: from);
        },
      );

      stream.start();
      await Future<void>.delayed(const Duration(milliseconds: 35));
      await stream.dispose();
      final afterDispose = calls;
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(
        calls,
        afterDispose,
        reason: 'после dispose новых запросов быть не должно',
      );
    });

    test('после dispose и повторного start цикл снова живёт', () async {
      // Сценарий приложения: ушли в фон (dispose) — вернулись (start).
      // Регрессия, которую ловим: `_stopped` выставлялся навсегда, а
      // `start()` делал `_loop ??= _run()`, поэтому мгновенно завершившийся
      // виток занимал `_loop` — лента после первого сворачивания замирала
      // без единого признака проблемы.
      final room = buildPeekRoom(client, '!channel:example.invalid');
      final received = <Event>[];
      var call = 0;

      final stream = ChannelPeekStream(
        client: client,
        roomId: '!channel:example.invalid',
        room: room,
        from: 's0',
        onEvents: received.addAll,
        fetch: (from, roomId) async {
          call++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return PeekEventsResponse(
            chunk: [
              MatrixEvent(
                type: EventTypes.Message,
                eventId: '\$post$call',
                senderId: '@author:example.invalid',
                originServerTs: DateTime.fromMillisecondsSinceEpoch(2000),
                content: {'msgtype': 'm.text', 'body': 'пост $call'},
              ),
            ],
            end: 's$call',
            start: from,
          );
        },
      );

      stream.start();
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await stream.dispose();
      final afterPause = received.length;
      final tokenAfterPause = stream.token;
      expect(afterPause, greaterThan(0), reason: 'до паузы лента шла');

      stream.start();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      await stream.dispose();

      expect(
        received.length,
        greaterThan(afterPause),
        reason: 'после возврата из фона лента обязана ожить',
      );
      expect(
        stream.token,
        isNot(tokenAfterPause),
        reason: 'токен продолжает продвигаться после рестарта',
      );
    });

    test('ошибка сети не роняет цикл, идёт backoff', () async {
      final room = buildPeekRoom(client, '!channel:example.invalid');
      var calls = 0;

      final stream = ChannelPeekStream(
        client: client,
        roomId: '!channel:example.invalid',
        room: room,
        from: 's0',
        onEvents: (_) {},
        retryDelay: const Duration(milliseconds: 10),
        fetch: (from, roomId) async {
          calls++;
          throw Exception('сеть отвалилась');
        },
      );

      stream.start();
      await Future<void>.delayed(const Duration(milliseconds: 45));
      await stream.dispose();

      expect(calls, greaterThan(1), reason: 'цикл обязан пережить ошибку');
      // Верхняя граница ловит регрессию «backoff выпилили»: за 45 мс с
      // retryDelay=10 мс корректный цикл делает ~4 вызова, а busy-loop без
      // задержки в catch — сотни. 15 — с запасом от флаки таймингов теста,
      // но на порядок ниже busy-loop-значений.
      expect(
        calls,
        lessThan(15),
        reason: 'без backoff (busy-loop) вызовов было бы на порядки больше',
      );
    });
  });
}
