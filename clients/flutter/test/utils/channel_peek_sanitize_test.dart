// ledger:RL-channel-peek-presence-safe-parse
// AC:RL-channel-peek-presence-safe-parse/1
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/channel_peek.dart';

void main() {
  group('sanitizePeekEventsJson — safe-parse ответа /events', () {
    Map<String, Object?> msg(String id) => {
      'type': 'm.room.message',
      'event_id': id,
      'sender': '@a:example.invalid',
      'origin_server_ts': 1000,
      'content': {'msgtype': 'm.text', 'body': 'hi'},
    };

    // Synapse подмешивает m.presence в /events — у него НЕТ sender/event_id.
    // Именно на нём падал `MatrixEvent.fromJson` (`json['sender'] as String`).
    final presence = {
      'type': 'm.presence',
      'content': {'presence': 'online', 'user_id': '@a:example.invalid'},
    };

    test(
      'presence-событие без sender/event_id выкидывается, лента доезжает',
      () {
        final response = sanitizePeekEventsJson({
          'chunk': [msg(r'$1'), presence, msg(r'$2')],
          'end': 's2',
        });
        expect(response.chunk?.map((e) => e.eventId), [r'$1', r'$2']);
        expect(response.end, 's2');
      },
    );

    test('RED-proof: сырой fromJson на presence бросил бы TypeError', () {
      // Без sanitize сырой парсинг падает — фиксируем, что чистка это и лечит.
      expect(
        () => sanitizePeekEventsJson({
          'chunk': [presence],
          'end': 's1',
        }),
        returnsNormally,
      );
      final r = sanitizePeekEventsJson({
        'chunk': [presence],
        'end': 's1',
      });
      expect(r.chunk, isEmpty);
    });

    test('пустой/отсутствующий chunk не роняет', () {
      expect(sanitizePeekEventsJson({'end': 's'}).chunk, isNull);
      expect(sanitizePeekEventsJson({'chunk': <Object?>[]}).chunk, isEmpty);
    });
  });
}
