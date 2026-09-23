// ledger:RL-channel-thread-reply-mention
// AC:RL-channel-thread-reply-mention/1
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/channel_discussion.dart';

Map<String, dynamic> _reply(String id, String inReplyTo) => {
  'event_id': id,
  'sender': '@a:x',
  'content': {
    'msgtype': 'm.text',
    'body': 'x',
    'm.relates_to': {
      'm.in_reply_to': {'event_id': inReplyTo},
    },
  },
};

void main() {
  group(
    'threadReplyAnchorId — схлопывание ответа в плоский 2-уровневый тред',
    () {
      const mirror = r'$mirror';

      test(
        'ответ на прямой комментарий (ур.1) → ссылается на него же (ур.2)',
        () {
          final c1 = _reply(r'$c1', mirror);
          expect(threadReplyAnchorId(c1, mirror), r'$c1');
        },
      );

      test(
        'ответ на ответ (ур.2) → схлопывается на родителя ур.1 (остаётся ур.2)',
        () {
          // c2 отвечает на c1 (который отвечает на зеркало). Ответ на c2 не должен
          // стать ур.3 (выпал бы из threadEvents) — анкор схлопывается на c1.
          final c2 = _reply(r'$c2', r'$c1');
          expect(threadReplyAnchorId(c2, mirror), r'$c1');
        },
      );

      test('цель без in_reply_to (ответ прямо на пост) → зеркало', () {
        final bare = {
          'event_id': r'$c9',
          'sender': '@a:x',
          'content': {'msgtype': 'm.text', 'body': 'x'},
        };
        expect(threadReplyAnchorId(bare, mirror), mirror);
      });
    },
  );

  // Гарантия «не выпадет из треда»: ответ, отправленный на вычисленный анкор,
  // ОБЯЗАН попасть в threadEvents (иначе «отправил, но пропало»).
  test('ответ на анкор остаётся в threadEvents (нет потери комментария)', () {
    const mirror = r'$mirror';
    final events = <Map<String, dynamic>>[
      {
        'event_id': mirror,
        'sender': '@a:x',
        'content': {'com.liza.channel.post_ref': r'$post'},
      },
      _reply(r'$c1', mirror),
      _reply(r'$c2', r'$c1'),
    ];
    // Отвечаем на c2 (ур.2) → анкор c1 → новый ответ c3 на c1.
    final anchor = threadReplyAnchorId(_reply(r'$c2', r'$c1'), mirror);
    events.add(_reply(r'$c3', anchor));
    final ids = threadEvents(events, mirror).map((e) => e['event_id']).toList();
    expect(ids, contains(r'$c3'));
  });
}
