// ledger:RL-account-bundle-live-update
//
// Страж живого обновления пакетов аккаунтов (account bundles). Жалоба LABA-2542:
// «чтобы увидеть изменения при работе с пакетами (добавление аккаунта в пакет
// или удаление из пакета), необходимо обновлять страницу после каждого действия».
//
// Корень: `Client.setAccountData` в matrix-4.1.0 — голый PUT, локальную карту
// `client.accountData` и базу заполняет ТОЛЬКО разбор /sync. Пакеты читаются
// синхронными геттерами, поэтому сразу после await они отдавали старое.
//
// Покрываемые AC (tests/registry/RL-account-bundle-live-update.md):
//   AC-1 setAccountBundle виден в accountData ДО какого-либо /sync (3 кейса);
//   AC-2 removeFromAccountBundle виден там же ДО /sync (2 кейса);
//   AC-3 агрегат MatrixState.accountBundles пересчитан без ожидания сети;
//   AC-4 эхо записано и в базу (переживёт холодный старт до /sync);
//   AC-5 accountBundlesVersion бампается РОВНО на нужный тип account_data.
//
// ⚠️ Ловушка харнесса: FakeMatrixApi при непустом `_client` перехватывает
// PUT /account_data/ и САМ зовёт `_client.handleSync(...)` — то есть подделывает
// мгновенный sync и обновляет карту БЕЗ нашего фикса (ложно-зелёный, red-proof
// невозможен). Карта `api[method]?[action]` проверяется РАНЬШЕ этой ветки,
// поэтому эндпоинт регистрируется явно и возвращает пустой ответ: сервер принял,
// локально не изменилось ничего — ровно как в проде.
//
// Red-proof: убрать вызовы `_echoAccountBundles` в
// `lib/utils/account_bundles.dart` → AC-1..AC-4 краснеют.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/utils/account_bundles.dart';
import 'package:liza/widgets/matrix.dart' as liza_matrix;

import '../../utils/test_client.dart';

/// PUT пакетов, отвечающий пустым объектом БЕЗ подделки sync — иначе фейк
/// обновит `client.accountData` сам и тест перестанет проверять фикс.
///
/// Ключ строится по ФАКТИЧЕСКОМУ `client.userID`: фейковый логин выдаёт своего
/// пользователя, а не того, что передан в `prepareTestClient`.
void _registerBundlesEndpoint(Client client) {
  final api = (client.httpClient as dynamic).inner as FakeMatrixApi;
  final path =
      '/client/v3/user/${Uri.encodeComponent(client.userID!)}/account_data/$accountBundlesType';
  api.api['PUT']![path] = (req) => {};
}

Map<String, dynamic> _content(Client client) =>
    client.accountData[accountBundlesType]?.content ?? {};

List<String> _bundleNames(Client client) =>
    client.accountBundles.map((b) => b.name).whereType<String>().toList();

/// MatrixState с подставленным набором клиентов: `accountBundles` агрегирует
/// именно `widget.clients`.
class _TestMatrixState extends liza_matrix.MatrixState {
  _TestMatrixState(this._clients, this._store);

  final List<Client> _clients;
  final SharedPreferences _store;

  @override
  liza_matrix.Matrix get widget => liza_matrix.Matrix(
    clients: _clients,
    store: _store,
    child: const SizedBox(),
  );

  @override
  Client get client => _clients.first;
}

void main() {
  late Client client;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    _registerBundlesEndpoint(client);
  });

  tearDown(() async {
    await client.dispose();
  });

  // AC:RL-account-bundle-live-update/1
  group('AC-1 — добавление в пакет видно до /sync', () {
    test('первый пакет у аккаунта без account_data', () async {
      expect(_content(client), isEmpty, reason: 'предусловие: пакетов нет');

      await client.setAccountBundle('оене');

      expect(_bundleNames(client), contains('оене'));
    });

    test('добавление второго пакета к существующему', () async {
      await client.setAccountBundle('оене');
      await client.setAccountBundle('ауц');

      expect(_bundleNames(client), containsAll(<String>['оене', 'ауц']));
    });

    test('повторная запись того же пакета меняет приоритет, не дублирует', () async {
      await client.setAccountBundle('оене', 1);
      await client.setAccountBundle('оене', 5);

      final bundles = client.accountBundles
          .where((b) => b.name == 'оене')
          .toList();
      expect(bundles, hasLength(1));
      expect(bundles.single.priority, 5);
    });
  });

  // AC:RL-account-bundle-live-update/2
  group('AC-2 — удаление из пакета видно до /sync', () {
    test('удаляемый был не последним — прочие остались', () async {
      await client.setAccountBundle('оене');
      await client.setAccountBundle('ауц');
      await client.setAccountBundle('453');

      await client.removeFromAccountBundle('ауц');

      expect(_bundleNames(client), containsAll(<String>['оене', '453']));
      expect(_bundleNames(client), isNot(contains('ауц')));
    });

    test('удалён последний пакет — список пуст', () async {
      await client.setAccountBundle('оене');

      await client.removeFromAccountBundle('оене');

      // Геттер подставляет синтетический пакет из userID, когда своих нет.
      expect(
        (_content(client)['bundles'] as List?) ?? const [],
        isEmpty,
        reason: 'в account_data не должно остаться ни одного пакета',
      );
    });
  });

  // AC:RL-account-bundle-live-update/3
  test('AC-3 — агрегат MatrixState.accountBundles пересчитан без сети', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await SharedPreferences.getInstance();
    final matrix = _TestMatrixState([client], store);

    await client.setAccountBundle('оене');

    expect(matrix.accountBundles.keys, contains('оене'));

    await client.removeFromAccountBundle('оене');

    expect(matrix.accountBundles.keys, isNot(contains('оене')));
  });

  // AC:RL-account-bundle-live-update/4
  test('AC-4 — эхо записано в базу, переживёт холодный старт до /sync', () async {
    await client.setAccountBundle('оене');

    final stored = await client.database.getAccountData();
    final bundles =
        (stored[accountBundlesType]?.content['bundles'] as List?) ?? const [];

    expect(
      bundles.map((b) => (b as Map)['name']),
      contains('оене'),
      reason: 'без записи в базу холодный старт поднял бы старое значение',
    );
  });

  // AC:RL-account-bundle-live-update/5
  group('AC-5 — нотифаер бампается ровно на свой тип', () {
    late SharedPreferences store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = await SharedPreferences.getInstance();
    });

    /// Гоняет РЕАЛЬНЫЙ фильтр `MatrixState.applyAccountBundlesSync` — тот же
    /// метод, что зовёт подписка `onAccountDataSub`, а не его копию.
    int bumpsFor(SyncUpdate sync) {
      final matrix = _TestMatrixState([client], store);
      final before = matrix.accountBundlesVersion.value;
      matrix.applyAccountBundlesSync(sync);
      return matrix.accountBundlesVersion.value - before;
    }

    test('sync с пакетами — один бамп', () {
      expect(
        bumpsFor(
          SyncUpdate(
            nextBatch: 's1',
            accountData: [
              BasicEvent(type: accountBundlesType, content: const {}),
            ],
          ),
        ),
        1,
      );
    });

    test('sync без account_data — бампов нет', () {
      expect(bumpsFor(SyncUpdate(nextBatch: 's2')), 0);
    });

    test('sync с чужим типом account_data — бампов нет', () {
      expect(
        bumpsFor(
          SyncUpdate(
            nextBatch: 's3',
            accountData: [
              BasicEvent(type: 'com.liza.user_role', content: const {}),
            ],
          ),
        ),
        0,
      );
    });
  });
}
