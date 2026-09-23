import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Пост в канале атрибутируется КАНАЛУ (аватар/имя комнаты), а не автору:
// сейчас админ видит под своими постами собственную аватарку.
// Структурный тест: сборка Event с полноценной Room в unit-тесте требует
// поднятого клиента; проверяем наличие ветки атрибуции в коде отрисовки.

void main() {
  group('атрибуция постов каналу', () {
    late String source;

    setUp(() {
      final file = File('lib/pages/chat/events/message.dart');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Тест должен запускаться из clients/flutter/',
      );
      source = file.readAsStringSync();
    });

    test('в message.dart есть предикат поста канала', () {
      expect(source.contains('isChannelPost'), isTrue);
    });

    test('предикат опирается на топологию комнаты (room.isChannel)', () {
      expect(
        source.contains('bool isChannelPost(Event event) => event.room.isChannel'),
        isTrue,
        reason: 'предикат должен быть чистым и брать тип из chat_topology',
      );
      expect(
        source.contains("import 'package:liza/utils/chat_topology.dart';"),
        isTrue,
      );
    });

    test('аватар канала берётся из комнаты, а не отправителя', () {
      expect(
        source.contains('event.room.avatar'),
        isTrue,
        reason: 'аватар поста канала — m.room.avatar, не user.avatarUrl',
      );
    });

    test('группировка подряд идущих сообщений не прячет атрибуцию канала', () {
      // В обычных чатах аватар скрывается при nextEventSameSender/ownMessage,
      // а заголовок — при nextEventSameSender. Для канала атрибуция обязана
      // остаться у каждого поста: у всех постов один и тот же sender-админ,
      // иначе аватар/имя канала не покажутся вовсе.
      // Пробелы схлопываем: перенос строк ставит dart format, а не автор.
      final compact = source.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        compact.contains(
          '!isChannelPost(event) && (nextEventSameSender || ownMessage)',
        ),
        isTrue,
        reason: 'жёлоб: распорка вместо аватара только для НЕ-канала',
      );
      expect(
        compact.contains('nextEventSameSender && !isChannelPost(event)'),
        isTrue,
        reason: 'заголовок: скрывается по группировке только для НЕ-канала',
      );
    });

    test('вся канальная логика ограничена предикатом isChannelPost', () {
      // Страховка от регресса в обычных чатах: room.avatar/getLocalizedDisplayname
      // не должны попадать в отрисовку сообщения вне канальных веток.
      final channelOnlyMarkers = <String>[
        'event.room.avatar',
        'event.room.getLocalizedDisplayname',
      ];
      for (final marker in channelOnlyMarkers) {
        var index = source.indexOf(marker);
        while (index != -1) {
          final windowStart = index - 600 < 0 ? 0 : index - 600;
          expect(
            source.substring(windowStart, index).contains('isChannelPost'),
            isTrue,
            reason: '«$marker» должен стоять внутри ветки isChannelPost',
          );
          index = source.indexOf(marker, index + marker.length);
        }
      }
    });
  });
}
