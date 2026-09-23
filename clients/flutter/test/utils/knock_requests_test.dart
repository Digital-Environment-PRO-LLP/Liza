import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/knock_requests.dart';

// ledger:RL-knock-requests
void main() {
  // AC:RL-knock-requests/4 — чистый подсчёт knock-членов.
  test('считает участников в состоянии knock', () {
    expect(
      countKnocking([
        Membership.join,
        Membership.knock,
        Membership.knock,
        Membership.invite,
      ]),
      2,
    );
  });

  test('без заявок даёт ноль', () {
    expect(countKnocking([Membership.join, Membership.leave]), 0);
  });

  test('пустой список даёт ноль', () {
    expect(countKnocking(const []), 0);
  });
}
