import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/channel_stories.dart';

void main() {
  test('channelIdOf reads stories_of marker', () {
    expect(
      channelIdOf({
        'com.liza.channel.stories_of': {'channel_id': '\$c'},
      }),
      '\$c',
    );
  });
  test('channelIdOf null for personal stories', () {
    expect(channelIdOf({'com.liza.chat.type': 'stories'}), isNull);
  });
}
