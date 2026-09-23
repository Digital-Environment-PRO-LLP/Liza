import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/stories/story_model.dart';

void main() {
  const ref = StoryRef(
    roomId: '!story:example.invalid',
    eventId: r'$seg1',
    authorId: '@author:example.invalid',
    thumbnailMxc: 'mxc://example.invalid/thumb1',
    expiresTs: 1751800000000,
  );

  test('round-trip toJson/fromContent [ledger:RL-stories-reply-share-card]', () {
    final content = ref.buildMessageContent(body: '📷 История Ивана: привет');
    expect(content['msgtype'], 'm.text');
    expect(content['body'], '📷 История Ивана: привет');
    final parsed = StoryRef.fromContent(content);
    expect(parsed, isNotNull);
    expect(parsed!.roomId, ref.roomId);
    expect(parsed.eventId, ref.eventId);
    expect(parsed.authorId, ref.authorId);
    expect(parsed.thumbnailMxc, ref.thumbnailMxc);
    expect(parsed.expiresTs, ref.expiresTs);
  });

  test('fromContent без ключа - null [ledger:RL-stories-reply-share-card]', () {
    expect(StoryRef.fromContent(const {'msgtype': 'm.text'}), isNull);
  });

  test('thumbnailMxc опционален [ledger:RL-stories-reply-share-card]', () {
    const noThumb = StoryRef(
      roomId: '!r:x',
      eventId: r'$e',
      authorId: '@a:x',
      expiresTs: 1,
    );
    final json = noThumb.toJson();
    expect(json.containsKey('thumbnail_mxc'), isFalse);
    final back = StoryRef.fromContent({storyRefKey: json});
    expect(back!.thumbnailMxc, isNull);
  });

  test(
    'body без userText не содержит перевод строки (StoryRefCard делит по первому \\n) [ledger:RL-stories-reply-share-card]',
    () {
      final content = ref.buildMessageContent(body: '📷 История Ивана');
      final body = content['body']! as String;
      expect(body.contains('\n'), isFalse);
    },
  );

  test(
    'body с userText: fallback до первого \\n, текст пользователя - после [ledger:RL-stories-reply-share-card]',
    () {
      final content = ref.buildMessageContent(
        body: '📷 История Ивана\nпривет, как дела?\nвторая строка',
      );
      final body = content['body']! as String;
      final newline = body.indexOf('\n');
      expect(newline, greaterThanOrEqualTo(0));
      expect(body.substring(newline + 1), 'привет, как дела?\nвторая строка');
    },
  );
}
