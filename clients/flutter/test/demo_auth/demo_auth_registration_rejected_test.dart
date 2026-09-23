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
import 'package:liza/pages/demo_auth/widgets/code_input.dart';
import 'package:liza/pages/demo_auth/widgets/demo_auth_scaffold.dart';

/// ledger:RL-demo-auth-keycloak-4xx-honest
///
/// LABA-2527: Keycloak отверг карточку нового пользователя (`/complete` →
/// 422 `registration_rejected`). Это не «сервис недоступен»: человек видит
/// честный текст с действием и кнопку поддержки, спиннер снят, поле кода
/// не тронуто (код был верным — чистить нечего). Прогон — на РЕАЛЬНОМ
/// `DemoAuthFlow` за `MockClient`, как у соседних стражей.
void main() {
  http.Response json(Map<String, Object?> body, int status) =>
      http.Response(jsonEncode(body), status);

  Future<DemoAuthFlowController> pumpFlow(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => DemoAuthFlow(
            phone: '+79991234567',
            service: DemoAuthService(client: MockClient(handler)),
            onAuthenticated: (_) async {},
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

  Future<http.Response> Function(http.Request) rejectedRegistration(
    int completeStatus,
    String completeError,
  ) => (request) async {
    if (request.url.path.endsWith('/phone/start')) {
      return json({
        'ticket': 't',
        'channel': 'phone',
        'masked_destination': '+63 ******8833',
      }, 200);
    }
    if (request.url.path.endsWith('/phone/verify')) {
      return json({'status': 'register'}, 200);
    }
    if (request.url.path.endsWith('/complete')) {
      // `message` сервера клиент не читает (текст берётся из l10n по коду);
      // кириллица в теле `http.Response` без charset упала бы в latin-1.
      return json({'error': completeError}, completeStatus);
    }
    throw StateError('Unexpected request: ${request.url.path}');
  };

  // AC:RL-demo-auth-keycloak-4xx-honest/7
  // AC:RL-demo-auth-keycloak-4xx-honest/8
  testWidgets(
    'AC-7: 422 registration_rejected — честный текст, кнопка поддержки, '
    'спиннер снят, поле не очищено',
    (tester) async {
      final controller = await pumpFlow(
        tester,
        rejectedRegistration(422, 'registration_rejected'),
      );
      final l10n = L10n.of(tester.element(find.byType(DemoAuthFlow)));

      await tester.enterText(cellFinder().first, '000000');
      await tester.pumpAndSettle();

      expect(controller.isLoading, isFalse);
      expect(controller.errorCode, 'registration_rejected');
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Текст — новый ключ, не «сервис недоступен» и не generic.
      expect(find.text(l10n.demoAuthRegistrationRejected), findsOneWidget);
      expect(find.text(l10n.demoAuthKeycloakError), findsNothing);
      expect(find.text(l10n.demoAuthGenericError), findsNothing);

      // Тупиковый код: под текстом — крупная кнопка поддержки
      // (`deadEndErrorCodes`), повтор кода бессмыслен.
      expect(deadEndErrorCodes, contains('registration_rejected'));
      expect(
        find.widgetWithText(ElevatedButton, l10n.supportContactButton),
        findsOneWidget,
      );

      // Провал complete — не отказ verify: поле кода не пересоздано
      // (зеркало AC-8 RL-auth-otp-code-clear-on-fail).
      expect(controller.codeRejections, 0);
      expect(cells(tester), ['0', '0', '0', '0', '0', '0']);
      expect(find.byType(DemoAuthFlow), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  // AC:RL-demo-auth-keycloak-4xx-honest/9
  testWidgets('AC-9: 502 keycloak_error по-прежнему «сервис недоступен»', (
    tester,
  ) async {
    final controller = await pumpFlow(
      tester,
      rejectedRegistration(502, 'keycloak_error'),
    );
    final l10n = L10n.of(tester.element(find.byType(DemoAuthFlow)));

    await tester.enterText(cellFinder().first, '000000');
    await tester.pumpAndSettle();

    expect(controller.errorCode, 'keycloak_error');
    expect(find.text(l10n.demoAuthKeycloakError), findsOneWidget);
    expect(find.text(l10n.demoAuthRegistrationRejected), findsNothing);
  });

  // AC:RL-demo-auth-keycloak-4xx-honest/6
  test('AC-6: ключ demoAuthRegistrationRejected есть в en и ru', () {
    // CI-гейта на паритет .arb нет: без ru-строки Flutter молча подставил
    // бы английский текст в русском интерфейсе.
    final en = File('lib/l10n/intl_en.arb').readAsStringSync();
    final ru = File('lib/l10n/intl_ru.arb').readAsStringSync();
    final enValue =
        (jsonDecode(en) as Map<String, dynamic>)['demoAuthRegistrationRejected']
            as String?;
    final ruValue =
        (jsonDecode(ru) as Map<String, dynamic>)['demoAuthRegistrationRejected']
            as String?;
    expect(enValue, isNotNull);
    expect(ruValue, isNotNull);
    expect(ruValue, isNot(enValue));
    expect(RegExp('[а-яА-ЯёЁ]').hasMatch(ruValue!), isTrue);
    expect(ruValue, isNot(contains('недоступен')));
  });
}
