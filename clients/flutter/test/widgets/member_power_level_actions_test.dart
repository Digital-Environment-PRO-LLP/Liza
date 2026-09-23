import 'package:flutter_test/flutter_test.dart';

import 'package:liza/widgets/member_power_level_actions.dart';

void main() {
  group('canChangeMemberPowerLevel', () {
    test('себе при sdkAllows=true — запрещено', () {
      final result = canChangeMemberPowerLevel(
        callerId: '@me:example.org',
        targetId: '@me:example.org',
        sdkAllows: true,
      );
      expect(result, isFalse);
    });

    test('другому при sdkAllows=true — разрешено', () {
      final result = canChangeMemberPowerLevel(
        callerId: '@me:example.org',
        targetId: '@other:example.org',
        sdkAllows: true,
      );
      expect(result, isTrue);
    });

    test('другому при sdkAllows=false — запрещено (SDK не обходим)', () {
      final result = canChangeMemberPowerLevel(
        callerId: '@me:example.org',
        targetId: '@other:example.org',
        sdkAllows: false,
      );
      expect(result, isFalse);
    });
  });
}
