// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/channel_discussion.dart';

import 'test_client.dart';

void main() {
  test('countReplies counts in_reply_to to the mirror of the post', () {
    final events = [
      {'event_id': '\$mirror', 'content': {
        'com.liza.channel.post_ref': {'post_event_id': '\$post'}
      }},
      {'event_id': '\$c1', 'content': {
        'm.relates_to': {'m.in_reply_to': {'event_id': '\$mirror'}}
      }},
      {'event_id': '\$c2', 'content': {
        'm.relates_to': {'m.in_reply_to': {'event_id': '\$mirror'}}
      }},
      {'event_id': '\$other', 'content': {
        'm.relates_to': {'m.in_reply_to': {'event_id': '\$somethingelse'}}
      }},
    ];
    expect(countReplies(events, '\$post'), 2);
  });

  test('countReplies returns 0 when no mirror for the post', () {
    expect(countReplies(const [], '\$post'), 0);
  });

  group('countReplies — граничные случаи ленты', () {
    test('нет зеркала — ноль комментариев', () {
      expect(countReplies(const [], r'$post'), 0);
    });

    test('зеркало без ответов — ноль', () {
      final events = [
        {
          'event_id': r'$mirror',
          'content': {
            'com.liza.channel.post_ref': {'post_event_id': r'$post'},
          },
        },
      ];
      expect(countReplies(events, r'$post'), 0);
    });

    test('считает только ответы на СВОЁ зеркало', () {
      final events = [
        {
          'event_id': r'$mirror1',
          'content': {
            'com.liza.channel.post_ref': {'post_event_id': r'$post1'},
          },
        },
        {
          'event_id': r'$mirror2',
          'content': {
            'com.liza.channel.post_ref': {'post_event_id': r'$post2'},
          },
        },
        {
          'event_id': r'$c1',
          'content': {
            'm.relates_to': {
              'm.in_reply_to': {'event_id': r'$mirror1'},
            },
          },
        },
        {
          'event_id': r'$c2',
          'content': {
            'm.relates_to': {
              'm.in_reply_to': {'event_id': r'$mirror2'},
            },
          },
        },
      ];
      expect(countReplies(events, r'$post1'), 1);
      expect(countReplies(events, r'$post2'), 1);
    });
  });

  group('findMirrorEventId', () {
    test('находит зеркало нужного поста среди чужих', () {
      final events = [
        {
          'event_id': r'$mirrorA',
          'content': {
            'com.liza.channel.post_ref': {'post_event_id': r'$postA'},
          },
        },
        {
          'event_id': r'$mirrorB',
          'content': {
            'com.liza.channel.post_ref': {'post_event_id': r'$postB'},
          },
        },
      ];
      expect(findMirrorEventId(events, r'$postB'), r'$mirrorB');
    });

    test('обычный комментарий без post_ref зеркалом не считается', () {
      final events = [
        {
          'event_id': r'$c1',
          'content': {'body': 'просто сообщение'},
        },
      ];
      expect(findMirrorEventId(events, r'$post'), isNull);
    });
  });

  group('discussionRoomId — маркер удаления канала', () {
    late Client client;
    late Room room;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
      room = Room(id: '!chan:example.invalid', client: client);
    });

    tearDown(() async {
      await client.dispose(closeDatabase: true);
    });

    void setDiscussionState(Map<String, dynamic> content) {
      room.setState(
        Event(
          eventId: '\$discussion',
          senderId: '@creator:example.invalid',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
          type: channelDiscussionState,
          content: content,
          room: room,
          stateKey: '',
        ),
      );
    }

    test('обычная привязка отдаёт room_id', () {
      setDiscussionState({'room_id': '!disc:example.invalid'});
      expect(room.discussionRoomId, '!disc:example.invalid');
      expect(room.hasComments, isTrue);
    });

    test('маркер удаления канала: для UI комментариев нет', () {
      // Маркер несёт room_id ради СЕРВЕРА (по нему фоновые кики находят чат
      // обсуждения независимо от порядка событий). Клиент обязан всё равно
      // считать такой канал без комментариев: он уже удаляется, открывать по
      // нему ленту нечему. Без этой ветки удаляемый канал выглядел бы
      // «с комментариями».
      setDiscussionState({
        'room_id': '!disc:example.invalid',
        channelDeletedKey: true,
      });
      expect(room.discussionRoomId, isNull);
      expect(room.hasComments, isFalse);
    });

    test('нестрогая истина маркером не считается', () {
      setDiscussionState({
        'room_id': '!disc:example.invalid',
        channelDeletedKey: 'true',
      });
      expect(room.discussionRoomId, '!disc:example.invalid');
    });

    test('выключенные комментарии — пустой content', () {
      setDiscussionState({});
      expect(room.discussionRoomId, isNull);
      expect(room.hasComments, isFalse);
    });
  });
}
