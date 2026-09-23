// ledger:RL-demo-auth-no-endless-spinner
//
// LABA-2529: лимит заказа кода исчерпан → ввод «000000» → вечный спиннер и
// `Null check operator used on a null value` в консоли web. Методы флоу ловили
// только `DemoAuthException`: любой другой сбой оставлял `isLoading` навсегда.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/demo_auth_flow.dart';
import 'package:liza/pages/demo_auth/demo_auth_service.dart';
import 'package:liza/pages/demo_auth/widgets/code_input.dart';

const _okStart = DemoAuthStartResult(
  ticket: 't',
  maskedDestination: '+7 980 ***-**-04',
  resendAvailableIn: 60,
);

Future<Never> _unexpected() => Future.error(StateError('неожиданный сбой'));

/// Сервис с управляемыми ответами: неожиданный throw нельзя получить через
/// `_post` для каждого метода, а инвариант касается ИМЕННО контроллера.
/// Всё, кроме старта, по умолчанию бросает [StateError].
class _FakeService extends DemoAuthService {
  _FakeService({this.start, this.verifyPhoneCall})
    : super(client: MockClient((_) async => http.Response('', 500)));

  final Future<DemoAuthStartResult> Function(int call)? start;
  final Future<DemoAuthPhoneResult> Function()? verifyPhoneCall;
  int _startCalls = 0;

  @override
  Future<DemoAuthStartResult> startPhone(
    String phone, {
    String? ticket,
    String? channel,
  }) {
    _startCalls++;
    return start?.call(_startCalls) ?? Future.value(_okStart);
  }

  @override
  Future<DemoAuthPhoneResult> verifyPhone({
    required String ticket,
    required String code,
  }) => (verifyPhoneCall ?? _unexpected)();

  @override
  Future<void> verifyEmail({required String ticket, required String code}) =>
      _unexpected();

  @override
  Future<DemoAuthStartResult> sendEmailCode({
    required String ticket,
    required String email,
  }) => _unexpected();

  @override
  Future<DemoAuthCompleteResult> complete({
    required String ticket,
    String? serverName,
  }) => _unexpected();
}

void main() {
  Future<DemoAuthFlowController> pumpFlow(
    WidgetTester tester,
    DemoAuthService service,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: DemoAuthFlow(
          phone: '+79800550404',
          service: service,
          onAuthenticated: (_) async {},
        ),
      ),
    );
    // Не pumpAndSettle: при дефекте спиннер крутится вечно и settle не
    // наступит — тест упал бы таймаутом вместо внятного ассерта.
    await settleFrames(tester);
    return tester.state<DemoAuthFlowController>(find.byType(DemoAuthFlow));
  }

  DemoAuthService http200(Object? Function(http.Request) respond) =>
      DemoAuthService(
        client: MockClient((request) async {
          final body = respond(request);
          return body is http.Response
              ? body
              : http.Response(jsonEncode(body), 200);
        }),
      );

  void expectNoEndlessSpinner(DemoAuthFlowController controller) {
    expect(controller.isLoading, isFalse);
    expect(controller.error, isNotNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  }

  // AC:RL-demo-auth-no-endless-spinner/1
  group('AC-1: отказ /phone/start не открывает поле кода', () {
    final cases = <String, http.Response>{
      'otp_request_limit_per_hour': http.Response(
        jsonEncode({
          'error': 'otp_request_limit_per_hour',
          'resend_available_in': 0,
        }),
        422,
      ),
      'resend_too_soon': http.Response(
        jsonEncode({'error': 'resend_too_soon', 'resend_available_in': 42}),
        429,
      ),
      'internal_error': http.Response(
        jsonEncode({'error': 'internal_error'}),
        500,
      ),
    };
    for (final MapEntry(key: code, value: response) in cases.entries) {
      testWidgets(code, (tester) async {
        final controller = await pumpFlow(tester, http200((_) => response));

        expect(controller.step, DemoAuthStep.starting);
        expect(controller.ticket, isNull);
        expect(controller.errorCode, code);
        expect(find.byType(CodeInput), findsNothing);
        expectNoEndlessSpinner(controller);
      });
    }
  });

  // AC:RL-demo-auth-no-endless-spinner/2
  group('AC-2: ответ 200 без тикета на старте — ошибка, а не спиннер', () {
    final cases = <String, http.Response>{
      'пустой JSON': http.Response('{}', 200),
      'не-JSON тело прокси': http.Response('<html>gateway</html>', 200),
    };
    for (final MapEntry(key: name, value: response) in cases.entries) {
      testWidgets(name, (tester) async {
        final controller = await pumpFlow(tester, http200((_) => response));

        expect(controller.step, DemoAuthStep.starting);
        expect(find.byType(CodeInput), findsNothing);
        expectNoEndlessSpinner(controller);
      });
    }
  });

  // AC:RL-demo-auth-no-endless-spinner/3
  group('AC-3: неожиданный сбой сервиса снимает загрузку', () {
    final methods = <String, Future<void> Function(DemoAuthFlowController)>{
      'resendSms': (c) => c.resendSms(),
      'submitSmsCode': (c) => c.submitSmsCode('123456'),
      'submitEmailCode': (c) => c.submitEmailCode('123456'),
      'resendEmailCode': (c) => c.resendEmailCode(),
      'selectServer': (c) => c.selectServer('example.com'),
    };
    for (final MapEntry(key: name, value: call) in methods.entries) {
      testWidgets(name, (tester) async {
        final controller = await pumpFlow(
          tester,
          _FakeService(
            start: (n) => n == 1 ? Future.value(_okStart) : _unexpected(),
          ),
        );
        expect(controller.step, DemoAuthStep.sms);

        await call(controller);
        await settleFrames(tester);

        expect(tester.takeException(), isNull);
        expectNoEndlessSpinner(controller);
      });
    }
  });

  // AC:RL-demo-auth-no-endless-spinner/4
  testWidgets('AC-4: известная ошибка сервера показывает свой текст', (
    tester,
  ) async {
    final controller = await pumpFlow(
      tester,
      http200(
        (request) => request.url.path == '/api/auth/phone/start'
            ? {'ticket': 't', 'channel': 'phone'}
            : http.Response(
                jsonEncode({'error': 'invalid_code', 'attempts_remain': 2}),
                400,
              ),
      ),
    );

    await controller.submitSmsCode('123456');
    await settleFrames(tester);

    final l10n = L10n.of(tester.element(find.byType(DemoAuthFlow)));
    expect(controller.errorCode, 'invalid_code');
    expect(controller.error, l10n.demoAuthInvalidCode);
    expect(controller.error, isNot(l10n.demoAuthGenericError));
  });

  // AC:RL-demo-auth-no-endless-spinner/5
  testWidgets('AC-5: после сбоя поле кода снова доступно', (tester) async {
    final controller = await pumpFlow(tester, _FakeService());

    await controller.submitSmsCode('123456');
    await settleFrames(tester);

    expect(controller.step, DemoAuthStep.sms);
    expect(tester.widget<CodeInput>(find.byType(CodeInput)).enabled, isTrue);
  });

  // AC:RL-demo-auth-no-endless-spinner/6
  testWidgets('AC-6: поздний сбой устаревшего запроса не трогает текущий', (
    tester,
  ) async {
    final staleResend = Completer<DemoAuthStartResult>();
    final currentVerify = Completer<DemoAuthPhoneResult>();
    final controller = await pumpFlow(
      tester,
      _FakeService(
        start: (n) => n == 1 ? Future.value(_okStart) : staleResend.future,
        verifyPhoneCall: () => currentVerify.future,
      ),
    );

    final stale = controller.resendSms();
    await tester.pump();
    final current = controller.submitSmsCode('123456');
    await tester.pump();

    staleResend.completeError(StateError('поздний сбой'));
    await stale;
    await tester.pump();
    expect(controller.isLoading, isTrue);
    expect(controller.error, isNull);

    currentVerify.completeError(StateError('текущий сбой'));
    await current;
    await settleFrames(tester);
    expectNoEndlessSpinner(controller);
  });

  // AC:RL-demo-auth-no-endless-spinner/7
  testWidgets('AC-7: ввод кода без тикета не роняет флоу в вечную загрузку', (
    tester,
  ) async {
    final requests = <String>[];
    final controller = await pumpFlow(
      tester,
      http200((request) {
        requests.add(request.url.path);
        return http.Response(
          jsonEncode({'error': 'resend_too_soon', 'resend_available_in': 42}),
          429,
        );
      }),
    );

    // Ровно сценарий тикета: кода нет, человек всё равно вводит «000000».
    await controller.submitSmsCode('000000');
    await settleFrames(tester);

    expect(tester.takeException(), isNull);
    expectNoEndlessSpinner(controller);
    expect(requests, isNot(contains('/api/auth/phone/verify')));
  });
}

Future<void> settleFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
