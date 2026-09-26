// ledger:RL-web-update-reload
// AC:RL-web-update-reload/1 AC:RL-web-update-reload/2 AC:RL-web-update-reload/3
// AC:RL-web-update-reload/4 AC:RL-web-update-reload/5
import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:liza/utils/web_update_checker.dart';

void main() {
  final versionUri = Uri.parse('https://web.liza.ru/version.json');

  late List<Uri> requests;
  late http.Response Function() respond;

  http.Client client() => MockClient((request) async {
    requests.add(request.url);
    return respond();
  });

  http.Response deployId(String id) =>
      http.Response(jsonEncode({'build_number': '3768', 'deploy_id': id}), 200);

  WebUpdateChecker checker({
    String current = 'abc-1',
    bool isWeb = true,
    DateTime Function()? now,
  }) => WebUpdateChecker(
    httpClient: client(),
    currentDeployId: current,
    isWeb: isWeb,
    versionUri: versionUri,
    now: now,
  );

  setUp(() {
    requests = [];
    respond = () => deployId('abc-1');
  });

  group('AC-1: сравнение идентификатора деплоя', () {
    test('на сервере другой деплой → обновление доступно', () async {
      respond = () => deployId('def-2');
      final c = checker();
      await c.check(force: true);
      expect(c.updateAvailable.value, isTrue);
    });

    test('тот же деплой → баннера нет', () async {
      final c = checker();
      await c.check(force: true);
      expect(c.updateAvailable.value, isFalse);
    });

    test(
      'откат (сервер на более старом деплое) → тоже предлагаем reload',
      () async {
        respond = () => deployId('old-0');
        final c = checker(current: 'new-9');
        await c.check(force: true);
        expect(c.updateAvailable.value, isTrue);
      },
    );

    test('одинаковый build_number, но разный deploy_id → доступно', () async {
      // Сценарий заявки №42: web выкатили между сторовыми bump'ами.
      respond = () => deployId('abc-2');
      final c = checker(current: 'abc-1');
      await c.check(force: true);
      expect(c.updateAvailable.value, isTrue);
    });
  });

  test('AC-2: same-origin version.json с уникальным cachebuster', () async {
    var t = DateTime(2026, 9, 25, 10);
    final c = checker(now: () => t);
    await c.check(force: true);
    t = t.add(const Duration(minutes: 31));
    await c.check(force: true);

    expect(requests, hasLength(2));
    for (final uri in requests) {
      expect(uri.replace(query: ''), versionUri.replace(query: ''));
      expect(uri.queryParameters['cachebuster'], isNotEmpty);
    }
    expect(
      requests[0].queryParameters['cachebuster'],
      isNot(requests[1].queryParameters['cachebuster']),
    );
  });

  group('AC-3: сбой → баннера нет', () {
    final cases = <String, http.Response Function()>{
      'не 200': () => http.Response('nope', 404),
      'битый JSON': () => http.Response('{oops', 200),
      'нет поля deploy_id': () =>
          http.Response(jsonEncode({'build_number': '3769'}), 200),
      'пустой deploy_id': () => deployId(''),
      'не объект': () => http.Response('[]', 200),
    };
    cases.forEach((name, response) {
      test(name, () async {
        respond = response;
        final c = checker();
        await c.check(force: true);
        expect(c.updateAvailable.value, isFalse);
      });
    });

    test('исключение сети', () async {
      final c = WebUpdateChecker(
        httpClient: MockClient((_) async => throw http.ClientException('x')),
        currentDeployId: 'abc-1',
        isWeb: true,
        versionUri: versionUri,
      );
      await c.check(force: true);
      expect(c.updateAvailable.value, isFalse);
    });
  });

  group('AC-4: выключено вне Web и без своего id', () {
    test('isWeb: false → ни одного запроса', () async {
      respond = () => deployId('def-2');
      final c = checker(isWeb: false);
      c.start();
      await c.check(force: true);
      await c.onResumed();
      expect(requests, isEmpty);
      expect(c.updateAvailable.value, isFalse);
      c.dispose();
    });

    test(
      'пустой WEB_DEPLOY_ID (локальная сборка) → ни одного запроса',
      () async {
        respond = () => deployId('def-2');
        final c = checker(current: '');
        c.start();
        await c.check(force: true);
        expect(requests, isEmpty);
        c.dispose();
      },
    );
  });

  group('AC-5: расписание проверок', () {
    test('старт сразу + опрос каждые 30 мин; dispose гасит таймер', () {
      fakeAsync((async) {
        final c = checker(now: () => async.getClock(DateTime(2026)).now());
        c.start();
        async.flushMicrotasks();
        expect(requests, hasLength(1));

        async.elapse(const Duration(minutes: 29));
        expect(requests, hasLength(1));
        async.elapse(const Duration(minutes: 1));
        expect(requests, hasLength(2));
        async.elapse(const Duration(minutes: 60));
        expect(requests, hasLength(4));

        c.dispose();
        async.elapse(const Duration(hours: 2));
        expect(requests, hasLength(4));
      });
    });

    test('resumed не чаще раза в 15 минут', () {
      fakeAsync((async) {
        final c = checker(now: () => async.getClock(DateTime(2026)).now());
        unawaited(c.onResumed());
        async.flushMicrotasks();
        unawaited(c.onResumed());
        async.elapse(const Duration(minutes: 14));
        unawaited(c.onResumed());
        async.flushMicrotasks();
        expect(requests, hasLength(1));

        async.elapse(const Duration(minutes: 1));
        unawaited(c.onResumed());
        async.flushMicrotasks();
        expect(requests, hasLength(2));
      });
    });

    test('повторный start не заводит второй таймер', () {
      fakeAsync((async) {
        final c = checker(now: () => async.getClock(DateTime(2026)).now());
        c.start();
        c.start();
        async.elapse(const Duration(minutes: 30));
        expect(requests, hasLength(2));
        c.dispose();
      });
    });

    test('после обнаружения обновления опрос прекращается', () {
      fakeAsync((async) {
        respond = () => deployId('def-2');
        final c = checker(now: () => async.getClock(DateTime(2026)).now());
        c.start();
        async.flushMicrotasks();
        expect(c.updateAvailable.value, isTrue);
        async.elapse(const Duration(hours: 2));
        expect(requests, hasLength(1));
        c.dispose();
      });
    });
  });

  test('dispose во время запроса version.json — без записи в уничтоженный '
      'notifier', () async {
    final gate = Completer<http.Response>();
    final c = WebUpdateChecker(
      httpClient: MockClient((_) => gate.future),
      currentDeployId: 'abc-1',
      isWeb: true,
      versionUri: versionUri,
    );
    final pending = c.check(force: true);
    c.dispose();
    gate.complete(deployId('def-2'));
    await expectLater(pending, completes);
  });
}
