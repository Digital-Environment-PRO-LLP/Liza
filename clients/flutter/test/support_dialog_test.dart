import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/widgets/demo_auth_scaffold.dart';
import 'package:liza/pages/demo_auth/widgets/support_dialog.dart';

void main() {
  testWidgets('форма требует оба поля', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSupportDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNWidgets(2));
  });

  _deadEndCodesGroup();
}

void _deadEndCodesGroup() {
  // Вынесено отдельной функцией, чтобы не смешивать с виджет-тестами выше.
  group('тупиковые коды ошибок', () {
    test('сбой SMS-провайдера ведёт в поддержку', () {
      // otp_send_failed приходит из /phone/start при выключенном bypass —
      // это основной сценарий «код не дошёл не по вине человека».
      // Без него человек упирался в общую ошибку без выхода в поддержку.
      expect(deadEndErrorCodes, contains('otp_send_failed'));
    });

    test('все четыре точки входа покрыты', () {
      expect(
        deadEndErrorCodes,
        containsAll(<String>[
          'otp_attempts_exhausted',
          'otp_send_failed',
          'email_send_failed',
          'network_error',
          'internal_error',
        ]),
      );
    });

    test('resend_limit_reached не дублируется в общем списке', () {
      // На шагах sms/email под него уже есть своя кнопка вместо таймера.
      expect(deadEndErrorCodes, isNot(contains('resend_limit_reached')));
    });
  });
}
