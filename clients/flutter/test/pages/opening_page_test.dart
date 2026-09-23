// ledger:RL-deeplink-target-resolve
// ledger:RL-user-invite-link-opens-profile
// AC:RL-user-invite-link-opens-profile/8
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/opening/opening_page.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: child,
      );

  testWidgets('показывает прогресс, пока цель не разрешена', (tester) async {
    await tester.pumpWidget(
      wrap(
        OpeningPage(
          code: 'p_AbCdEfGh',
          resolve: () async {
            await Future<void>.delayed(const Duration(seconds: 30));
            return '/rooms/!abc';
          },
          onNavigated: (_) {},
        ),
      ),
    );
    // Ресурсы локализации грузятся через deferFirstFrame/allowFirstFrame
    // (см. LocalizationsState._load) — первый кадр до их загрузки рисует
    // SizedBox.shrink. pump(Duration.zero) прогоняет микротаски и снимает
    // deferFirstFrame, не трогая реальные Timer виджета.
    await tester.pump(Duration.zero);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Открываем…'), findsOneWidget);
    // Досрочно завершаем отложенный таймер, чтобы тест не падал на pending timer.
    await tester.pump(const Duration(seconds: 31));
  });

  testWidgets('по неуспеху показывает ошибку и кнопку повтора; '
      'нормализация URL НЕ вызывается', (tester) async {
    final navigated = <String>[];
    await tester.pumpWidget(
      wrap(
        OpeningPage(
          code: 'p_AbCdEfGh',
          resolve: () async => throw Exception('boom'),
          onNavigated: navigated.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Не удалось открыть ссылку'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
    // AC-8: при ошибке адресная строка нужна кнопке «Повторить» — не трогаем.
    expect(navigated, isEmpty);
  });

  testWidgets('после успешной навигации нормализация URL вызывается один раз '
      'с путём цели', (tester) async {
    // AC-8: на вебе после `/i/<code>` → SPA-навигации pathname остался бы в
    // адресной строке (hash-стратегия меняет только `#…`) — колбэк чистит его
    // РОВНО после успешного перехода, не раньше и не при ошибке.
    final navigated = <String>[];
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => OpeningPage(
            code: 'd_KH3HsAxgUB',
            resolve: () async => '/rooms',
            onNavigated: navigated.add,
          ),
        ),
        GoRoute(
          path: '/rooms',
          builder: (context, state) => const Scaffold(body: Text('ROOMS')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ROOMS'), findsOneWidget);
    expect(navigated, ['/rooms']);
  });
}
