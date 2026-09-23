// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/stories/story_model.dart';

void main() {
  test('publishStory content содержит caption когда задан', () {
    final json = StoryContent(
      expiresTs: 1, caption: 'Подпись', overlays: const [],
    ).toJson();
    expect(json['caption'], 'Подпись');
  });

  test('content без caption когда пусто', () {
    final json = StoryContent(
      expiresTs: 1, caption: '', overlays: const [],
    ).toJson();
    expect(json.containsKey('caption'), isFalse);
  });
}
