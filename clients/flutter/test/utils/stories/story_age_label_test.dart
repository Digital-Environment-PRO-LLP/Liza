import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/stories/story_model.dart';

void main() {
  test('меньше часа - минуты, минимум 1', () {
    expect(storyAge(const Duration(seconds: 20)), (value: 1, hours: false));
    expect(storyAge(const Duration(minutes: 59)), (value: 59, hours: false));
  });
  test('час и больше - часы', () {
    expect(storyAge(const Duration(minutes: 60)), (value: 1, hours: true));
    expect(storyAge(const Duration(hours: 23)), (value: 23, hours: true));
  });
}
