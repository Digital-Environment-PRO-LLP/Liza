import 'package:flutter_test/flutter_test.dart';
import 'package:liza/pages/chat_list/chat_list.dart';

void main() {
  test('ActiveFilter has channels value', () {
    expect(ActiveFilter.values.contains(ActiveFilter.channels), isTrue);
  });
}
