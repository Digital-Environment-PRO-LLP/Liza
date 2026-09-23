import 'package:flutter_test/flutter_test.dart';
import 'package:liza/pages/chat_list/chat_list.dart';

void main() {
  group('shouldShowBlockAction', () {
    test('DM — показываем', () {
      expect(shouldShowBlockAction(isDirectChat: true), isTrue);
    });
    test('не-DM — скрываем', () {
      expect(shouldShowBlockAction(isDirectChat: false), isFalse);
    });
  });
}
