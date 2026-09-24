// ledger:RL-add-account-phone-stays-in-flow
//
// Разработчик нажимал «Добавить аккаунт», вводил номер телефона — и его
// выкидывало в список чатов (@maksim.korolev:liza.cyber-agro.ru, 2026-09-23).
// Ввод номера делал go('/auth/phone'), а этот маршрут стоит под
// loggedInRedirect: уже вошедшего уводило на /rooms, код даже не заказывался.
// Парольный путь добавления ходил вложенными маршрутами и работал, поэтому
// регресс (с 9caaee64, телефон по умолчанию) никто не ловил.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/config/routes.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/demo_auth_flow.dart';
import 'package:liza/pages/demo_auth/demo_auth_service.dart';
import 'package:liza/pages/homeserver_picker/homeserver_picker.dart';

const _phone = '+79800550404';

/// Полный путь → маршрут по всему дереву приложения.
Map<String, GoRoute> _collectRoutes(
  List<RouteBase> routes, [
  String prefix = '',
]) {
  final result = <String, GoRoute>{};
  for (final route in routes) {
    if (route is GoRoute) {
      final path = (route.path.startsWith('/')
              ? route.path
              : '$prefix/${route.path}')
          .replaceAll('//', '/');
      result[path] = route;
      result.addAll(_collectRoutes(route.routes, path));
    } else {
      result.addAll(_collectRoutes(route.routes, prefix));
    }
  }
  return result;
}

class _Service extends DemoAuthService {
  _Service({this.startError})
    : super(client: MockClient((_) async => http.Response('', 500)));

  final DemoAuthException? startError;

  @override
  Future<DemoAuthStartResult> startPhone(
    String phone, {
    String? ticket,
    String? channel,
  }) async {
    final error = startError;
    if (error != null) throw error;
    return const DemoAuthStartResult(
      ticket: 't',
      maskedDestination: '+7 980 ***-**-04',
      resendAvailableIn: 60,
    );
  }
}

/// Уже вошедший пользователь: верхние /home и /auth/phone уводят его в
/// чаты — ровно как AppRoutes.loggedInRedirect.
String _loggedIn(BuildContext _, GoRouterState _) => '/rooms';

GoRouter _router({
  required String initialLocation,
  required Widget Function(GoRouterState state) phonePage,
  Widget Function(BuildContext context)? addAccountPage,
}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(path: '/home', redirect: _loggedIn),
    GoRoute(
      path: '/auth/phone',
      redirect: _loggedIn,
      builder: (_, _) => const Text('auth-phone'),
    ),
    GoRoute(
      path: '/rooms',
      builder: (_, _) => const Text('rooms'),
      routes: [
        GoRoute(
          path: 'settings/addaccount',
          builder: (context, _) =>
              addAccountPage?.call(context) ?? const Text('addaccount'),
          routes: [
            GoRoute(path: 'phone', builder: (_, state) => phonePage(state)),
          ],
        ),
      ],
    ),
  ],
);

Future<void> _pump(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: const Locale('ru'),
    ),
  );
  // Не pumpAndSettle: на шаге ожидания кода крутится спиннер.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Верхний маршрут стека с учётом push (URL push не меняет).
String _location(GoRouter router) =>
    router.routerDelegate.currentConfiguration.last.matchedLocation;

void main() {
  final routes = _collectRoutes(AppRoutes.routes);

  // AC:RL-add-account-phone-stays-in-flow/1
  test('AC-1: в prod-сборке есть /rooms/settings/addaccount/phone и '
      '/auth/phone для первого входа', () {
    expect(AppConfig.phoneAuthEnabled, isTrue);
    expect(routes.keys, contains('/rooms/settings/addaccount/phone'));
    expect(routes.keys, contains('/auth/phone'));
  });

  // AC:RL-add-account-phone-stays-in-flow/2
  test('AC-2: маршрут добавления пускает вошедшего (loggedOutRedirect), '
      '/auth/phone — по-прежнему только для невошедших', () {
    expect(
      routes['/rooms/settings/addaccount/phone']!.redirect,
      AppRoutes.loggedOutRedirect,
    );
    expect(routes['/auth/phone']!.redirect, AppRoutes.loggedInRedirect);
  });

  // AC:RL-add-account-phone-stays-in-flow/3
  group('AC-3: отправка номера', () {
    testWidgets('из «Добавить аккаунт» остаётся во флоу добавления', (
      tester,
    ) async {
      final router = _router(
        initialLocation: addAccountPath,
        addAccountPage: (context) => TextButton(
          onPressed: () =>
              openPhoneAuth(context, _phone, addMultiAccount: true),
          child: const Text('submit'),
        ),
        phonePage: (state) => Text('phone:${state.extra}'),
      );
      await _pump(tester, router);
      await tester.tap(find.text('submit'));
      await tester.pumpAndSettle();

      expect(find.text('rooms'), findsNothing);
      expect(find.text('phone:$_phone'), findsOneWidget);
      expect(_location(router), '$addAccountPath/phone');
    });

    testWidgets('первый вход — прежний /auth/phone', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, _) => TextButton(
              onPressed: () =>
                  openPhoneAuth(context, _phone, addMultiAccount: false),
              child: const Text('submit'),
            ),
          ),
          GoRoute(
            path: '/auth/phone',
            builder: (_, state) => Text('auth-phone:${state.extra}'),
          ),
        ],
      );
      await _pump(tester, router);
      await tester.tap(find.text('submit'));
      await tester.pumpAndSettle();

      expect(find.text('auth-phone:$_phone'), findsOneWidget);
    });
  });

  // AC:RL-add-account-phone-stays-in-flow/4
  group('AC-4: любой выход из флоу добавления — на экран добавления', () {
    Future<GoRouter> pumpFlow(
      WidgetTester tester, {
      String phone = _phone,
      DemoAuthException? startError,
      bool addMultiAccount = true,
    }) async {
      final router = _router(
        initialLocation: '$addAccountPath/phone',
        phonePage: (_) => DemoAuthFlow(
          phone: phone,
          addMultiAccount: addMultiAccount,
          service: _Service(startError: startError),
          onAuthenticated: (_) async {},
        ),
      );
      await _pump(tester, router);
      return router;
    }

    Future<void> expectOnAddAccount(WidgetTester tester, GoRouter router) async {
      await tester.pumpAndSettle();
      expect(_location(router), addAccountPath);
      expect(find.text('addaccount'), findsOneWidget);
      expect(find.text('rooms'), findsNothing);
    }

    testWidgets('«назад» на шаге кода', (tester) async {
      final router = await pumpFlow(tester);
      final flow = tester.state<DemoAuthFlowController>(
        find.byType(DemoAuthFlow),
      );
      expect(flow.step, DemoAuthStep.sms);
      flow.back();
      await expectOnAddAccount(tester, router);
    });

    testWidgets('истёкшая сессия (ticket_expired)', (tester) async {
      final router = await pumpFlow(
        tester,
        startError: const DemoAuthException('ticket_expired'),
      );
      await expectOnAddAccount(tester, router);
    });

    testWidgets('пустой номер (web: F5 теряет extra)', (tester) async {
      final router = await pumpFlow(tester, phone: '');
      await expectOnAddAccount(tester, router);
    });

    test('первый вход по-прежнему выходит на /home', () {
      expect(demoAuthExitPath(addMultiAccount: false), '/home');
      expect(demoAuthExitPath(addMultiAccount: true), addAccountPath);
    });
  });
}
