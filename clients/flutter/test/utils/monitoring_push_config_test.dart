// Страж RL-push-rules-default-reset-client (сигнальная часть): клиентский
// `[push-config]` — тот же маркер, что у серверного детектора, без PII, и не
// чаще раза в сутки на причину (состояние хроническое).
//
// ledger:RL-push-rules-default-reset-client

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/monitoring.dart';

void main() {
  test(
    'AC:RL-push-rules-default-reset-client/5 — title: маркер сервера + reason, без PII',
    () {
      for (final reason in ['default_rule_disabled', 'os_denied']) {
        final title = Monitoring.pushConfigTitle(reason);
        expect(title, '[push-config] reason=$reason');
        expect(title.length, lessThanOrEqualTo(100));
        expect(title, isNot(contains('@')));
        for (final marker in [
          '[video-',
          '[audio-',
          '[media-',
          '[badge-mismatch]',
        ]) {
          expect(title, isNot(contains(marker)));
        }
      }
    },
  );

  test('AC:RL-push-rules-default-reset-client/5 — троттл 24 ч', () {
    final now = DateTime(2026, 9, 14, 12);
    expect(Monitoring.pushConfigDue(lastSent: null, now: now), isTrue);
    expect(
      Monitoring.pushConfigDue(
        lastSent: now.subtract(const Duration(hours: 23)),
        now: now,
      ),
      isFalse,
    );
    expect(
      Monitoring.pushConfigDue(
        lastSent: now.subtract(const Duration(hours: 24)),
        now: now,
      ),
      isTrue,
    );
  });
}
