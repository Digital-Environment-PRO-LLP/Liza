// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/settings/settings.dart';
import 'package:liza/utils/user_handle_service.dart';
import 'package:liza/widgets/matrix.dart' as liza_matrix;

import '../../utils/test_client.dart';

// Полноценный Matrix-виджет неоправданно тяжёл — подменяем только геттер
// client, как в channel_peek_message_render_test.dart.
class _TestMatrixState extends liza_matrix.MatrixState {
  _TestMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

/// Сервис с заранее заданным ответом fetchOwn, без сети — гейт проверяем
/// изолированно от реального auth-proxy и от Task 4.
class _StubHandleService extends UserHandleService {
  _StubHandleService({this.state, this.throwOnFetch = false})
      : super(
          baseUrl: 'https://auth.test',
          accessTokenProvider: () => 'token',
          serverNameProvider: () => 'bots.liza.ru',
        );

  final HandleState? state;
  final bool throwOnFetch;

  @override
  Future<HandleState> fetchOwn() async {
    if (throwOnFetch) throw Exception('boom');
    return state ?? HandleState.disabled;
  }
}

Widget _wrap(Client client, UserHandleService service) {
  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (context, state) => Provider<liza_matrix.MatrixState>.value(
          value: _TestMatrixState(client),
          child: Settings(handleService: service),
        ),
      ),
    ],
  );
  return MaterialApp.router(
    locale: const Locale('ru'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    routerConfig: router,
  );
}

void main() {
  testWidgets('гейт доступен — пункт «Имя пользователя» виден', (tester) async {
    late final Client client;
    await tester.runAsync(() async {
      client = await prepareTestClient(loggedIn: true);
    });
    addTearDown(client.dispose);

    final service = _StubHandleService(
      state: const HandleState(handle: null, available: true),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(client, service));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      await tester.pump();
    });

    expect(find.text('Имя пользователя'), findsOneWidget);
  });

  testWidgets('гейт недоступен — пункта нет', (tester) async {
    late final Client client;
    await tester.runAsync(() async {
      client = await prepareTestClient(loggedIn: true);
    });
    addTearDown(client.dispose);

    final service = _StubHandleService(
      state: const HandleState(handle: null, available: false),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(client, service));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      await tester.pump();
    });

    expect(find.text('Имя пользователя'), findsNothing);
  });

  testWidgets('сервис бросает исключение — пункта нет, экран цел',
      (tester) async {
    late final Client client;
    await tester.runAsync(() async {
      client = await prepareTestClient(loggedIn: true);
    });
    addTearDown(client.dispose);

    final service = _StubHandleService(throwOnFetch: true);

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(client, service));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      await tester.pump();
    });

    expect(find.text('Имя пользователя'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
