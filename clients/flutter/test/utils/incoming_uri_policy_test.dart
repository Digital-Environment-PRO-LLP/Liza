// ledger:RL-user-invite-link-opens-profile
// AC:RL-user-invite-link-opens-profile/7
//
// Веб: initial-link из AppLinks — это URL самой страницы, уже разобранный
// роутером через webInitialLocation. Обработка его в ChatList уводила бы
// fallback'ом в /rooms поверх /opening/<code> (LABA-2551). Нативные ссылки и
// runtime-стрим обрабатываются как прежде.

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/incoming_uri_policy.dart';

void main() {
  test('веб + initial-link → пропустить', () {
    expect(shouldHandleIncomingUri(isWeb: true, isInitialLink: true), isFalse);
  });

  test('веб + runtime-ссылка → обработать', () {
    expect(shouldHandleIncomingUri(isWeb: true, isInitialLink: false), isTrue);
  });

  test('нативка: initial и runtime → обработать', () {
    expect(shouldHandleIncomingUri(isWeb: false, isInitialLink: true), isTrue);
    expect(
      shouldHandleIncomingUri(isWeb: false, isInitialLink: false),
      isTrue,
    );
  });
}
