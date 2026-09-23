import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/chat_topology.dart';
import 'package:liza/utils/stories/stories_extension.dart';

// Регресс 2026-07-30 (второй и третий очаг того же дефекта, что в
// channel_creation_powerlevels_test.dart). Synapse применяет
// powerLevelContentOverride через shallow-merge
// (`power_level_content.update(...)`), поэтому ключ `events` заменяется
// ЦЕЛИКОМ. Обе сторис-комнаты передавали `events` только с собственным
// порогом `com.liza.chat.topology`, стирая шаблонные защитные пороги — они
// падали на `state_default: 50`, и участник с PL 50 мог переписать
// `m.room.power_levels`, выдав себе админа, а заодно снять шифрование и
// history_visibility.
void main() {
  group('ensureMyStoriesRoom: власть над сторис-комнатой пользователя', () {
    Map<String, Object?> events() =>
        myStoriesRoomPowerLevelOverride()['events']! as Map<String, Object?>;

    test('своя защита com.liza.chat.topology сохранена (PL 100)', () {
      expect(events()['com.liza.chat.topology'], 100);
    });

    test('перечислены ВСЕ шаблонные пороги Synapse, не ниже шаблонных', () {
      final actual = events();
      for (final entry in synapseDefaultEventPowerLevels.entries) {
        expect(
          actual.containsKey(entry.key),
          isTrue,
          reason: '${entry.key} стёрт shallow-merge и упадёт на state_default 50',
        );
        expect(
          actual[entry.key] as int,
          greaterThanOrEqualTo(entry.value as int),
          reason: 'порог ${entry.key} занижен относительно шаблона Synapse',
        );
      }
    });

    test('m.room.power_levels и m.room.encryption недоступны PL 50', () {
      final actual = events();
      expect(actual['m.room.power_levels'] as int, greaterThanOrEqualTo(100));
      expect(actual['m.room.encryption'] as int, greaterThanOrEqualTo(100));
    });

    test('участник (PL 50) не проходит ни по одному защитному порогу', () {
      const memberPowerLevel = 50;
      const protectedEvents = [
        'm.room.power_levels',
        'm.room.history_visibility',
        'm.room.tombstone',
        'm.room.server_acl',
        'm.room.encryption',
      ];
      final actual = events();
      for (final type in protectedEvents) {
        expect(
          memberPowerLevel >= (actual[type]! as int),
          isFalse,
          reason: 'участник не должен иметь права на $type в сторис-комнате',
        );
      }
    });
  });

  group('ensureChannelStoriesRoom: власть над сторис-комнатой канала', () {
    Map<String, Object?> override() => channelStoriesRoomPowerLevelOverride();
    Map<String, Object?> events() =>
        override()['events']! as Map<String, Object?>;

    test('events_default: 100 сохранён — постить может только админ', () {
      expect(override()['events_default'], 100);
    });

    test('своя защита com.liza.chat.topology сохранена (PL 100)', () {
      expect(events()['com.liza.chat.topology'], 100);
    });

    test('перечислены ВСЕ шаблонные пороги Synapse, не ниже шаблонных', () {
      final actual = events();
      for (final entry in synapseDefaultEventPowerLevels.entries) {
        expect(
          actual.containsKey(entry.key),
          isTrue,
          reason: '${entry.key} стёрт shallow-merge и упадёт на state_default 50',
        );
        expect(
          actual[entry.key] as int,
          greaterThanOrEqualTo(entry.value as int),
          reason: 'порог ${entry.key} занижен относительно шаблона Synapse',
        );
      }
    });

    test('m.room.power_levels и m.room.encryption недоступны PL 50', () {
      final actual = events();
      expect(actual['m.room.power_levels'] as int, greaterThanOrEqualTo(100));
      expect(actual['m.room.encryption'] as int, greaterThanOrEqualTo(100));
    });

    test('модератор (PL 50) не проходит ни по одному защитному порогу', () {
      const moderatorPowerLevel = 50;
      const protectedEvents = [
        'm.room.power_levels',
        'm.room.history_visibility',
        'm.room.tombstone',
        'm.room.server_acl',
        'm.room.encryption',
      ];
      final actual = events();
      for (final type in protectedEvents) {
        expect(
          moderatorPowerLevel >= (actual[type]! as int),
          isFalse,
          reason: 'модератор канала не должен иметь права на $type в сторис-комнате',
        );
      }
    });
  });
}
