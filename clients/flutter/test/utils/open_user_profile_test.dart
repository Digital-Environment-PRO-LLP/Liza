// ledger:RL-user-invite-link-opens-profile
// AC:RL-user-invite-link-opens-profile/5 AC:RL-user-invite-link-opens-profile/6
// guard.render:real-widget
//
// Real-widget страж: user-инвайт после резолва открывает РЕАЛЬНЫЙ UserDialog
// поверх экрана (тот же openUserProfile, что и у ссылки `/u/<ник>`), а не
// список чатов; для своей ссылки карточка без «Начать общение».
// Red-proof: до фикса user-инвайт вообще не доходил до карточки
// (startDirectChat → 403 → /rooms) — find.byType(UserDialog) пуст.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/opening/opening_page.dart';
import 'package:liza/utils/deep_link_target.dart';
import 'package:liza/utils/open_user_profile.dart';
import 'package:liza/utils/user_handle_service.dart';
import 'package:liza/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:liza/widgets/matrix.dart' as liza_matrix;

import 'test_client.dart';

const _bob = '@bob:example.invalid';

class _StubHandleService extends UserHandleService {
  _StubHandleService()
      : super(
          baseUrl: 'auth.test',
          accessTokenProvider: () => 'token',
          serverNameProvider: () => 'example.invalid',
          httpClient: MockClient((request) async {
            fail('карточка не должна ходить в auth-proxy: $request');
          }),
        );

  @override
  String? cachedHandleFor(String mxid) => null;
}

class _TestMatrixState extends liza_matrix.MatrixState {
  _TestMatrixState(this._client, this._store);

  final Client _client;
  final SharedPreferences _store;
  final _handles = _StubHandleService();

  @override
  Client get client => _client;

  @override
  UserHandleService get userHandleService => _handles;

  // Кольцо сторис на аватаре читает store (StoriesSeenStore) — виджету
  // MatrixState тут нет, отдаём мок SharedPreferences.
  @override
  SharedPreferences get store => _store;

  @override
  bool isAiUser(String userId) => false;
}

// Avatar заводит MxcImage._tryLoad с exp-backoff — сливаем таймеры вручную,
// как в test/pages/chat/draft_chat_page_test.dart.
Future<void> _drainAvatarRetryTimers(WidgetTester tester) async {
  for (final delay in const [
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 9),
    Duration(seconds: 17),
    Duration(seconds: 31),
  ]) {
    await tester.pump(delay);
  }
}

/// Резолв → context.go → переход страницы → пост-кадровый колбэк → сетевой
/// профиль (FakeMatrixApi под runAsync) → showDialog: несколько реальных пауз
/// с кадрами между ними; pumpAndSettle не сходится из-за таймеров аватара.
Future<void> _settleAsync(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late Client client;
  late SharedPreferences store;
  final navigatorKey = GlobalKey<NavigatorState>();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await SharedPreferences.getInstance();
    client = await prepareTestClient(loggedIn: true);
    final api = (client.httpClient as dynamic).inner as FakeMatrixApi;
    api.api['GET']!['/client/v3/profile/%40bob%3Aexample.invalid'] =
        (_) => {'displayname': 'Боб'};
  });

  tearDown(() => client.dispose());

  /// Приложение с роутером: `/` — OpeningPage, чей resolve делает ровно то,
  /// что closure `/opening/:code` в routes.dart — побочный эффект цели через
  /// openUserProfile + путь через deepLinkRoutePath.
  Widget app(DeepLinkTarget target) {
    final router = GoRouter(
      navigatorKey: navigatorKey,
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => OpeningPage(
            code: 'd_KH3HsAxgUB',
            resolve: () async {
              switch (deepLinkSideEffect(target)) {
                case OpenUserProfile(:final userId):
                  openUserProfile(
                    client,
                    userId,
                    navigatorContext: () => navigatorKey.currentContext,
                  );
                case null:
                  break;
              }
              return deepLinkRoutePath(target);
            },
            onNavigated: (_) {},
          ),
        ),
        GoRoute(
          path: '/rooms',
          builder: (context, state) => const Scaffold(body: Text('ROOMS')),
        ),
      ],
    );
    return Provider<liza_matrix.MatrixState>.value(
      value: _TestMatrixState(client, store),
      child: MaterialApp.router(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        routerConfig: router,
      ),
    );
  }

  testWidgets(
    'AC-5: чужая ссылка → список чатов + реальный UserDialog с «Начать общение»',
    (tester) async {
      await tester.pumpWidget(app(const DeepLinkUser(_bob)));
      await _settleAsync(tester);
      expect(find.text('ROOMS'), findsOneWidget);
      expect(find.byType(UserDialog), findsOneWidget);
      expect(find.text('Боб'), findsWidgets);
      expect(find.text('Начать общение'), findsOneWidget);
      await _drainAvatarRetryTimers(tester);
    },
  );

  testWidgets(
    'AC-6: своя ссылка → карточка своего профиля без «Начать общение»',
    (tester) async {
      await tester.pumpWidget(app(DeepLinkUser(client.userID!)));
      await _settleAsync(tester);
      expect(find.byType(UserDialog), findsOneWidget);
      expect(find.text('Начать общение'), findsNothing);
      expect(find.text('Закрыть'), findsOneWidget);
      await _drainAvatarRetryTimers(tester);
    },
  );

  testWidgets('цель без побочного эффекта карточку не открывает',
      (tester) async {
    await tester.pumpWidget(app(const DeepLinkNeutral()));
    await _settleAsync(tester);
    expect(find.text('ROOMS'), findsOneWidget);
    expect(find.byType(UserDialog), findsNothing);
  });
}
