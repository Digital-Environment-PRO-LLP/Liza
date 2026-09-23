import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/demo_auth_flow.dart';
import 'package:liza/pages/demo_auth/demo_auth_service.dart';
import 'package:liza/pages/demo_auth/widgets/code_input.dart';

/// ledger:RL-auth-otp-code-clear-on-fail
///
/// LABA-2528: после отказа `/phone/verify` ячейки кода пустеют, при неверном
/// коде курсор стоит в первой. Код вводится через реальные `TextField`
/// `CodeInput` — тем же путём, что и у человека (заполнение → onCompleted).
void main() {
  http.Response json(Map<String, Object?> body, int status) =>
      http.Response(jsonEncode(body), status);

  http.Response startOk([String channel = 'phone']) => json({
    'ticket': 't',
    'channel': channel,
    'masked_destination': '+7 999 ***-**-67',
  }, 200);

  final verifyOk = json({'status': 'login', 'has_email': false}, 200);

  /// Проверка кода идёт не мгновенно: кадр загрузки выключает ячейки и
  /// снимает с них фокус — как у человека. Без задержки ответ приходил до
  /// первого кадра, и фокусный страж зеленел даже без фикса.
  Future<void> verifyLatency() =>
      Future<void>.delayed(const Duration(milliseconds: 100));

  Future<DemoAuthFlowController> pumpFlow(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler, {
    Future<void> Function(DemoAuthTokens)? onAuthenticated,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => DemoAuthFlow(
            phone: '+79991234567',
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
        locale: const Locale('ru'),
      ),
    );
    await tester.pumpAndSettle();
    return tester.state<DemoAuthFlowController>(find.byType(DemoAuthFlow));
  }

  Finder cellFinder() => find.descendant(
    of: find.byType(CodeInput),
    matching: find.byType(TextField),
  );

  List<String> cells(WidgetTester tester) => tester
      .widgetList<TextField>(cellFinder())
      .map((field) => field.controller!.text)
      .toList();

  bool firstCellFocused(WidgetTester tester) =>
      tester.widget<TextField>(cellFinder().first).focusNode!.hasFocus;

  bool anyCellFocused(WidgetTester tester) => tester
      .widgetList<TextField>(cellFinder())
      .any((field) => field.focusNode!.hasFocus);

  /// Ввод как у человека: целый код в первую ячейку (вставка/автозаполнение)
  /// раскладывается по ячейкам и сам уходит на проверку.
  Future<void> typeCode(WidgetTester tester, String code) async {
    await tester.enterText(cellFinder().first, code);
    await tester.pump();
    expect(
      tester.widget<TextField>(cellFinder().first).enabled,
      isFalse,
      reason: 'кадр «проверка идёт» обязан выключить ячейки',
    );
    await tester.pumpAndSettle();
  }

  /// Ввод по одной цифре в ячейку с фокусом — как с клавиатуры: цифра
  /// дописывается к тому, что в ячейке уже есть. Именно так ломался ввод
  /// до фикса: в заполненной ячейке получалось две цифры и ветка вставки
  /// перераскладывала код.
  Future<void> typeDigitsIntoFocusedCell(
    WidgetTester tester,
    String code,
  ) async {
    for (final digit in code.split('')) {
      final focused = tester
          .widgetList<TextField>(cellFinder())
          .where((field) => field.focusNode!.hasFocus)
          .toList();
      expect(focused, hasLength(1), reason: 'нет ячейки с фокусом для $digit');
      final field = focused.single;
      await tester.enterText(
        find.byWidget(field),
        field.controller!.text + digit,
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  const empty = ['', '', '', '', '', ''];

  // Кейсы отказа verify: код отклонён сервером и обрыв сети до ответа.
  const rejectCases = {
    'invalid_code': 400,
    'otp_expired': 400,
    'otp_attempts_exhausted': 429,
    'network_error': 0,
  };

  Future<http.Response> Function(http.Request) rejectingVerify(
    String code,
    int status,
  ) => (request) async {
    if (request.url.path.endsWith('/phone/start')) return startOk();
    if (request.url.path.endsWith('/phone/verify')) {
      await verifyLatency();
      // Исключение транспорта сервис превращает в `network_error`.
      if (status == 0) throw http.ClientException('offline');
      return json({'error': code}, status);
    }
    throw StateError('Unexpected request: ${request.url.path}');
  };

  for (final MapEntry(key: code, value: status) in rejectCases.entries) {
    // AC:RL-auth-otp-code-clear-on-fail/1
    // AC:RL-auth-otp-code-clear-on-fail/2
    testWidgets('AC-1/AC-2: $code очищает все 6 ячеек, ошибка остаётся', (
      tester,
    ) async {
      final controller = await pumpFlow(
        tester,
        rejectingVerify(code, status),
      );

      await typeCode(tester, '123456');

      expect(cells(tester), empty);
      expect(controller.errorCode, code);
      expect(controller.error, isNotNull);
      expect(controller.isLoading, isFalse);
    });
  }

  // AC:RL-auth-otp-code-clear-on-fail/2
  testWidgets('AC-2: «Неверный код» виден на экране после очистки', (
    tester,
  ) async {
    await pumpFlow(tester, rejectingVerify('invalid_code', 400));
    final l10n = L10n.of(tester.element(find.byType(DemoAuthFlow)));

    await typeCode(tester, '123456');

    expect(find.text(l10n.demoAuthInvalidCode), findsOneWidget);
  });

  // AC:RL-auth-otp-code-clear-on-fail/3
  testWidgets('AC-3: после invalid_code курсор в первой ячейке', (
    tester,
  ) async {
    await pumpFlow(tester, rejectingVerify('invalid_code', 400));

    await typeCode(tester, '123456');

    expect(tester.widget<TextField>(cellFinder().first).enabled, isTrue);
    expect(firstCellFocused(tester), isTrue);
  });

  for (final code in ['otp_expired', 'otp_attempts_exhausted']) {
    // AC:RL-auth-otp-code-clear-on-fail/4
    testWidgets('AC-4: после $code курсор не ставится', (tester) async {
      await pumpFlow(tester, rejectingVerify(code, 400));

      await typeCode(tester, '123456');

      expect(cells(tester), empty);
      expect(anyCellFocused(tester), isFalse);
    });
  }

  // AC:RL-auth-otp-code-clear-on-fail/5
  testWidgets('AC-5: повторный ввод уходит в verify ровно новым кодом', (
    tester,
  ) async {
    final verifiedCodes = <String>[];
    await pumpFlow(tester, (request) async {
      if (request.url.path.endsWith('/phone/start')) return startOk();
      if (request.url.path.endsWith('/phone/verify')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        verifiedCodes.add(body['code'] as String);
        await verifyLatency();
        return json({'error': 'invalid_code'}, 400);
      }
      throw StateError('Unexpected request: ${request.url.path}');
    });

    await typeCode(tester, '123456');
    await typeDigitsIntoFocusedCell(tester, '654321');

    expect(verifiedCodes, ['123456', '654321']);
  });

  // AC:RL-auth-otp-code-clear-on-fail/6
  testWidgets('AC-6: поздний отказ устаревшей проверки не трогает ячейки', (
    tester,
  ) async {
    final staleVerify = Completer<http.Response>();
    var starts = 0;
    final controller = await pumpFlow(tester, (request) async {
      if (request.url.path.endsWith('/phone/start')) {
        starts++;
        return startOk(starts == 1 ? 'phone' : 'email');
      }
      if (request.url.path.endsWith('/phone/verify')) {
        return staleVerify.future;
      }
      throw StateError('Unexpected request: ${request.url.path}');
    });

    // Проверка висит — человек уходит в «Другой способ»: новый запрос
    // становится актуальным, ответ старой проверки — устаревшим.
    await tester.enterText(cellFinder().first, '123456');
    await tester.pump();
    await controller.switchChannel(DemoAuthChannel.email);
    await tester.pumpAndSettle();
    final before = cells(tester);

    staleVerify.complete(json({'error': 'invalid_code'}, 400));
    await tester.pumpAndSettle();

    expect(controller.codeRejections, 0);
    expect(controller.errorCode, isNull);
    expect(cells(tester), before);
  });

  // AC:RL-auth-otp-code-clear-on-fail/7
  testWidgets('AC-7: отказ повтора и переключения не чистит набранное', (
    tester,
  ) async {
    var starts = 0;
    final controller = await pumpFlow(tester, (request) async {
      if (request.url.path.endsWith('/phone/start')) {
        starts++;
        if (starts == 1) return startOk('email');
        return json({'error': 'resend_too_soon'}, 429);
      }
      throw StateError('Unexpected request: ${request.url.path}');
    });

    // Две цифры из шести — код ещё не ушёл на проверку.
    await tester.enterText(cellFinder().first, '12');
    await tester.pumpAndSettle();
    const partial = ['1', '2', '', '', '', ''];
    expect(cells(tester), partial);

    await controller.resendSms();
    await tester.pumpAndSettle();
    expect(controller.errorCode, 'resend_too_soon');
    expect(cells(tester), partial);

    await controller.switchChannel(DemoAuthChannel.phone);
    await tester.pumpAndSettle();
    expect(controller.errorCode, 'resend_too_soon');
    expect(cells(tester), partial);
    expect(controller.codeRejections, 0);
  });

  // AC:RL-auth-otp-code-clear-on-fail/8
  testWidgets('AC-8: провал complete после успешного verify не чистит поле', (
    tester,
  ) async {
    final controller = await pumpFlow(tester, (request) async {
      if (request.url.path.endsWith('/phone/start')) return startOk();
      if (request.url.path.endsWith('/phone/verify')) {
        await verifyLatency();
        return verifyOk;
      }
      if (request.url.path.endsWith('/complete')) {
        return json({'error': 'synapse_error'}, 502);
      }
      throw StateError('Unexpected request: ${request.url.path}');
    });

    await typeCode(tester, '123456');

    expect(controller.errorCode, 'synapse_error');
    expect(controller.codeRejections, 0);
    expect(cells(tester), ['1', '2', '3', '4', '5', '6']);
  });

  // AC:RL-auth-otp-code-clear-on-fail/9
  testWidgets('AC-9: верный код по-прежнему завершает вход', (tester) async {
    DemoAuthTokens? authenticated;
    await pumpFlow(
      tester,
      (request) async {
        if (request.url.path.endsWith('/phone/start')) return startOk();
        if (request.url.path.endsWith('/phone/verify')) return verifyOk;
        if (request.url.path.endsWith('/complete')) {
          return json({
            'login_token': 'token',
            'server_name': 'example.com',
            'user_id': '@user:example.com',
          }, 200);
        }
        throw StateError('Unexpected request: ${request.url.path}');
      },
      onAuthenticated: (tokens) async => authenticated = tokens,
    );

    await tester.enterText(cellFinder().first, '123456');
    // В тестовом callback нет навигации — экран остаётся в загрузке, и
    // pumpAndSettle ждал бы спиннер вечно.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(authenticated?.loginToken, 'token');
  });

  // AC:RL-auth-otp-code-clear-on-fail/10
  testWidgets('AC-10: ticket_expired по-прежнему уводит на первый экран', (
    tester,
  ) async {
    await pumpFlow(tester, rejectingVerify('ticket_expired', 400));

    await typeCode(tester, '123456');

    expect(find.text('home-screen'), findsOneWidget);
    expect(find.byType(DemoAuthFlow), findsNothing);
  });
}
