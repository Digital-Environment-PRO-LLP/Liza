// ledger:RL-login-phone-invalid-inline
// AC:RL-login-phone-invalid-inline/7 AC:RL-login-phone-invalid-inline/8
//
// Отказ запроса `/phone/start` не должен выдавать себя за отправленный код.
//
// Раньше `_fail()` переводил шаг `starting` → `sms`, потому что показать
// ошибку на экране ожидания было негде. Но на шаге `sms` `deliveryFailed`
// остаётся false, а `maskedPhone` пуст — заголовок читался как «Мы отправили
// СМС на номер .» над пустыми ячейками кода. Так выглядели ВСЕ отказы
// первого запроса: неверный номер (LABA-2531), лимит частоты, сбой
// провайдера, обрыв сети. Теперь ошибку показывает сам экран ожидания.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/steps/demo_starting_step.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: child,
      );

  group('экран ожидания с ошибкой', () {
    testWidgets(
      'AC-8: спиннера нет, виден текст ошибки и выход в поддержку',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const DemoAuthStartingStep(
              error: 'Введите корректный номер телефона',
              errorCode: 'invalid_phone',
            ),
          ),
        );
        // Локализация грузится отложенно (use-deferred-loading в l10n.yaml),
        // поэтому одного кадра мало.
        await tester.pump(const Duration(milliseconds: 100));

        // Ждать больше нечего — код не заказан.
        expect(find.byType(CircularProgressIndicator), findsNothing);
        // Причина названа прямо здесь, а не на чужом экране.
        expect(find.text('Введите корректный номер телефона'), findsOneWidget);
        // Человек не заперт: выход в поддержку есть.
        expect(find.textContaining('поддержку'), findsWidgets);
      },
    );

    testWidgets(
      'AC-7: экран ожидания с ошибкой не утверждает, что СМС отправлена',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const DemoAuthStartingStep(
              error: 'Введите корректный номер телефона',
              errorCode: 'invalid_phone',
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));

        // Ровно та ложь, ради которой правка: пустая маска номера в шаблоне
        // «Мы отправили СМС на номер {phone}.» давала «…на номер .».
        expect(find.textContaining('Мы отправили СМС'), findsNothing);
        expect(find.textContaining('Код из СМС'), findsNothing);
        expect(find.byIcon(Icons.sms_outlined), findsNothing);
      },
    );

    testWidgets(
      'без ошибки шаг ожидания прежний: спиннер и подсказка',
      (tester) async {
        await tester.pumpWidget(wrap(const DemoAuthStartingStep()));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsNothing);
        expect(find.text('Подождите, выбираем способ доставки'), findsOneWidget);
      },
    );
  });
}
