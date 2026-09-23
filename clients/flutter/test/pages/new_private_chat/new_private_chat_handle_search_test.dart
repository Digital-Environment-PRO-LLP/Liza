// ledger:RL-search-handle-profile-hydration
//
// Страж экрана «Новый личный чат» на РЕАЛЬНОМ виджете (NewPrivateChat →
// NewPrivateChatView): ввод ПРЕФИКСА @-ника без сигила находит человека и
// показывает его с именем из профиля, а не localpart (LABA-2552).
//
// Покрываемые AC (tests/registry/RL-search-handle-profile-hydration.md):
//   AC-1 (E3) профиль доступен → строка «Саша», localpart отсутствует.
//   AC-7 находка по нику префиксом попадает в результаты этого экрана
//        (раньше здесь был только точный resolve('@ник') — RL-user-handles
//        AC-33 «во всех трёх поисках» был ложным).
//   AC-5 (E3) после публикации списка повторная отрисовка не ходит за
//        профилем.
//
// Red-proof AC-7: убрать вызов searchHandles из new_private_chat.dart::_searchUser
// → directory и федерация здесь пусты, «Саша» не находится, тест красный.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/new_private_chat/new_private_chat.dart';
import 'package:liza/utils/federated_user_search_service.dart';
import 'package:liza/utils/user_handle_service.dart';
import 'package:liza/widgets/matrix.dart' as liza_matrix;

import '../../utils/test_client.dart';

const _sasha = '@user_f86a7e57:user.liza.ru';
const _sashaRoute = '/client/v3/profile/%40user_f86a7e57%3Auser.liza.ru';

/// auth-proxy без сети: префиксный поиск отдаёт Сашу на `alexx…`, точный
/// резолв — ничего (как на живом сервере для неполного ника).
class _StubHandleService extends UserHandleService {
  _StubHandleService()
      : super(
          baseUrl: 'auth.test',
          accessTokenProvider: () => 'token',
          serverNameProvider: () => 'example.invalid',
          httpClient: MockClient((request) async {
            fail('тест не должен ходить в auth-proxy: $request');
          }),
        );

  final _byMxid = <String, String>{};

  @override
  Future<List<UserHandleMatch>> searchHandles(String query) async {
    final normalized = query.trim().toLowerCase().replaceFirst('@', '');
    if (normalized.length < UserHandleService.minSearchPrefix) return const [];
    if (!'alexxandrines'.startsWith(normalized)) return const [];
    _byMxid[_sasha] = 'alexxandrines';
    return const [UserHandleMatch(handle: 'alexxandrines', mxid: _sasha)];
  }

  @override
  Future<String?> resolve(String handle) async => null;

  @override
  String? cachedHandleFor(String mxid) => _byMxid[mxid];
}

/// Федерация недоступна — как при выключенном модуле user_search_guard.
class _StubFederatedSearch extends FederatedUserSearchService {
  _StubFederatedSearch(super.client);

  @override
  Future<List<FederatedUserEntry>> searchUsers(String query) async => const [];
}

class _TestMatrixState extends liza_matrix.MatrixState {
  _TestMatrixState(this._client, this._handles);

  final Client _client;
  final UserHandleService _handles;

  @override
  Client get client => _client;

  @override
  UserHandleService get userHandleService => _handles;

  @override
  FederatedUserSearchService get federatedUserSearchService =>
      _StubFederatedSearch(_client);
}

// Client оборачивает httpClient в FixedTimeoutHttpClient — фейк лежит в inner.
FakeMatrixApi _api(Client client) =>
    (client.httpClient as dynamic).inner as FakeMatrixApi;

void main() {
  late Client client;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    // Локальный directory про человека с другого инстанса не знает.
    _api(client).api['POST']!['/client/v3/user_directory/search'] =
        (_) => {'results': <Map<String, Object?>>[], 'limited': false};
  });

  tearDown(() async {
    await client.dispose();
  });

  testWidgets(
      // AC:RL-search-handle-profile-hydration/1
      // AC:RL-search-handle-profile-hydration/7
      // AC:RL-search-handle-profile-hydration/5
      'ввод префикса ника без @ находит человека и показывает «Саша»',
      (tester) async {
    var profileCalls = 0;
    _api(client).api['GET']![_sashaRoute] = (_) {
      profileCalls++;
      return {'displayname': 'Саша'};
    };
    final handles = _StubHandleService();

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Provider<liza_matrix.MatrixState>.value(
            value: _TestMatrixState(client, handles),
            child: const NewPrivateChat(),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'alexxandr');
      // Дебаунс 500 мс + реальные await (FakeMatrixApi, БД) — ждём в реальной зоне.
      await Future<void>.delayed(const Duration(milliseconds: 700));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump();
    });

    expect(find.text('Саша'), findsOneWidget);
    expect(find.text('user_f86a7e57'), findsNothing);
    expect(find.text('@alexxandrines'), findsOneWidget,
        reason: 'подпись строки — ник (userIdentifier), заголовок — имя');
    expect(profileCalls, 1, reason: 'профиль запрошен один раз, в контроллере');

    // Повторная отрисовка уже опубликованного списка — без новых запросов.
    await tester.runAsync(() async {
      await tester.pump();
      await tester.pump();
    });
    expect(profileCalls, 1);
  });
}
