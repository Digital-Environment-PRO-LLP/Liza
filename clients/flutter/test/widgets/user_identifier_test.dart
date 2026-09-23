import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/user_handle_service.dart';
import 'package:liza/widgets/user_identifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Любой сетевой вызов внутри userIdentifier() — регрессия прецедента
  // stories_extension.dart:314-317 (142 сетевых провала за сессию из
  // build()). MockClient падает, если к нему обратились хоть раз.
  UserHandleService buildService() => UserHandleService(
    baseUrl: 'https://auth.test',
    accessTokenProvider: () => 'token',
    serverNameProvider: () => 'bots.liza.ru',
    httpClient: MockClient((request) async {
      fail('userIdentifier() не должна ходить в сеть: $request');
    }),
  );

  const mxid = '@ivan:bots.liza.ru';

  test('[AC:RL-user-handles/1] ник вытесняет MXID, когда он есть в кэше', () {
    final handles = buildService();
    handles.rememberHandle(mxid, 'ivan');

    expect(userIdentifier(mxid, handles: handles), '@ivan');
  });

  test('[AC:RL-user-handles/2] MXID остаётся, когда ника нет ни в кэше, ни передан явно', () {
    final handles = buildService();

    expect(userIdentifier(mxid, handles: handles), mxid);
  });

  test('MXID остаётся, когда профиль/кэш не загрузился (пустой сервис)', () {
    final handles = buildService();

    expect(
      userIdentifier('@unknown:bots.liza.ru', handles: handles),
      '@unknown:bots.liza.ru',
    );
  });

  test('явно переданный ник побеждает кэш', () {
    final handles = buildService();
    handles.rememberHandle(mxid, 'stale');

    expect(userIdentifier(mxid, handles: handles, handle: 'fresh'), '@fresh');
  });

  test('[AC:RL-user-handles/3] функция синхронна и не делает сетевых запросов', () {
    // MockClient в buildService() падает на любой реальный HTTP-вызов —
    // сам факт того, что вызов ниже завершается без await и без исключения,
    // и есть проверка синхронности/отсутствия сети.
    final handles = buildService();
    final result = userIdentifier(mxid, handles: handles);
    expect(result, isA<String>());
  });

  test(
    'MockClient гарантированно ловит сетевой вызов, если бы он был',
    () async {
      final client = MockClient((request) async {
        throw StateError('unexpected network call');
      });
      expect(
        () => client.get(Uri.parse('https://auth.test/x')),
        throwsA(anything),
      );
    },
  );

  // ledger:RL-search-handle-profile-hydration
  // Заголовок карточки поиска: имя → @ник → localpart. Localpart (технический
  // user_<hex8>) — только когда неизвестны ни имя, ни ник (LABA-2552).
  group('searchResultLabel', () {
    const sasha = '@user_f86a7e57:user.liza.ru';

    // AC:RL-search-handle-profile-hydration/2
    test('имя из профиля побеждает ник и localpart', () {
      final handles = buildService();
      handles.rememberHandle(sasha, 'alexxandrines');
      final label = searchResultLabel(
        Profile(userId: sasha, displayName: 'Саша'),
        handles: handles,
        unknown: 'Пользователь',
      );
      expect(label.title, 'Саша');
      expect(label.avatarName, 'Саша');
    });

    // AC:RL-search-handle-profile-hydration/2
    test('без имени, но с ником в кэше — @ник, буква аватара без сигила', () {
      final handles = buildService();
      handles.rememberHandle(sasha, 'alexxandrines');
      final label = searchResultLabel(
        Profile(userId: sasha),
        handles: handles,
        unknown: 'Пользователь',
      );
      expect(label.title, '@alexxandrines');
      expect(label.avatarName, 'alexxandrines',
          reason: 'иначе буквой аватара стал бы «@»');
      expect(label.title, isNot(contains('user_f86a7e57')));
    });

    // AC:RL-search-handle-profile-hydration/2
    test('ни имени, ни ника — короткий localpart, а не полный MXID', () {
      final handles = buildService();
      final label = searchResultLabel(
        Profile(userId: sasha),
        handles: handles,
        unknown: 'Пользователь',
      );
      // Red-proof против `displayName ?? userIdentifier(...) ?? localpart`:
      // userIdentifier non-null и отдал бы '@user_f86a7e57:user.liza.ru'.
      expect(label.title, 'user_f86a7e57');
      expect(label.avatarName, 'user_f86a7e57');
    });

    test('пустая строка имени считается отсутствующим именем', () {
      final handles = buildService();
      handles.rememberHandle(sasha, 'alexxandrines');
      final label = searchResultLabel(
        Profile(userId: sasha, displayName: ''),
        handles: handles,
        unknown: 'Пользователь',
      );
      expect(label.title, '@alexxandrines');
    });

    test('функция синхронна и не делает сетевых запросов', () {
      final handles = buildService();
      final label = searchResultLabel(
        Profile(userId: sasha),
        handles: handles,
        unknown: 'Пользователь',
      );
      expect(label.title, isA<String>());
    });
  });
}
