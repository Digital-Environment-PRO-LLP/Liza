import 'package:flutter_test/flutter_test.dart';
import 'package:liza/pages/chat/events/state_message.dart';

void main() {
  group('shouldHideMemberEvent', () {
    test('скрывает invite (любой prev)', () {
      expect(shouldHideMemberEvent('invite', null), isTrue);
      expect(shouldHideMemberEvent('invite', 'join'), isTrue);
      expect(shouldHideMemberEvent('invite', 'leave'), isTrue);
    });

    test('показывает реальный вход (prev не join)', () {
      expect(shouldHideMemberEvent('join', null), isFalse);
      expect(shouldHideMemberEvent('join', 'invite'), isFalse);
      expect(shouldHideMemberEvent('join', 'leave'), isFalse);
    });

    test('скрывает смену ника/аватарки (join -> join)', () {
      expect(shouldHideMemberEvent('join', 'join'), isTrue);
    });

    test('показывает leave и ban', () {
      expect(shouldHideMemberEvent('leave', 'join'), isFalse);
      expect(shouldHideMemberEvent('ban', 'join'), isFalse);
    });

    test('скрывает неизвестное/пустое membership', () {
      expect(shouldHideMemberEvent(null, null), isTrue);
    });
  });
}
