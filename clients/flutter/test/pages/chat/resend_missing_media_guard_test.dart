// LABA-2239: голосовое «сначала не отправлялось, потом расплодилось, нажал
// отправить повторно — пропало». Корень «пропало»: у медиа в ошибке байты для
// повтора лежат в in-memory room.sendingFilePlaceholders[eventId]; SDK
// (matrix/room.dart:sendFileEvent) удаляет их ДАЖЕ после неудачной отправки, а
// перезапуск приложения очищает память. Тогда Event.sendAgain() вместо повтора
// зовёт cancelSend() и УДАЛЯЕТ сообщение. Клиент обязан это распознавать
// (isUnresendableMissingMedia) и блокировать «отправить повторно», а не терять
// данные молча.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/utils/file_description.dart';
import '../../utils/test_client.dart';

Event _pendingEvent(
  Room room, {
  required String msgtype,
  required EventStatus status,
  String eventId = 'txid-voice-1',
}) =>
    Event.fromMatrixEvent(
      MatrixEvent(
        content: {'msgtype': msgtype, 'body': 'voice.ogg'},
        type: EventTypes.Message,
        eventId: eventId,
        senderId: '@alice:example.invalid',
        originServerTs: DateTime.now(),
        unsigned: {'transaction_id': eventId},
      ),
      room,
      status: status,
    );

// ledger:RL-resend-missing-media-guard
void main() {
  late Client client;
  late Room room;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    room = Room(id: '!resend:example.invalid', client: client);
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  group('isUnresendableMissingMedia (LABA-2239)', () {
    test('медиа в ошибке без плейсхолдера → блокируем повтор', () {
      final event = _pendingEvent(
        room,
        msgtype: MessageTypes.Audio,
        status: EventStatus.error,
      );
      expect(room.sendingFilePlaceholders[event.eventId], isNull);
      expect(event.isUnresendableMissingMedia, isTrue);
    });

    test(
      'red-proof: реальный sendAgain() для такого события УДАЛЯЕТ его '
      '(cancelSend) и бросает — именно это блокирует наш гард',
      () async {
        final event = _pendingEvent(
          room,
          msgtype: MessageTypes.Audio,
          status: EventStatus.error,
        );
        final cancelled = <String>[];
        final sub = room.client.onCancelSendEvent.stream.listen(cancelled.add);
        await expectLater(event.sendAgain(), throwsA(isA<Exception>()));
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        // Событие ушло через cancelSend — то самое «пропало» из бага.
        expect(cancelled, contains(event.eventId));
      },
    );

    test('медиа в ошибке С плейсхолдером → повтор разрешён', () {
      final event = _pendingEvent(
        room,
        msgtype: MessageTypes.Audio,
        status: EventStatus.error,
      );
      room.sendingFilePlaceholders[event.eventId] = MatrixAudioFile(
        bytes: Uint8List.fromList([1, 2, 3]),
        name: 'voice.ogg',
      );
      expect(event.isUnresendableMissingMedia, isFalse);
    });

    test('текст в ошибке → не блокируем (плейсхолдер тут ни при чём)', () {
      final event = _pendingEvent(
        room,
        msgtype: MessageTypes.Text,
        status: EventStatus.error,
      );
      expect(event.isUnresendableMissingMedia, isFalse);
    });

    test('доставленное медиа (sent) → не блокируем', () {
      final event = _pendingEvent(
        room,
        msgtype: MessageTypes.Audio,
        status: EventStatus.synced,
      );
      expect(event.isUnresendableMissingMedia, isFalse);
    });

    test('медиа в процессе отправки (sending) → не блокируем', () {
      final event = _pendingEvent(
        room,
        msgtype: MessageTypes.Audio,
        status: EventStatus.sending,
      );
      expect(event.isUnresendableMissingMedia, isFalse);
    });

    test('стикер в ошибке без плейсхолдера → НЕ блокируем '
        '(SDK шлёт стикер через sendEvent, cancelSend не зовёт)', () {
      final event = _pendingEvent(
        room,
        msgtype: MessageTypes.Sticker,
        status: EventStatus.error,
      );
      expect(event.isUnresendableMissingMedia, isFalse);
    });
  });
}
