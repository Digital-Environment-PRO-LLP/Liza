import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/chat_topology.dart';
import 'package:liza/utils/channel_discussion.dart';

void main() {
  test('channelChatType constant is "channel"', () {
    expect(channelChatType, 'channel');
  });

  test('константа типа обсуждения совпадает с серверной', () {
    expect(channelDiscussionChatType, 'channel_discussion');
  });

  group('discussionSettingsFor', () {
    test('открытый канал: чат public + world_readable', () {
      expect(discussionSettingsFor('public'), {
        'join_rule': 'public',
        'history_visibility': 'world_readable',
      });
    });

    test('закрытый канал: чат invite + shared', () {
      expect(discussionSettingsFor('invite'), {
        'join_rule': 'invite',
        'history_visibility': 'shared',
      });
    });

    test('неизвестное правило трактуем как закрытый канал', () {
      expect(discussionSettingsFor('knock'), {
        'join_rule': 'invite',
        'history_visibility': 'shared',
      });
      expect(discussionSettingsFor(null), {
        'join_rule': 'invite',
        'history_visibility': 'shared',
      });
    });
  });

  group('isChannelPublic', () {
    test('только public считается открытым', () {
      expect(isChannelPublic('public'), isTrue);
      expect(isChannelPublic('invite'), isFalse);
      expect(isChannelPublic('knock'), isFalse);
      expect(isChannelPublic(null), isFalse);
    });
  });
}
