import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:liza/utils/user_handle_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  UserHandleService build(
    http.Client client, {
    String accessToken = 'token',
    String serverName = 'bots.liza.ru',
  }) =>
      UserHandleService(
        httpClient: client,
        // ХОСТ без схемы — ровно то, что отдаёт AppConfig.authProxyBaseUrl.
        // Раньше здесь стоял полный URL 'https://auth.test', и тесты
        // проходили на данных, которых в проде не бывает: реальный вызов
        // строил относительный адрес и уходил на origin страницы.
        baseUrl: 'auth.test',
        accessTokenProvider: () => accessToken,
        serverNameProvider: () => serverName,
      );

  // Полноценный Matrix Client нужен только затем, чтобы setHandle мог
  // позвать publishHandle (setProfileField бьёт по нему живым HTTP-запросом
  // внутри SDK) — без сети наружу, через MockClient. userId по умолчанию
  // без него publishHandle/rememberHandle внутри setHandle тихо
  // не сработают (см. проверку в user_handle_service.dart).
  Future<Client> buildMatrixClient({
    String userId = '@user_a1:bots.liza.ru',
    http.Client? httpClient,
  }) async {
    final client = Client(
      'Liza Test',
      httpClient: httpClient ??
          MockClient((req) async => http.Response('{}', 200)),
      database: await MatrixSdkDatabase.init(
        'user_handle_service_test_${DateTime.now().microsecondsSinceEpoch}',
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    client.homeserver = Uri.parse('https://fakeserver.notexisting');
    client.accessToken = 'test_token';
    client.setUserId(userId);
    return client;
  }

  test('resolve возвращает MXID и кэширует его', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      expect(req.url.path, '/api/handles/ivanov');
      return http.Response(jsonEncode({'mxid': '@user_a1:bots.liza.ru'}), 200);
    });
    final service = build(client);

    final mxid = await service.resolve('ivanov');

    expect(mxid, '@user_a1:bots.liza.ru');
    expect(calls, 1);
    service.dispose();
  });

  test('повторный resolve не делает второго запроса', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response(jsonEncode({'mxid': '@user_a1:bots.liza.ru'}), 200);
    });
    final service = build(client);

    await service.resolve('ivanov');
    await service.resolve('ivanov');

    expect(calls, 1);
    service.dispose();
  });

  test('resolve неизвестного ника возвращает null, а не бросает', () async {
    final client = MockClient((req) async => http.Response(
          jsonEncode({'error': 'not_found'}),
          404,
        ));
    final service = build(client);

    final mxid = await service.resolve('unknown');

    expect(mxid, isNull);
    service.dispose();
  });

  test('resolve при сетевой ошибке возвращает null, а не бросает', () async {
    final client = MockClient((req) async => throw Exception('boom'));
    final service = build(client);

    final mxid = await service.resolve('ivanov');

    expect(mxid, isNull);
    service.dispose();
  });

  test('cachedHandleFor не делает сетевых запросов', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response(jsonEncode({'mxid': '@user_a1:bots.liza.ru'}), 200);
    });
    final service = build(client);

    // До заполнения кэша.
    expect(service.cachedHandleFor('@user_a1:bots.liza.ru'), isNull);
    expect(calls, 0);

    // После resolve кэш заполняется, но cachedHandleFor не задевает сеть.
    await service.resolve('ivanov');
    expect(calls, 1);
    expect(service.cachedHandleFor('@user_a1:bots.liza.ru'), 'ivanov');
    expect(calls, 1);

    // После rememberHandle тоже без сети.
    service.rememberHandle('@user_b2:bots.liza.ru', 'petrov');
    expect(service.cachedHandleFor('@user_b2:bots.liza.ru'), 'petrov');
    expect(calls, 1);

    service.dispose();
  });

  test('смена ника оставляет ровно одну запись на mxid', () async {
    final client = MockClient((req) async => http.Response('', 500));
    final service = build(client);

    service.rememberHandle('@user_a1:bots.liza.ru', 'ivanov');
    service.rememberHandle('@user_a1:bots.liza.ru', 'petrov');

    // Обратный индекс не задваивается: старый ник больше не резолвится
    // на этот mxid ни прямым, ни обратным путём.
    expect(service.cachedHandleFor('@user_a1:bots.liza.ru'), 'petrov');
    expect(await service.resolve('ivanov'), isNot('@user_a1:bots.liza.ru'));

    service.dispose();
  });

  test('rememberHandle с новым ником — cachedHandleFor отдаёт новый, не старый', () async {
    final client = MockClient((req) async => http.Response('', 500));
    final service = build(client);

    service.rememberHandle('@user_a1:bots.liza.ru', 'ivanov');
    service.rememberHandle('@user_a1:bots.liza.ru', 'petrov');

    expect(service.cachedHandleFor('@user_a1:bots.liza.ru'), 'petrov');

    service.dispose();
  });

  test(
      'rememberHandle переживает перезапуск: чужой ник не пропадает после '
      'дебаунса', () {
    // Без чужих ников кэш B5 после каждого старта деградирует до MXID
    // везде — резолвом их не восстановить (запрещён в отрисовке списков,
    // прецедент stories_extension.dart:314-317).
    fakeAsync((async) {
      final client = MockClient((req) async => http.Response('', 500));
      final service = build(client);

      service.rememberHandle('@user_a1:bots.liza.ru', 'ivanov');
      async.elapse(const Duration(seconds: 2));

      final raw = SharedPreferences.getInstance();
      // getInstance() с мок-хранилищем резолвится через микрозадачи —
      // без прогона очереди Future не завершится в fakeAsync.
      async.flushMicrotasks();
      raw.then((prefs) {
        final stored = prefs.getString('user_handle_cache_v1');
        expect(stored, isNotNull);
        expect(jsonDecode(stored!), contains('ivanov'));
      });
      async.flushMicrotasks();

      service.dispose();
    });
  });

  test(
      'rememberHandle не пишет на диск на каждый вызов — только после '
      'паузы (дебаунс)', () {
    fakeAsync((async) {
      final client = MockClient((req) async => http.Response('', 500));
      final service = build(client);

      // Пачка вызовов подряд (обход списка участников) не должна успеть
      // сбросить кэш на диск раньше паузы — иначе это та самая тяжёлая
      // сериализация на каждый элемент, которой дебаунс избегает.
      for (var i = 0; i < 50; i++) {
        service.rememberHandle('@user_$i:bots.liza.ru', 'handle_$i');
        async.elapse(const Duration(milliseconds: 10));
      }
      async.flushMicrotasks();

      SharedPreferences.getInstance().then((prefs) {
        expect(prefs.getString('user_handle_cache_v1'), isNull);
      });
      async.flushMicrotasks();

      async.elapse(const Duration(seconds: 2));
      async.flushMicrotasks();

      SharedPreferences.getInstance().then((prefs) {
        final stored = prefs.getString('user_handle_cache_v1');
        expect(stored, isNotNull);
        expect(jsonDecode(stored!), contains('handle_49'));
      });
      async.flushMicrotasks();

      service.dispose();
    });
  });

  test(
      'dispose() досбрасывает несохранённый ник, а не теряет его вместе с '
      'таймером', () {
    // Сценарий: сохранил ник и сразу закрыл экран настроек, не дождавшись
    // дебаунс-паузы — простая отмена таймера потеряла бы запись.
    fakeAsync((async) {
      final client = MockClient((req) async => http.Response('', 500));
      final service = build(client);

      service.rememberHandle('@user_a1:bots.liza.ru', 'ivanov');
      // Дебаунс ещё не выстрелил (< 1с) — таймер активен на момент dispose.
      async.elapse(const Duration(milliseconds: 100));
      service.dispose();
      async.flushMicrotasks();

      SharedPreferences.getInstance().then((prefs) {
        final stored = prefs.getString('user_handle_cache_v1');
        expect(stored, isNotNull);
        expect(jsonDecode(stored!), contains('ivanov'));
      });
      async.flushMicrotasks();
    });
  });

  test('setHandle различает taken / invalid / disabled по коду ответа', () async {
    Future<HandleSetResult> resultFor(int code, {String? error}) async {
      final client = MockClient((req) async {
        expect(req.method, 'PUT');
        return http.Response(
          jsonEncode({if (error != null) 'error': error, 'handle': 'ivanov'}),
          code,
        );
      });
      final service = build(client);
      final r = await service.setHandle(
        'ivanov',
        client: await buildMatrixClient(),
      );
      service.dispose();
      return r;
    }

    expect(await resultFor(200), HandleSetResult.ok);
    expect(await resultFor(409, error: 'handle_taken'), HandleSetResult.taken);
    expect(await resultFor(400, error: 'invalid_handle'), HandleSetResult.invalid);
    expect(await resultFor(403, error: 'handles_disabled'), HandleSetResult.disabled);
  });

  test(
      'setHandle с client кладёт свой ник в кэш сразу, не дожидаясь resolve',
      () async {
    final authProxyClient = MockClient((req) async {
      // Первый запрос — PUT на auth-proxy; второй (если будет) — publishHandle
      // в Matrix-профиль, здесь не важен.
      return http.Response(jsonEncode({'handle': 'ivanov'}), 200);
    });
    final service = build(authProxyClient);
    final matrixClient = await buildMatrixClient();

    final result = await service.setHandle('ivanov', client: matrixClient);

    expect(result, HandleSetResult.ok);
    expect(service.cachedHandleFor('@user_a1:bots.liza.ru'), 'ivanov');

    service.dispose();
  });

  test('setHandle при сетевой ошибке отдаёт networkError', () async {
    final client = MockClient((req) async => throw Exception('boom'));
    final service = build(client);

    final result = await service.setHandle(
      'ivanov',
      client: await buildMatrixClient(),
    );

    expect(result, HandleSetResult.networkError);
    service.dispose();
  });

  test('fetchOwn при недоступном auth-proxy отдаёт available: false', () async {
    final client = MockClient((req) async => throw Exception('boom'));
    final service = build(client);

    final state = await service.fetchOwn();

    expect(state.available, isFalse);
    expect(state.handle, isNull);
    service.dispose();
  });

  test('PUT шлёт server_name — без него сервер отвечает 400 unknown_server',
      () async {
    // Выстрадано: тело PUT содержало только {handle}. Сервер не мог найти
    // хоумсервер, отвечал 400 unknown_server, а клиент трактовал ЛЮБОЙ 400
    // как «неверный формат» — человек видел «должен начинаться с буквы»
    // на совершенно правильном нике.
    Map<String, dynamic>? sentBody;
    final service = UserHandleService(
      baseUrl: 'auth.test',
      accessTokenProvider: () => 'token',
      serverNameProvider: () => 'bots.liza.ru',
      httpClient: MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"handle": "ivanov"}', 200);
      }),
    );
    addTearDown(service.dispose);

    await service.setHandle('ivanov', client: await buildMatrixClient());

    expect(sentBody, isNotNull);
    expect(sentBody!['handle'], 'ivanov');
    expect(
      sentBody!['server_name'],
      'bots.liza.ru',
      reason: 'без server_name сервер не опознает хоумсервер',
    );
  });

  test('400 unknown_server НЕ выдаётся за неверный формат ника', () async {
    final service = UserHandleService(
      baseUrl: 'auth.test',
      accessTokenProvider: () => 'token',
      serverNameProvider: () => 'bots.liza.ru',
      httpClient: MockClient((request) async => http.Response(
            '{"error": "unknown_server", "message": "Неизвестный сервер"}',
            400,
          )),
    );
    addTearDown(service.dispose);

    final result =
        await service.setHandle('ivanov', client: await buildMatrixClient());

    expect(
      result,
      isNot(HandleSetResult.invalid),
      reason: 'ник корректен — винить формат нельзя',
    );
  });

  test('400 invalid_handle остаётся ошибкой формата', () async {
    final service = UserHandleService(
      baseUrl: 'auth.test',
      accessTokenProvider: () => 'token',
      serverNameProvider: () => 'bots.liza.ru',
      httpClient: MockClient((request) async => http.Response(
            '{"error": "invalid_handle", "message": "..."}',
            400,
          )),
    );
    addTearDown(service.dispose);

    final result =
        await service.setHandle('1bad', client: await buildMatrixClient());

    expect(result, HandleSetResult.invalid);
  });

  test('URL абсолютный: хост без схемы не даёт относительный адрес', () async {
    // Страж против регрессии: AppConfig.authProxyBaseUrl — ГОЛЫЙ ХОСТ.
    // Если собирать URL как Uri.parse('$baseUrl/...'), выйдет относительный
    // адрес, и на вебе запрос уйдёт на origin страницы (dev.web.liza.ru)
    // вместо auth-proxy. Внешне это выглядит как «фича молча не работает».
    Uri? seen;
    final service = UserHandleService(
      baseUrl: 'auth.test',
      accessTokenProvider: () => 'token',
      serverNameProvider: () => 'bots.liza.ru',
      httpClient: MockClient((request) async {
        seen = request.url;
        return http.Response('{"handle": null, "available": true}', 200);
      }),
    );
    addTearDown(service.dispose);

    await service.fetchOwn();

    expect(seen, isNotNull);
    expect(seen!.isAbsolute, isTrue, reason: 'адрес обязан быть абсолютным');
    expect(seen!.scheme, 'https');
    expect(seen!.host, 'auth.test');
    expect(seen!.path, '/api/account/handle');
  });

  test('fetchOwn возвращает handle и available из ответа', () async {
    final client = MockClient((req) async {
      expect(req.method, 'GET');
      expect(req.url.queryParameters['server_name'], 'bots.liza.ru');
      return http.Response(
        jsonEncode({'handle': 'ivanov', 'available': true}),
        200,
      );
    });
    final service = build(client);

    final state = await service.fetchOwn();

    expect(state.handle, 'ivanov');
    expect(state.available, isTrue);
    service.dispose();
  });

  test('истёкший кэш перезапрашивается', () async {
    var calls = 0;
    final client = MockClient((req) async {
      calls++;
      return http.Response(jsonEncode({'mxid': '@user_a1:bots.liza.ru'}), 200);
    });
    final service = build(client);

    await service.resolve('ivanov');
    expect(calls, 1);

    // Насильно состариваем запись в SharedPreferences-кэше за пределы TTL (1ч).
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user_handle_cache_v1')!;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    final entry = map['ivanov'] as Map<String, dynamic>;
    final staleAt = DateTime.now()
        .subtract(const Duration(hours: 2))
        .millisecondsSinceEpoch;
    entry['fetchedAt'] = staleAt;
    await prefs.setString('user_handle_cache_v1', jsonEncode(map));

    // Новый инстанс сервиса, чтобы прочитать кэш заново с диска.
    final service2 = build(client);
    await service2.resolve('ivanov');

    expect(calls, 2);
    service.dispose();
    service2.dispose();
  });

  // ------------------------------------------------------------------
  // Поиск по префиксу ника. ledger:RL-user-handles
  // ------------------------------------------------------------------

  // AC:RL-user-handles/27
  test('searchHandles возвращает найденных и шлёт префикс без сигила',
      () async {
    Uri? seen;
    final service = build(
      MockClient((req) async {
        seen = req.url;
        return http.Response(
          jsonEncode({
            'results': [
              {'handle': 'ivanov', 'mxid': '@ivan:bots.liza.ru'},
              {'handle': 'ivanova', 'mxid': '@anna:bots.liza.ru'},
            ],
          }),
          200,
        );
      }),
    );

    // '@' и верхний регистр — ровно то, что человек копирует из профиля.
    final found = await service.searchHandles('@IVAN');

    expect(found.map((m) => m.handle), ['ivanov', 'ivanova']);
    expect(found.map((m) => m.mxid),
        ['@ivan:bots.liza.ru', '@anna:bots.liza.ru']);
    expect(seen!.path, '/api/handles/search');
    expect(seen!.queryParameters['q'], 'ivan');
    expect(seen!.queryParameters['server_name'], 'bots.liza.ru');
  });

  // AC:RL-user-handles/30
  test('searchHandles шлёт Bearer — эндпоинт под токеном', () async {
    String? auth;
    final service = build(
      MockClient((req) async {
        auth = req.headers['Authorization'];
        return http.Response(jsonEncode({'results': []}), 200);
      }),
      accessToken: 'sekret',
    );

    await service.searchHandles('ivan');

    expect(auth, 'Bearer sekret');
  });

  // AC:RL-user-handles/31
  test('searchHandles наполняет кэш — cachedHandleFor знает найденных',
      () async {
    final service = build(
      MockClient(
        (req) async => http.Response(
          jsonEncode({
            'results': [
              {'handle': 'ivanov', 'mxid': '@ivan:bots.liza.ru'},
            ],
          }),
          200,
        ),
      ),
    );

    await service.searchHandles('ivan');

    // Без наполнения кэша список результатов показал бы MXID у человека,
    // ник которого мы только что узнали (cachedHandleFor в сеть не ходит).
    expect(service.cachedHandleFor('@ivan:bots.liza.ru'), 'ivanov');
  });

  // AC:RL-user-handles/29
  test('слишком короткий запрос не идёт в сеть вовсе', () async {
    var calls = 0;
    final service = build(
      MockClient((req) async {
        calls++;
        return http.Response(jsonEncode({'results': []}), 200);
      }),
    );

    expect(await service.searchHandles('i'), isEmpty);
    // '@i' после снятия сигила — тот же один символ.
    expect(await service.searchHandles('@i'), isEmpty);
    expect(calls, 0, reason: 'сервер всё равно ответит 400 query_too_short');
  });

  test('searchHandles при ошибке сервера отдаёт пустой список, а не бросает',
      () async {
    final service = build(
      MockClient((req) async => http.Response('{"error":"boom"}', 500)),
    );

    expect(await service.searchHandles('ivan'), isEmpty);
  });

  test('searchHandles при сетевой ошибке отдаёт пустой список, а не бросает',
      () async {
    final service = build(
      MockClient((req) async => throw Exception('network down')),
    );

    expect(await service.searchHandles('ivan'), isEmpty);
  });

  // AC:RL-user-handles/32
  test('битые записи в ответе пропускаются, целые остаются', () async {
    final service = build(
      MockClient(
        (req) async => http.Response(
          jsonEncode({
            'results': [
              {'handle': 'ivanov'},
              {'mxid': '@anna:bots.liza.ru'},
              'not-an-object',
              {'handle': 'ivanova', 'mxid': '@anna:bots.liza.ru'},
            ],
          }),
          200,
        ),
      ),
    );

    final found = await service.searchHandles('ivan');

    expect(found.map((m) => m.handle), ['ivanova']);
  });

  // AC:RL-user-handles/32
  test('ответ без поля results не роняет поиск', () async {
    final service = build(
      MockClient((req) async => http.Response('{}', 200)),
    );

    expect(await service.searchHandles('ivan'), isEmpty);
  });

}
