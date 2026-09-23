// ignore_for_file: depend_on_referenced_packages

// ledger:RL-group-content-protection
//
// Спека 2026-08-12: запрет копирования/пересылки/сохранения действует на всех,
// КРОМЕ модераторов и администраторов (PL >= 50). Порог понижен со 100 до 50 и
// применяется одинаково к каналам и групповым чатам.
//
// ⚠️ Смена поведения существующих каналов: модератор канала (PL 50) раньше был
// под запретом, теперь освобождён — принято сознательно.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/chat_topology.dart';

import 'test_client.dart';

void main() {
  group('contentProtected', () {
    test('участник без прав — контент закрыт', () {
      // AC:RL-group-content-protection/2: при включённом флаге и PL=0 контент закрыт
      expect(contentProtected(noForwards: true, ownPowerLevel: 0), isTrue);
    });

    test('PL 49 (на единицу ниже порога) — контент закрыт', () {
      // AC:RL-group-content-protection/2: при включённом флаге и PL<50 контент закрыт
      expect(contentProtected(noForwards: true, ownPowerLevel: 49), isTrue);
    });

    test('модератор (PL 50, ровно порог) — ограничений нет', () {
      // AC:RL-group-content-protection/3: при PL≥50 (модератор) ограничений нет
      expect(contentProtected(noForwards: true, ownPowerLevel: 50), isFalse);
    });

    test('админ (PL 100) — ограничений нет', () {
      // AC:RL-group-content-protection/3: при PL≥50 (админ) ограничений нет
      expect(contentProtected(noForwards: true, ownPowerLevel: 100), isFalse);
    });

    test('флаг выключен — ограничений нет ни у кого', () {
      expect(contentProtected(noForwards: false, ownPowerLevel: 0), isFalse);
    });
  });

  group('право переключать запрет (Room.canChangeStateEvent)', () {
    late Client client;
    late Room room;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
      room = Room(id: '!group:example.invalid', client: client);
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

    test('обычный участник (PL 0) при state_default 50 — переключить НЕЛЬЗЯ', () {
      setPowerLevels({
        'events_default': 0,
        'state_default': 50,
        'users_default': 0,
        'events': <String, Object?>{},
      });
      // AC:RL-group-content-protection/4: без права переключать (PL<state_default) тумблер неактивен
      expect(room.canChangeStateEvent(channelNoForwardsState), isFalse);
    });

    test('модератор (PL 50) при state_default 50 — переключить можно', () {
      setPowerLevels({
        'events_default': 0,
        'state_default': 50,
        'users_default': 0,
        'users': {client.userID!: 50},
        'events': <String, Object?>{},
      });
      // AC:RL-group-content-protection/4: с правом переключать (PL≥state_default) тумблер активен
      expect(room.canChangeStateEvent(channelNoForwardsState), isTrue);
    });
  });

  // LABA-2541. Флаг обязан действовать СРАЗУ после sync, без открытия таймлайна.
  // SDK применяет state в память partial-комнаты только для типов из
  // `Client.importantStateEvents`; неважные подтягивает `Room.postLoad()`,
  // который зовётся из `getTimeline()`. Пока тип не был важным,
  // `Room.noForwards` в partial-комнате читался как `false` — защита молча не
  // действовала на первом кадре чата, в треде по прямой ссылке, на экране
  // настроек и в изоляте пушей.
  group('флаг доезжает через sync (partial-комната)', () {
    late Client client;

    setUp(() async => client = await prepareTestClient(loggedIn: true));
    tearDown(() async => client.dispose());

    Future<Room> syncRoom({
      required String roomId,
      required bool enabled,
      bool withPowerLevels = true,
      String creatorId = '@creator:example.invalid',
    }) async {
      await client.handleSync(
        SyncUpdate(
          nextBatch: 'batch1',
          rooms: RoomsUpdate(
            join: {
              roomId: JoinedRoomUpdate(
                state: [
                  MatrixEvent(
                    type: EventTypes.RoomCreate,
                    eventId: '\$create',
                    senderId: creatorId,
                    originServerTs: DateTime.now(),
                    content: const {'room_version': '10'},
                    stateKey: '',
                  ),
                  MatrixEvent(
                    type: channelNoForwardsState,
                    eventId: '\$noforwards',
                    senderId: creatorId,
                    originServerTs: DateTime.now(),
                    content: {'enabled': enabled},
                    stateKey: '',
                  ),
                  if (withPowerLevels)
                    MatrixEvent(
                      type: EventTypes.RoomPowerLevels,
                      eventId: '\$pl',
                      senderId: creatorId,
                      originServerTs: DateTime.now(),
                      content: const {
                        'users_default': 0,
                        'state_default': 50,
                      },
                      stateKey: '',
                    ),
                ],
              ),
            },
          ),
        ),
      );
      return client.getRoomById(roomId)!;
    }

    test('защита включена сразу после sync, без открытия таймлайна', () async {
      final room = await syncRoom(
        roomId: '!protected:example.invalid',
        enabled: true,
      );

      // Комната ИМЕННО partial — иначе тест доказывал бы не тот путь.
      expect(
        room.partial,
        isTrue,
        reason: 'таймлайн не открывали, postLoad не вызывали',
      );
      // AC:RL-group-content-protection/6: флаг доезжает до памяти partial-комнаты
      expect(room.getState(channelNoForwardsState), isNotNull);
      expect(room.noForwards, isTrue);
      expect(room.isContentProtected, isTrue);
    });

    test('флаг выключен — защиты нет и после sync', () async {
      final room = await syncRoom(
        roomId: '!open:example.invalid',
        enabled: false,
      );
      // AC:RL-group-content-protection/6: обратный кейс — гейт не «всегда true»
      expect(room.noForwards, isFalse);
      expect(room.isContentProtected, isFalse);
    });

    test('без m.room.power_levels отказ идёт в БЕЗОПАСНУЮ сторону', () async {
      // `m.room.power_levels` НЕ входит ни в дефолтный набор важных типов SDK,
      // ни в наш — в partial-комнате его в памяти нет, и `ownPowerLevel` падает
      // на fallback «создатель→100 / прочие→0». Это осознанный fail-CLOSED:
      // участник закрыт, а не открыт. Не «чинить» повышением power_levels в
      // importantStateEvents — там blast radius на каждую комнату (транзиентно
      // нулевой PL снял бы права админа по всему клиенту).
      final room = await syncRoom(
        roomId: '!nopl:example.invalid',
        enabled: true,
        withPowerLevels: false,
      );
      // AC:RL-group-content-protection/8: не-создатель закрыт
      expect(room.ownPowerLevel, 0);
      expect(room.isContentProtected, isTrue);
    });

    test('создатель комнаты освобождён и в partial-комнате', () async {
      final room = await syncRoom(
        roomId: '!mine:example.invalid',
        enabled: true,
        withPowerLevels: false,
        creatorId: client.userID!,
      );
      // AC:RL-group-content-protection/8: создатель (fallback PL 100) свободен
      expect(room.ownPowerLevel, 100);
      expect(room.isContentProtected, isFalse);
    });
  });

  group('парность наборов importantStateEvents', () {
    String compact(String path) {
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Тест должен запускаться из clients/flutter/',
      );
      return file.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
    }

    test('тип флага объявлен и в проде, и в тестовом клиенте', () {
      // Набор дублируется в двух файлах. Разъедутся — тесты будут гонять НЕ ТОТ
      // sync-путь, что живёт в проде, и покажут ложную картину.
      for (final path in const [
        'lib/utils/client_manager.dart',
        'test/utils/test_client.dart',
      ]) {
        // AC:RL-group-content-protection/7: наборы важных Liza-типов совпадают
        final source = compact(path);
        expect(
          source.contains('com.liza.chat.topology'),
          isTrue,
          reason: '$path потерял com.liza.chat.topology',
        );
        expect(
          source.contains('com.liza.chat.hidden_members'),
          isTrue,
          reason: '$path потерял com.liza.chat.hidden_members',
        );
        expect(
          source.contains('com.liza.channel.no_forwards') ||
              source.contains('channelNoForwardsState'),
          isTrue,
          reason:
              '$path потерял запрет сохранения контента: в partial-комнате '
              'флаг снова начнёт читаться как false (LABA-2541)',
        );
      }
    });
  });
}
