import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/channel_discussion.dart';

// Спек 2026-07-30, Этап 2. Комментарий = reply на «зеркало» поста в
// привязанном чате. Экран треда показывает только эти события.
void main() {
  Map<String, dynamic> mirror(String id, String postId) => {
        'event_id': id,
        'content': {
          'com.liza.channel.post_ref': {'post_event_id': postId},
        },
      };

  Map<String, dynamic> reply(String id, String toId) => {
        'event_id': id,
        'content': {
          'm.relates_to': {
            'm.in_reply_to': {'event_id': toId},
          },
        },
      };

  group('repliesToMirror', () {
    test('отбирает только ответы на указанное зеркало', () {
      final events = [
        mirror(r'$m1', r'$post1'),
        reply(r'$c1', r'$m1'),
        reply(r'$other', r'$m2'),
        reply(r'$c2', r'$m1'),
      ];
      final result = repliesToMirror(events, r'$m1');
      expect(result.map((e) => e['event_id']), [r'$c1', r'$c2']);
    });

    test('пустой список, если ответов нет', () {
      expect(repliesToMirror([mirror(r'$m1', r'$post1')], r'$m1'), isEmpty);
    });

    test('обычное сообщение чата в тред не попадает', () {
      final events = [
        mirror(r'$m1', r'$post1'),
        {'event_id': r'$plain', 'content': {'body': 'привет'}},
      ];
      expect(repliesToMirror(events, r'$m1'), isEmpty);
    });

    group('грязные данные', () {
      test('событие вообще без ключа content', () {
        final events = [
          mirror(r'$m1', r'$post1'),
          {'event_id': r'$noContent'},
        ];
        expect(repliesToMirror(events, r'$m1'), isEmpty);
      });

      test('m.relates_to не Map (строка)', () {
        final events = [
          mirror(r'$m1', r'$post1'),
          {
            'event_id': r'$weird',
            'content': {'m.relates_to': 'не мапа'},
          },
        ];
        expect(repliesToMirror(events, r'$m1'), isEmpty);
      });

      test('отсутствующий m.in_reply_to', () {
        final events = [
          mirror(r'$m1', r'$post1'),
          {
            'event_id': r'$noReplyTo',
            'content': {'m.relates_to': <String, dynamic>{}},
          },
        ];
        expect(repliesToMirror(events, r'$m1'), isEmpty);
      });
    });
  });

  group('threadEvents', () {
    test('берёт и прямые ответы, и ответы на ответы', () {
      final events = [
        mirror(r'$m1', r'$post1'),
        reply(r'$c1', r'$m1'),
        reply(r'$c2', r'$c1'),
        reply(r'$other', r'$m2'),
      ];
      expect(
        threadEvents(events, r'$m1').map((e) => e['event_id']),
        [r'$c1', r'$c2'],
      );
    });

    test('чужой чат в тред не подмешивается', () {
      final events = [
        mirror(r'$m1', r'$post1'),
        reply(r'$foreign', r'$m2'),
        reply(r'$onForeign', r'$foreign'),
        {'event_id': r'$plain', 'content': {'body': 'привет'}},
      ];
      expect(threadEvents(events, r'$m1'), isEmpty);
    });

    test('третий уровень не втягивается — тред остаётся плоским', () {
      final events = [
        mirror(r'$m1', r'$post1'),
        reply(r'$c1', r'$m1'),
        reply(r'$c2', r'$c1'),
        reply(r'$c3', r'$c2'),
      ];
      expect(
        threadEvents(events, r'$m1').map((e) => e['event_id']),
        [r'$c1', r'$c2'],
      );
    });

    test('порядок входного списка сохраняется', () {
      final events = [
        mirror(r'$m1', r'$post1'),
        reply(r'$c2', r'$c1'),
        reply(r'$c1', r'$m1'),
      ];
      expect(
        threadEvents(events, r'$m1').map((e) => e['event_id']),
        [r'$c2', r'$c1'],
      );
    });
  });

  group('countThreadComments', () {
    // Плашка «N комментариев» под постом и содержимое треда обязаны считать
    // одно и то же. Раньше плашка звала countReplies (только прямые ответы),
    // и пост с одним комментарием и ответами на него открывался с бОльшим
    // числом сообщений, чем обещал счётчик.
    test('считает и прямые ответы, и ответы на них', () {
      final events = [
        mirror(r'$m1', r'$post1'),
        reply(r'$c1', r'$m1'),
        reply(r'$r1', r'$c1'),
        reply(r'$r2', r'$c1'),
      ];
      expect(countThreadComments(events, r'$post1'), 3);
      // Ровно расхождение, которое чинится: прямых ответов всего один.
      expect(countReplies(events, r'$post1'), 1);
    });

    test('совпадает с длиной того, что покажет тред', () {
      final events = [
        mirror(r'$m1', r'$post1'),
        reply(r'$c1', r'$m1'),
        reply(r'$c2', r'$m1'),
        reply(r'$r1', r'$c2'),
        reply(r'$other', r'$m2'),
        {
          'event_id': r'$plain',
          'content': {'body': 'обычное сообщение чата'},
        },
      ];
      expect(
        countThreadComments(events, r'$post1'),
        threadEvents(events, r'$m1').length,
      );
      expect(countThreadComments(events, r'$post1'), 3);
    });

    test('нет зеркала — ноль', () {
      expect(countThreadComments(const [], r'$post1'), 0);
    });

    test('зеркало без ответов — ноль', () {
      expect(countThreadComments([mirror(r'$m1', r'$post1')], r'$post1'), 0);
    });

    test('чужой тред в счётчик не подмешивается', () {
      final events = [
        mirror(r'$m1', r'$post1'),
        mirror(r'$m2', r'$post2'),
        reply(r'$c1', r'$m1'),
        reply(r'$c2', r'$m2'),
        reply(r'$r2', r'$c2'),
      ];
      expect(countThreadComments(events, r'$post1'), 1);
      expect(countThreadComments(events, r'$post2'), 2);
    });
  });

  group('quotedComment', () {
    test('ответ прямо на пост цитаты не имеет', () {
      final events = [mirror(r'$m1', r'$post1'), reply(r'$c1', r'$m1')];
      expect(quotedComment(events, events[1], r'$m1'), isNull);
    });

    test('ответ на комментарий цитирует этот комментарий', () {
      final events = [
        mirror(r'$m1', r'$post1'),
        reply(r'$c1', r'$m1'),
        reply(r'$c2', r'$c1'),
      ];
      expect(quotedComment(events, events[2], r'$m1'), events[1]);
    });

    test('адресат не загружен — цитаты нет, но и падения нет', () {
      final events = [mirror(r'$m1', r'$post1'), reply(r'$c2', r'$missing')];
      expect(quotedComment(events, events[1], r'$m1'), isNull);
    });
  });

  group('needsMoreHistory', () {
    test('зеркало не найдено — нужна ещё история', () {
      expect(
        needsMoreHistory(
          events: const [],
          postEventId: r'$post1',
          loadedBatches: 1,
          maxBatches: 3,
        ),
        isTrue,
      );
    });

    test('зеркало найдено — больше не грузим', () {
      expect(
        needsMoreHistory(
          events: [mirror(r'$m1', r'$post1')],
          postEventId: r'$post1',
          loadedBatches: 1,
          maxBatches: 3,
        ),
        isFalse,
      );
    });

    test('потолок итераций останавливает подгрузку', () {
      expect(
        needsMoreHistory(
          events: const [],
          postEventId: r'$post1',
          loadedBatches: 3,
          maxBatches: 3,
        ),
        isFalse,
      );
    });

    test(
      'потолок останавливает подгрузку, даже когда зеркало ещё НЕ найдено '
      '(доказывает короткое замыкание именно на потолке, а не на пустом '
      'списке)',
      () {
        expect(
          needsMoreHistory(
            events: [mirror(r'$other', r'$postOther')],
            postEventId: r'$post1',
            loadedBatches: 3,
            maxBatches: 3,
          ),
          isFalse,
        );
      },
    );
  });
}
