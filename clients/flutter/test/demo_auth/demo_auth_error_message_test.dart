import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/demo_auth_flow.dart';

/// Каждый код ошибки от auth-proxy обязан иметь свой текст: иначе человек
/// видит общую «что-то пошло не так» и не понимает, ждать ему или чинить.
void main() {
  late L10n l10n;

  setUp(() async {
    l10n = await L10n.delegate.load(const Locale('ru'));
  });

  test('серверные лимиты различимы по тексту', () {
    // otp_rate_limited раньше в маппинге отсутствовал.
    expect(
      demoAuthErrorMessage('otp_rate_limited', l10n),
      isNot(l10n.demoAuthGenericError),
    );
    expect(
      demoAuthErrorMessage('otp_rate_limited', l10n),
      l10n.demoAuthRateLimited,
    );
    // Новый код нового auth-proxy: часовой потолок, отвечает 422.
    expect(
      demoAuthErrorMessage('otp_request_limit_per_hour', l10n),
      l10n.demoAuthRateLimited,
    );
    expect(
      demoAuthErrorMessage('resend_too_soon', l10n),
      l10n.demoAuthResendTooSoon,
    );
    expect(
      demoAuthErrorMessage('resend_limit_reached', l10n),
      l10n.demoAuthResendLimitReached,
    );
  });

  test('все известные коды имеют собственный текст', () {
    const codes = [
      'invalid_phone',
      'invalid_code',
      'otp_expired',
      'otp_send_failed',
      'otp_delivery_failed',
      'otp_rate_limited',
      'otp_request_limit_per_hour',
      'resend_too_soon',
      'resend_limit_reached',
      'email_send_failed',
      'invalid_email',
      'otp_attempts_exhausted',
      'ticket_expired',
      // LABA-2527: отказ Keycloak по данным, а не недоступность сервиса.
      'registration_rejected',
      'keycloak_error',
      'synapse_error',
    ];
    for (final code in codes) {
      expect(
        demoAuthErrorMessage(code, l10n),
        isNot(l10n.demoAuthGenericError),
        reason: 'код $code остался без своего текста',
      );
    }
  });

  // ledger:RL-demo-auth-keycloak-4xx-honest
  // AC:RL-demo-auth-keycloak-4xx-honest/5
  test('registration_rejected — не «сервис недоступен» и не generic', () {
    final text = demoAuthErrorMessage('registration_rejected', l10n);
    expect(text, l10n.demoAuthRegistrationRejected);
    expect(text, isNot(l10n.demoAuthKeycloakError));
    expect(text, isNot(l10n.demoAuthGenericError));
    // Сервис при таком отказе жив — слово «недоступен» здесь было бы ложью.
    expect(text, isNot(contains('недоступен')));
  });

  // AC:RL-demo-auth-keycloak-4xx-honest/9
  test('keycloak_error по-прежнему означает недоступность (пин)', () {
    expect(
      demoAuthErrorMessage('keycloak_error', l10n),
      l10n.demoAuthKeycloakError,
    );
  });

  test('неизвестный код падает в общую ошибку', () {
    expect(demoAuthErrorMessage('who_knows', l10n), l10n.demoAuthGenericError);
  });

  test('тексты ошибок не раскрывают демо-код', () {
    // demoAuthDeliveryFailed и demoAuthRateLimited прямо предлагали ввести
    // 000000 — bypass-код не место в пользовательском тексте.
    expect(l10n.demoAuthDeliveryFailed, isNot(contains('000000')));
    expect(l10n.demoAuthRateLimited, isNot(contains('000000')));
  });
}
