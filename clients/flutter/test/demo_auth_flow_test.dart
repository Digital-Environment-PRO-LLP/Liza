import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/demo_auth_flow.dart';
import 'package:liza/pages/demo_auth/demo_auth_service.dart';

void main() {
  group('DemoAuthStep', () {
    test('шагов ввода почты и никнейма больше нет', () {
      final names = DemoAuthStep.values.map((s) => s.name).toList();
      expect(names, isNot(contains('email')));
      expect(names, isNot(contains('nickname')));
    });

    test('остались только starting, sms, emailCode и selectServer', () {
      expect(DemoAuthStep.values.map((s) => s.name).toSet(), {
        'starting',
        'sms',
        'emailCode',
        'selectServer',
      });
    });

    test('начальный шаг — ожидание, а не готовый экран СМС', () {
      // Канал доставки выбирает сервер. Пока `/phone/start` не ответил,
      // экран СМС рисовать нельзя: при доставке письмом он тут же
      // перерисовывался в «Код из письма» — человек видел мигание.
      expect(DemoAuthStep.values.first, DemoAuthStep.starting);
    });
  });

  group('DemoAuthChannel', () {
    test('на провод уходят те же строки, что понимает auth-proxy', () {
      expect(DemoAuthChannel.phone.wireName, 'phone');
      expect(DemoAuthChannel.email.wireName, 'email');
    });
  });

  testWidgets('email → SMS завершает сессию без повторного email OTP', (
    tester,
  ) async {
    final paths = <String>[];
    DemoAuthTokens? authenticated;
    final service = DemoAuthService(
      client: MockClient((request) async {
        paths.add(request.url.path);
        return switch (request.url.path) {
          '/api/auth/phone/start' => http.Response(
            jsonEncode({
              'ticket': 'ticket',
              'channel': paths.length == 1 ? 'email' : 'phone',
              'masked_destination': 'destination',
            }),
            200,
          ),
          '/api/auth/phone/verify' => http.Response(
            jsonEncode({'status': 'login', 'has_email': true}),
            200,
          ),
          '/api/auth/complete' => http.Response(
            jsonEncode({
              'login_token': 'token',
              'server_name': 'example.com',
              'user_id': '@user:example.com',
            }),
            200,
          ),
          _ => throw StateError('Unexpected request: ${request.url.path}'),
        };
      }),
    );

    await tester.pumpWidget(
      _testApp(
        DemoAuthFlow(
          phone: '+79991234567',
          service: service,
          onAuthenticated: (tokens) async => authenticated = tokens,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final controller = tester.state<DemoAuthFlowController>(
      find.byType(DemoAuthFlow),
    );

    expect(controller.currentChannel, DemoAuthChannel.email);
    await controller.switchChannel(DemoAuthChannel.phone);
    await tester.pumpAndSettle();
    await controller.submitSmsCode('123456');
    // В тестовом callback нет навигации, поэтому экран намеренно остаётся
    // loading. Одного кадра достаточно; pumpAndSettle ждёт этот индикатор.
    await tester.pump();

    expect(paths, [
      '/api/auth/phone/start',
      '/api/auth/phone/start',
      '/api/auth/phone/verify',
      '/api/auth/complete',
    ]);
    expect(authenticated?.loginToken, 'token');
  });

  testWidgets('поздний email-ответ не перезаписывает выбранный SMS-канал', (
    tester,
  ) async {
    final staleEmailResponse = Completer<http.Response>();
    var phoneStartCalls = 0;
    final service = DemoAuthService(
      client: MockClient((request) async {
        if (request.url.path != '/api/auth/phone/start') {
          throw StateError('Unexpected request: ${request.url.path}');
        }
        phoneStartCalls++;
        if (phoneStartCalls == 2) return staleEmailResponse.future;
        return http.Response(
          jsonEncode({
            'ticket': 'ticket',
            'channel': phoneStartCalls == 1 ? 'email' : 'phone',
            'masked_destination': phoneStartCalls == 1 ? 'email' : 'sms',
          }),
          200,
        );
      }),
    );

    await tester.pumpWidget(
      _testApp(DemoAuthFlow(phone: '+79991234567', service: service)),
    );
    await tester.pumpAndSettle();
    final controller = tester.state<DemoAuthFlowController>(
      find.byType(DemoAuthFlow),
    );

    final staleRequest = controller.resendSms(channel: 'email');
    await tester.pump();
    await controller.switchChannel(DemoAuthChannel.phone);
    await tester.pumpAndSettle();
    staleEmailResponse.complete(
      http.Response(
        jsonEncode({
          'ticket': 'ticket',
          'channel': 'email',
          'masked_destination': 'email',
        }),
        200,
      ),
    );
    await staleRequest;
    await tester.pumpAndSettle();

    expect(controller.step, DemoAuthStep.sms);
    expect(controller.currentChannel, DemoAuthChannel.phone);
    expect(controller.maskedPhone, 'sms');
  });
}

Widget _testApp(Widget home) => MaterialApp(
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: home,
);
