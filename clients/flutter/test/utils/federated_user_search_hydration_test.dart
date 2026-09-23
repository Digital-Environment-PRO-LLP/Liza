// ledger:RL-search-handle-profile-hydration
//
// Страж хелпера гидратации профилей поиска (LABA-2552): находки по @-нику /
// MXID / телефону приходят голым Profile(userId) — хелпер догружает имя и
// аватар через РЕАЛЬНЫЙ SDK-клиент (кэш профилей в in-memory БД, FakeMatrixApi
// вместо сети), не меняя порядок и не трогая профили, у которых имя уже есть.
//
// Покрываемые AC (tests/registry/RL-search-handle-profile-hydration.md):
//   AC-3 длина/порядок/userId сохранены; профиль с именем не подменён;
//        гидратируются только пустые; индекс 0 стабилен.
//   AC-4 стадия 1 публикуется ДО завершения гидратации, стадия 2 — после;
//        параметры SDK (timeout 5с, maxCacheAge 10 мин) переданы.
//   AC-6 один из N недоступен (404 / запрещён) → остальные гидратированы,
//        исходный элемент сохранён, исключения наружу нет.
//
// Red-proof: убрать гейт `if (!_hasName(profile)) continue` в хелпере → тест
// «недоступный профиль остаётся исходным» краснеет (null-Profile затирает
// элемент — ровно баг stories_extension.dart:313-317).
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:liza/utils/federated_user_search_service.dart';

import 'test_client.dart';

const _sasha = '@user_f86a7e57:user.liza.ru';
const _sashaRoute = '/client/v3/profile/%40user_f86a7e57%3Auser.liza.ru';
const _phone = '@user_11112222:user.liza.ru';
const _phoneRoute = '/client/v3/profile/%40user_11112222%3Auser.liza.ru';
const _ghost = '@user_deadbeef:user.liza.ru';
const _forbidden = '@user_forbidden:user.liza.ru';
const _forbiddenRoute = '/client/v3/profile/%40user_forbidden%3Auser.liza.ru';

// Client оборачивает httpClient в FixedTimeoutHttpClient — фейк лежит в inner.
FakeMatrixApi _api(Client client) =>
    (client.httpClient as dynamic).inner as FakeMatrixApi;

/// Клиент с подменённым getProfileFromUserId: отдаёт профиль только после
/// [gate] и запоминает переданные параметры — чтобы проверить стадийность и
/// то, что хелпер действительно передаёт SDK короткие таймауты, а не дефолт.
class _ProbeClient extends Client {
  _ProbeClient(super.clientName, {required super.database})
      : super(httpClient: FakeMatrixApi());

  final gate = Completer<void>();
  Duration? seenTimeout;
  Duration? seenMaxCacheAge;

  @override
  Future<Profile> getProfileFromUserId(
    String userId, {
    @Deprecated('No longer supported') bool? getFromRooms,
    @Deprecated('No longer supported') bool? cache,
    Duration timeout = const Duration(seconds: 30),
    Duration maxCacheAge = const Duration(days: 1),
  }) async {
    seenTimeout = timeout;
    seenMaxCacheAge = maxCacheAge;
    await gate.future;
    return Profile(userId: userId, displayName: 'Саша');
  }
}

void main() {
  late Client client;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    _api(client).api['GET']![_sashaRoute] = (_) => {
          'displayname': 'Саша',
          'avatar_url': 'mxc://user.liza.ru/DwhWXyeYYcOGIkfKrRrjENnw',
        };
    _api(client).api['GET']![_phoneRoute] = (_) => {'displayname': 'Телефонный'};
    // Не M_NOT_FOUND → FakeMatrixApi отдаёт 405 → SDK бросает MatrixException.
    _api(client).api['GET']![_forbiddenRoute] =
        (_) => {'errcode': 'M_FORBIDDEN', 'error': 'federation denied'};
  });

  tearDown(() async {
    await client.dispose();
  });

  group('hydrateProfilesWithoutDisplayName', () {
    // AC:RL-search-handle-profile-hydration/3
    test('порядок, длина и userId сохранены; имя из directory не подменяется',
        () async {
      final directory = Profile(userId: '@ivan:prod', displayName: 'Иван');
      final input = [
        Profile(userId: _phone), // телефонный матч — индекс 0
        directory,
        Profile(userId: _sasha), // находка по нику
      ];

      final out = await hydrateProfilesWithoutDisplayName(client, input);

      expect(out.length, input.length);
      expect(
        out.map((p) => p.userId).toList(),
        input.map((p) => p.userId).toList(),
        reason: 'гидратация не переставляет и не теряет элементы',
      );
      expect(identical(out[1], directory), isTrue,
          reason: 'профиль с именем (directory) остаётся тем же объектом');
      expect(out[0].displayName, 'Телефонный');
      expect(out[2].displayName, 'Саша');
      expect(
        out[2].avatarUrl,
        Uri.parse('mxc://user.liza.ru/DwhWXyeYYcOGIkfKrRrjENnw'),
      );
      // Вход не мутирован — стадия 1 главного экрана уже показала его.
      expect(input[2].displayName, isNull);
    });

    // AC:RL-search-handle-profile-hydration/6
    test('недоступный профиль (404 / запрещён) остаётся исходным, остальные —'
        ' гидратированы, исключения наружу нет', () async {
      final ghost = Profile(userId: _ghost);
      final forbidden = Profile(userId: _forbidden);
      final input = [ghost, Profile(userId: _sasha), forbidden];

      final out = await hydrateProfilesWithoutDisplayName(client, input);

      expect(identical(out[0], ghost), isTrue,
          reason: '404 → исходный элемент, не Profile с null-полями');
      expect(identical(out[2], forbidden), isTrue,
          reason: 'запрет федерации → исходный элемент');
      expect(out[1].displayName, 'Саша');
    });

    // AC:RL-search-handle-profile-hydration/3
    test('без пустых профилей — сеть не нужна, список тот же', () async {
      var calls = 0;
      _api(client).api['GET']![_sashaRoute] = (_) {
        calls++;
        return {'displayname': 'Саша'};
      };
      final input = [Profile(userId: _sasha, displayName: 'Уже есть')];

      final out = await hydrateProfilesWithoutDisplayName(client, input);

      expect(calls, 0);
      expect(out.single.displayName, 'Уже есть');
    });

    // AC:RL-search-handle-profile-hydration/4
    test('стадия 1 видна до завершения гидратации, стадия 2 — после;'
        ' SDK получает короткие timeout/maxCacheAge', () async {
      final probe = _ProbeClient(
        'probe',
        database: await MatrixSdkDatabase.init(
          'probe',
          database: await databaseFactoryFfi.openDatabase(':memory:'),
          sqfliteFactory: databaseFactoryFfi,
        ),
      );
      addTearDown(probe.dispose);
      // Опубликованный стадией 1 список (как userSearchResult.results).
      final published = [Profile(userId: _sasha)];

      final pending = hydrateProfilesWithoutDisplayName(probe, published);
      await Future<void>.delayed(Duration.zero);

      expect(published.single.displayName, isNull,
          reason: 'пока профиль не пришёл, показан фоллбэк стадии 1');
      expect(probe.seenTimeout, const Duration(seconds: 5));
      expect(probe.seenMaxCacheAge, const Duration(minutes: 10));

      probe.gate.complete();
      final hydrated = await pending;
      expect(applyHydratedProfiles(published, hydrated), isTrue);
      expect(published.single.displayName, 'Саша');
    });
  });

  group('applyHydratedProfiles', () {
    // AC:RL-search-handle-profile-hydration/4
    test('подменяет по индексу только при совпадении userId, без пересборки',
        () {
      final target = [
        Profile(userId: '@a:s'),
        Profile(userId: '@b:s', displayName: 'Б'),
        Profile(userId: '@c:s'),
      ];
      final same = target[1];
      final hydrated = [
        Profile(userId: '@a:s', displayName: 'А'),
        same,
        // Список успели пересобрать под другой запрос — на этом индексе
        // другой человек, подменять нельзя.
        Profile(userId: '@zzz:s', displayName: 'Чужой'),
      ];

      expect(applyHydratedProfiles(target, hydrated), isTrue);
      expect(target[0].displayName, 'А');
      expect(identical(target[1], same), isTrue);
      expect(target[2].userId, '@c:s');
      expect(target[2].displayName, isNull);
    });

    test('ничего не изменилось → false (setState не нужен)', () {
      final target = [Profile(userId: '@a:s', displayName: 'А')];
      expect(applyHydratedProfiles(target, List.of(target)), isFalse);
      expect(applyHydratedProfiles(target, const []), isFalse);
    });
  });
}
