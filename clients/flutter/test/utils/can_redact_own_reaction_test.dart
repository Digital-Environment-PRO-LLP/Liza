// ignore_for_file: depend_on_referenced_packages

// ledger:RL-channel-reaction-redaction-powerlevel
//
// Баг 2026-08-01. В канале подписчик СТАВИЛ реакцию (порог m.reaction: 0
// бэкфиллен), но СНЯТЬ не мог: сервер отдавал M_FORBIDDEN, клиент показывал
// «Нет прав доступа». Причина: снятие реакции — это отправка события
// m.room.redaction, а его порог в power_levels.events отсутствовал и
// наследовал events_default: 100 (реальный канал
// !imFpwmDxzbZyFMaFtN:nadezhda.liza.ru).
//
// Клиентский гейт нужен для СТАРЫХ каналов, которых не догнал бэкфилл:
// реакция там просто не должна быть снимаемой, вместо диалога ошибки.

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/chat_topology.dart';

import 'test_client.dart';

void main() {
  group('canRedactOwnAt (чистая функция)', () {
    test('подписчик снимает свою реакцию при открытом пороге', () {
      expect(canRedactOwnAt(ownPowerLevel: 0, redactionThreshold: 0), isTrue);
    });

    test('порог 100 (наследован от events_default канала) отсекает подписчика', () {
      expect(canRedactOwnAt(ownPowerLevel: 0, redactionThreshold: 100), isFalse);
    });

    test('владелец канала снимает свою реакцию даже на старом канале', () {
      expect(
        canRedactOwnAt(ownPowerLevel: 100, redactionThreshold: 100),
        isTrue,
      );
    });

    test('ровно на пороге — можно', () {
      expect(canRedactOwnAt(ownPowerLevel: 50, redactionThreshold: 50), isTrue);
    });
  });

  group('Room.canRedactOwnReaction', () {
    late Client client;
    late Room room;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
      room = Room(id: '!channel:example.invalid', client: client);
    });

    tearDown(() async {
      await client.dispose(closeDatabase: true);
    });

    void setPowerLevels(Map<String, Object?> content) {
      room.setState(
        Event(
          eventId: '\$pl',
          senderId: '@creator:example.invalid',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
          type: EventTypes.RoomPowerLevels,
          content: content,
          room: room,
          stateKey: '',
        ),
      );
    }

    test('старый канал без порога m.room.redaction — снять НЕЛЬЗЯ', () {
      // Точный снимок power_levels продового канала до фикса.
      setPowerLevels({
        'events_default': 100,
        'state_default': 50,
        'users_default': 0,
        'redact': 50,
        'ban': 50,
        'kick': 50,
        'events': {'m.reaction': 0, 'm.room.avatar': 50},
      });
      expect(
        room.canRedactOwnReaction,
        isFalse,
        reason: 'порог наследует events_default: 100 → сервер вернёт M_FORBIDDEN',
      );
      expect(
        room.canSendReaction,
        isTrue,
        reason: 'поставить реакцию при этом можно — в этом и была асимметрия',
      );
    });

    test('починенный канал с m.room.redaction: 0 — снять можно', () {
      setPowerLevels({
        'events_default': 100,
        'state_default': 50,
        'users_default': 0,
        'redact': 50,
        'events': {'m.reaction': 0, 'm.room.redaction': 0},
      });
      expect(room.canRedactOwnReaction, isTrue);
    });

    test('обычный чат (events_default: 0) — снять можно без явного порога', () {
      setPowerLevels({
        'events_default': 0,
        'state_default': 50,
        'users_default': 0,
        'redact': 50,
        'events': <String, Object?>{},
      });
      expect(room.canRedactOwnReaction, isTrue);
    });

    test('владелец канала (PL 100) снимает свою реакцию и на старом канале', () {
      setPowerLevels({
        'events_default': 100,
        'users_default': 0,
        'redact': 50,
        'users': {client.userID!: 100},
        'events': {'m.reaction': 0},
      });
      expect(room.canRedactOwnReaction, isTrue);
    });

    test('гейт читает events[m.room.redaction], а НЕ top-level redact', () {
      // redact: 50 (право на ЧУЖИЕ события) не должен закрывать снятие СВОЕЙ
      // реакции, если порог отправки редакции открыт.
      setPowerLevels({
        'events_default': 100,
        'users_default': 0,
        'redact': 50,
        'events': {'m.room.redaction': 0},
      });
      expect(room.canRedactOwnReaction, isTrue);
    });
  });
}
