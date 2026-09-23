// ledger:RL-channel-peek-live-feed
// AC:RL-channel-peek-live-feed/8
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('гейты peek-режима', () {
    late String source;

    setUpAll(() {
      source = File('lib/pages/chat/chat.dart').readAsStringSync();
    });

    test('setReadMarker не шлёт квитанции без членства', () {
      final start = source.indexOf('void setReadMarker(');
      expect(start, greaterThan(0));
      final body = source.substring(start, start + 700);
      expect(
        body.contains('Membership.join'),
        isTrue,
        reason: 'без гейта каждый скролл в peek-режиме даёт M_FORBIDDEN',
      );
    });
  });
}
