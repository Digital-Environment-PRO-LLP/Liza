// ledger:RL-auth-review-login
//
// Вход модераторов App Store: для зарезервированного номера сервер отвечает
// на `/phone/start` каналом `password`, и шаг кода рисует поле пароля вместо
// ячеек OTP — без таймера повтора и «Другого способа». Пароль уходит тем же
// `/phone/verify` в поле `code`. Обычные номера — прежний экран кода.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/demo_auth_flow.dart';
import 'package:liza/pages/demo_auth/demo_auth_service.dart';
import 'package:liza/pages/demo_auth/steps/demo_sms_step.dart';
import 'package:liza/pages/demo_auth/widgets/code_input.dart';

/// Ответ `/phone/start` для номера App Store review — по контракту
/// auth-proxy (change `apple-review-login`).
const _passwordStart = {
  'ticket': 'review-ticket',
  'channel': 'password',
  'masked_destination': '+7 777 ***-**-01',
  'resend_available_in': 0,
  'delivery_failed': false,
  'expires_in': 600,
  'attempts_remain': 5,
};

/// Пароль со всеми классами символов: буквы обоих регистров, цифры, знаки.
const _password = r'Kx7#mP-q2_Zr!9vW';

void main() {
  http.Response json(Map<String, Object?> body, int status) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  final startBodies = {
    'password': _passwordStart,
    'phone': {
      'ticket': 't',
      'channel': 'phone',
      'masked_destination': '+7 999 ***-**-67',
      'resend_available_in': 60,
    },
    'email': {
      'ticket': 't',
      'channel': 'email',
      'masked_destination': 'd***@example.com',
      'resend_available_in': 60,
    },
  };

  /// Сервис с фиксированным `/phone/start` и управляемым `/phone/verify`.
  /// Все тела `/phone/verify` складываются в [verifyBodies].
  Future<http.Response> Function(http.Request) handler({
    required String channel,
    required List<Map<String, dynamic>> verifyBodies,
    http.Response Function()? verify,
  }) => (request) async {
    final path = request.url.path;
    if (path.endsWith('/phone/start')) {
      return json(startBodies[channel]!, 200);
    }
    if (path.endsWith('/phone/verify')) {
      verifyBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      return (verify ??
          () => json({'status': 'register', 'has_email': false}, 200))();
    }
    if (path.endsWith('/complete')) {
      return json({
        'status': 'ok',
        'login_token': 'lt',
        'server_name': 'liza.example',
        'user_id': '@review:liza.example',
      }, 200);
    }
    throw StateError('Unexpected request: $path');
  };

  Future<DemoAuthFlowController> pumpFlow(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    String locale = 'ru',
    Future<void> Function(DemoAuthTokens)? onAuthenticated,
  }) async {
    // use-deferred-loading: первую загрузку локали делает настоящий
    // loadLibrary(), под fakeAsync он не резолвится — дерево остаётся пустым.
    await tester.runAsync(() => L10n.delegate.load(Locale(locale)));
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => DemoAuthFlow(
            phone: '+77770000001',
            service: DemoAuthService(client: MockClient(handler)),
            onAuthenticated: onAuthenticated ?? (_) async {},
          ),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => const Text('home-screen'),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: Locale(locale),
      ),
    );
    // Не pumpAndSettle: у обычного канала тикает Timer.periodic отсчёта.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return tester.state<DemoAuthFlowController>(find.byType(DemoAuthFlow));
  }

  /// Не pumpAndSettle: после успешного входа спиннер кнопки крутится до
  /// навигации (в тесте её нет), и «уляжется» он никогда.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder passwordField() => find.descendant(
    of: find.byType(DemoPasswordInput),
    matching: find.byType(TextField),
  );

  L10n l10nOf(WidgetTester tester) =>
      L10n.of(tester.element(find.byType(DemoAuthFlow)));

  // AC:RL-auth-review-login/1
  group('AC-1: канал password разбирается из ответа сервера', () {
    test('startPhone с channel: password → isPasswordChannel', () async {
      final service = DemoAuthService(
        client: MockClient((_) async => json(_passwordStart, 200)),
      );

      final result = await service.startPhone('+77770000001');

      expect(result.channel, 'password');
      expect(result.isPasswordChannel, isTrue);
      expect(result.isEmailChannel, isFalse);
      expect(result.deliveryFailed, isFalse);
      expect(result.resendAvailableIn, 0);
      expect(result.maskedDestination, '+7 777 ***-**-01');
    });

    test('обычные каналы и отсутствие поля — не пароль', () {
      for (final channel in ['phone', 'email']) {
        final result = DemoAuthStartResult(
          ticket: 't',
          maskedDestination: '',
          channel: channel,
        );
        expect(result.isPasswordChannel, isFalse, reason: channel);
      }
      expect(
        const DemoAuthStartResult(
          ticket: 't',
          maskedDestination: '',
        ).isPasswordChannel,
        isFalse,
      );
    });

    test('wireName канала совпадает с auth-proxy', () {
      expect(DemoAuthChannel.password.wireName, 'password');
    });

    testWidgets('контроллер: канал password, переключать нечего', (
      tester,
    ) async {
      final controller = await pumpFlow(
        tester,
        handler(channel: 'password', verifyBodies: []),
      );

      expect(controller.step, DemoAuthStep.sms);
      expect(controller.passwordLogin, isTrue);
      expect(controller.currentChannel, DemoAuthChannel.password);
      expect(controller.canSwitchChannel, isFalse);
      expect(
        controller.availableChannels,
        isNot(contains(DemoAuthChannel.password)),
        reason: 'пароль не предлагается в меню «Другой способ»',
      );
    });
  });

  for (final locale in ['ru', 'en']) {
    // AC:RL-auth-review-login/2
    testWidgets('AC-2 [$locale]: экран пароля — скрытое поле, без повтора и '
        '«Другого способа»', (tester) async {
      await pumpFlow(
        tester,
        handler(channel: 'password', verifyBodies: []),
        locale: locale,
      );
      final l10n = l10nOf(tester);

      expect(find.text(l10n.demoAuthPasswordTitle), findsOneWidget);
      expect(
        find.text(l10n.demoAuthPasswordHint('+7 777 ***-**-01')),
        findsOneWidget,
      );
      expect(find.text(l10n.demoAuthSmsTitle), findsNothing);

      expect(find.byType(CodeInput), findsNothing);
      expect(passwordField(), findsOneWidget);
      final field = tester.widget<TextField>(passwordField());
      expect(field.obscureText, isTrue);
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.autofillHints, contains(AutofillHints.password));
      expect(field.keyboardType, TextInputType.visiblePassword);
      expect(field.inputFormatters, anyOf(isNull, isEmpty));

      expect(find.text(l10n.demoAuthResendAgain), findsNothing);
      expect(
        find.textContaining(l10n.demoAuthResendIn('').trim()),
        findsNothing,
      );
      expect(find.text(l10n.demoAuthOtherChannel), findsNothing);
      // Выход в поддержку остаётся: застрять можно и с паролем.
      expect(find.text(l10n.supportContactButton), findsOneWidget);
    });
  }

  // AC:RL-auth-review-login/3
  group('AC-3: пароль уходит в /phone/verify как есть', () {
    testWidgets('Enter на клавиатуре отправляет пароль', (tester) async {
      final verifyBodies = <Map<String, dynamic>>[];
      await pumpFlow(
        tester,
        handler(channel: 'password', verifyBodies: verifyBodies),
      );

      await tester.enterText(passwordField(), _password);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(verifyBodies, [
        {'ticket': 'review-ticket', 'code': _password},
      ]);
    });

    testWidgets('кнопка «Продолжить» отправляет пароль, пустой — нельзя', (
      tester,
    ) async {
      final verifyBodies = <Map<String, dynamic>>[];
      await pumpFlow(
        tester,
        handler(channel: 'password', verifyBodies: verifyBodies),
      );
      final l10n = l10nOf(tester);
      final button = find.widgetWithText(ElevatedButton, l10n.demoAuthContinue);

      expect(tester.widget<ElevatedButton>(button).onPressed, isNull);

      await tester.enterText(passwordField(), _password);
      await tester.pump();
      await tester.tap(button);
      await settle(tester);

      expect(verifyBodies.single['code'], _password);
    });
  });

  for (final locale in ['ru', 'en']) {
    // AC:RL-auth-review-login/4
    testWidgets('AC-4 [$locale]: неверный пароль — «неверный пароль», шаг '
        'тот же, поле пустое', (tester) async {
      final verifyBodies = <Map<String, dynamic>>[];
      final controller = await pumpFlow(
        tester,
        handler(
          channel: 'password',
          verifyBodies: verifyBodies,
          verify: () => json({
            'error': 'invalid_code',
            'message': 'Wrong password',
            'attempts_remain': 4,
          }, 400),
        ),
        locale: locale,
      );
      final l10n = l10nOf(tester);

      await tester.enterText(passwordField(), 'wrong-pass');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settle(tester);

      expect(verifyBodies, hasLength(1));
      expect(controller.step, DemoAuthStep.sms);
      expect(find.text(l10n.demoAuthWrongPassword), findsOneWidget);
      expect(find.text(l10n.demoAuthInvalidCode), findsNothing);
      expect(passwordField(), findsOneWidget);
      expect(tester.widget<TextField>(passwordField()).controller!.text, '');
    });
  }

  // AC:RL-auth-review-login/4
  test(
    'AC-4: invalid_code на обычном канале — прежний «Неверный код»',
    () async {
      for (final locale in ['ru', 'en']) {
        final l10n = await L10n.delegate.load(Locale(locale));
        expect(
          demoAuthErrorMessage('invalid_code', l10n),
          l10n.demoAuthInvalidCode,
        );
        expect(
          demoAuthErrorMessage('invalid_code', l10n, passwordChannel: true),
          l10n.demoAuthWrongPassword,
        );
        expect(
          l10n.demoAuthWrongPassword,
          isNot(l10n.demoAuthInvalidCode),
          reason: locale,
        );
      }
    },
  );

  // AC:RL-auth-review-login/5
  testWidgets('AC-5: верный пароль завершает вход как после OTP', (
    tester,
  ) async {
    final verifyBodies = <Map<String, dynamic>>[];
    DemoAuthTokens? tokens;
    await pumpFlow(
      tester,
      handler(channel: 'password', verifyBodies: verifyBodies),
      onAuthenticated: (t) async => tokens = t,
    );

    await tester.enterText(passwordField(), _password);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);

    expect(tokens?.loginToken, 'lt');
    expect(tokens?.userId, '@review:liza.example');
  });

  for (final channel in ['phone', 'email']) {
    // AC:RL-auth-review-login/6
    testWidgets('AC-6 [$channel]: обычный номер — ячейки кода, таймер повтора, '
        'без поля пароля', (tester) async {
      final controller = await pumpFlow(
        tester,
        handler(channel: channel, verifyBodies: []),
      );
      final l10n = l10nOf(tester);

      expect(controller.passwordLogin, isFalse);
      expect(find.byType(CodeInput), findsOneWidget);
      expect(find.byType(DemoPasswordInput), findsNothing);
      expect(find.text(l10n.demoAuthPasswordTitle), findsNothing);
      expect(find.text(l10n.demoAuthResendIn('1:00')), findsOneWidget);
      // «Другой способ» — по прежнему правилу: при доставке письмом.
      expect(
        find.text(l10n.demoAuthOtherChannel),
        channel == 'email' ? findsOneWidget : findsNothing,
      );

      // Отсчёт до конца — появляется «Отправить ещё раз».
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text(l10n.demoAuthResendAgain), findsOneWidget);
    });
  }

  // AC:RL-auth-review-login/7
  test('AC-7: строки экрана пароля есть в en и ru, ru переведён', () {
    Map<String, dynamic> arb(String lang) =>
        jsonDecode(File('lib/l10n/intl_$lang.arb').readAsStringSync())
            as Map<String, dynamic>;
    final en = arb('en');
    final ru = arb('ru');
    const keys = [
      'demoAuthPasswordTitle',
      'demoAuthPasswordHint',
      'demoAuthPasswordLabel',
      'demoAuthHidePassword',
      'demoAuthWrongPassword',
    ];
    for (final key in keys) {
      expect(en[key], isA<String>(), reason: 'en: $key');
      expect(ru[key], isA<String>(), reason: 'ru: $key');
      expect(ru[key], isNot(en[key]), reason: 'ru не переведён: $key');
      expect(
        ru[key] as String,
        matches(RegExp('[а-яё]', caseSensitive: false)),
      );
    }

    // Строки экрана — только через L10n: в шаге нет кириллицы/английских
    // литералов заголовков.
    final step = File(
      'lib/pages/demo_auth/steps/demo_sms_step.dart',
    ).readAsStringSync();
    for (final literal in ["'Password'", "'Пароль'", "'Enter password'"]) {
      expect(step, isNot(contains(literal)));
    }
  });
}
