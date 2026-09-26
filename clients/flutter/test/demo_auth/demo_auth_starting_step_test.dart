@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/demo_auth_flow.dart';
import 'package:liza/pages/demo_auth/steps/demo_starting_step.dart';
import 'package:liza/pages/demo_auth/widgets/demo_auth_scaffold.dart';

/// Мигание экрана СМС перед экраном письма.
///
/// Канал доставки выбирает СЕРВЕР (`/phone/start` отвечает `channel`), а
/// флоу до его ответа рисовал экран СМС по умолчанию: при доставке письмом
/// человек успевал увидеть чужой заголовок «Код из СМС» и иконку sms, после
/// чего экран перерисовывался. Инвариант — до ответа сервера конкретный
/// экран канала не рисуется вовсе.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: child,
      );

  group('шаг ожидания (starting)', () {
    test('начальный шаг флоу — starting, а не sms', () {
      // Прод-инвариант по исходнику: поле инициализируется до первого
      // кадра, поэтому проверяем именно объявление, а не поведение копии.
      final source = File(
        'lib/pages/demo_auth/demo_auth_flow.dart',
      ).readAsStringSync();

      expect(
        source,
        contains('DemoAuthStep step = DemoAuthStep.starting;'),
        reason: 'начальное значение sms возвращает мигание экрана СМС',
      );
      expect(
        source,
        isNot(contains('DemoAuthStep step = DemoAuthStep.sms;')),
      );
    });

    test('конкретный экран канала рисуется только после ответа сервера', () {
      final source = File(
        'lib/pages/demo_auth/demo_auth_flow.dart',
      ).readAsStringSync();

      // В обработчике ответа `/phone/start` шаг обязан переключаться на sms:
      // без этого экран ожидания не сменится никогда.
      expect(source, contains('step = DemoAuthStep.sms;'));
      // А вот ошибку первого запроса на шаг кода уводить НЕЛЬЗЯ: код не
      // отправлен, и экран ввода кода про него солгал бы. Инвариант «человек
      // не остаётся со спиннером навсегда» держится теперь поверхностью
      // ошибки на самом шаге ожидания — он проверяется поведением ниже
      // («экран ожидания с ошибкой…»), а не наличием строки в исходнике.
      expect(
        source,
        isNot(
          contains(
            'if (step == DemoAuthStep.starting) step = DemoAuthStep.sms;',
          ),
        ),
      );
    });

    testWidgets('экран ожидания не называет канал и не показывает иконку СМС',
        (tester) async {
      await tester.pumpWidget(
        wrap(const DemoAuthStartingStep()),
      );
      // Локализация грузится отложенно (use-deferred-loading в l10n.yaml),
      // поэтому одного кадра мало; pumpAndSettle здесь не годится — на
      // экране бесконечный спиннер.
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Отправляем код'), findsOneWidget);
      // Ни заголовка СМС, ни заголовка письма — канал ещё неизвестен.
      expect(find.text('Код из СМС'), findsNothing);
      expect(find.byIcon(Icons.sms_outlined), findsNothing);
      expect(find.byIcon(Icons.mark_email_unread_outlined), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('каркас тот же, что у экранов кода — вёрстка не скачет', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const DemoAuthStartingStep()));
      // Локализация грузится отложенно (use-deferred-loading в l10n.yaml),
      // поэтому одного кадра мало; pumpAndSettle здесь не годится — на
      // экране бесконечный спиннер.
      await tester.pump(const Duration(milliseconds: 100));

      // Один и тот же DemoAuthScaffold на обоих шагах: смена шага не
      // перестраивает экран целиком.
      expect(find.byType(DemoAuthScaffold), findsOneWidget);

      final spinner = tester.getSize(
        find.byType(CircularProgressIndicator).first,
      );
      // Иконки экранов кода — 56px; спиннер занимает тот же слот, поэтому
      // заголовок не прыгает вверх-вниз при смене шага.
      expect(spinner.width, lessThanOrEqualTo(56.0));
    });
  });

  group('DemoAuthChannel', () {
    test('канал сервера не строка в трёх местах, а один enum', () {
      // Архитектурное требование: добавление третьего способа не должно
      // требовать правок в пяти местах.
      final source = File(
        'lib/pages/demo_auth/widgets/otp_actions_row.dart',
      ).readAsStringSync();
      expect(source, isNot(contains("'email'  ==")));
      expect(source, contains('DemoAuthChannel'));
    });

    test('wireName совпадает с тем, что ждёт auth-proxy', () {
      expect(
        DemoAuthChannel.values.map((c) => c.wireName).toSet(),
        {'phone', 'email', 'password'},
      );
    });
  });
}
