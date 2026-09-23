// ledger:RL-user-handles AC:RL-user-handles/5
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Сервис с заранее заданным ответом fetchOwn, без сети — шапку настроек
/// проверяем изолированно от реального auth-proxy.
class _StubHandleService extends UserHandleService {
  _StubHandleService({this.state})
      : super(
          baseUrl: 'https://auth.test',
          accessTokenProvider: () => 'token',
          serverNameProvider: () => 'bots.liza.ru',
        );

  final HandleState? state;

  @override
  Future<HandleState> fetchOwn() async => state ?? HandleState.disabled;
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
  testWidgets('ник задан — шапка настроек показывает @ник, а не MXID',
      (tester) async {
    late final Client client;
    await tester.runAsync(() async {
      client = await prepareTestClient(loggedIn: true);
    });
    addTearDown(client.dispose);

    final service = _StubHandleService(
      state: const HandleState(handle: 'ivan_petrov', available: true),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(client, service));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      await tester.pump();
    });

    expect(find.text('@ivan_petrov'), findsOneWidget);
    expect(find.text(client.userID!), findsNothing);
  });

  testWidgets('ника нет — шапка настроек показывает MXID, как раньше',
      (tester) async {
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

    expect(find.text(client.userID!), findsOneWidget);
  });

  testWidgets('ник задан — копирование кладёт в буфер @ник, а не MXID',
      (tester) async {
    late final Client client;
    await tester.runAsync(() async {
      client = await prepareTestClient(loggedIn: true);
    });
    addTearDown(client.dispose);

    final service = _StubHandleService(
      state: const HandleState(handle: 'ivan_petrov', available: true),
    );

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(client, service));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      await tester.pump();
    });

    await tester.tap(find.text('@ivan_petrov'));
    await tester.pump();

    expect(copied, '@ivan_petrov');
  });
}
