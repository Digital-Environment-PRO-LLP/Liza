import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:liza/utils/version_gate_service.dart';

void main() {
  VersionGateService build(http.Client client, {required int currentBuild, String? platformKey}) =>
      VersionGateService(
        httpClient: client,
        baseUrl: 'https://vg.test',
        platformKeyOverride: platformKey,
        currentBuildOverride: currentBuild,
      );

  group('detectWebPlatformKey', () {
    test('Android Chrome', () {
      expect(
        detectWebPlatformKey(
          'Mozilla/5.0 (Linux; Android 14; SM-S921B) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
        ),
        'android',
      );
    });

    test('iPhone Safari', () {
      expect(
        detectWebPlatformKey(
          'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
          'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile Safari/604.1',
        ),
        'ios',
      );
    });

    test('iPad распознаётся как ios, а не macos', () {
      expect(
        detectWebPlatformKey(
          'Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X) AppleWebKit/605.1.15 '
          '(KHTML, like Gecko) Version/17.0 Mobile Safari/604.1',
        ),
        'ios',
      );
    });

    test('macOS Safari', () {
      expect(
        detectWebPlatformKey(
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
          '(KHTML, like Gecko) Version/17.0 Safari/605.1.15',
        ),
        'macos',
      );
    });

    test('Windows', () {
      expect(
        detectWebPlatformKey(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/120.0 Safari/537.36',
        ),
        'windows',
      );
    });

    test('нераспознанная ОС — null, плашки не будет', () {
      expect(detectWebPlatformKey('Mozilla/5.0 (X11; Linux x86_64)'), isNull);
    });
  });

  group('check() install_url', () {
    // kIsWeb — константа компиляции, в тестах её не подменить. Проверяем
    // прокидывание install_url через обычный platformKeyOverride — веб-режим
    // отличается только источником platform (см. _resolvePlatformKey),
    // разбор ответа и install_url общий для всех платформ.
    test('install_url сохраняется, даже когда обновление не нужно', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'platform': 'android',
              'build': 100,
              'version': '2.5.0',
              'install_url': 'https://install.example/android',
            }),
            200,
          ));
      final result =
          await build(client, currentBuild: 3643, platformKey: 'android').check();
      expect(result.needsUpdate, isFalse);
      expect(result.installUrl, 'https://install.example/android');
    });

    test('install_url возвращается и без поля build в ответе', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'platform': 'android',
              'install_url': 'https://install.example/android',
            }),
            200,
          ));
      final result =
          await build(client, currentBuild: 3643, platformKey: 'android').check();
      expect(result.needsUpdate, isFalse);
      expect(result.installUrl, 'https://install.example/android');
    });
  });

  group('fetchRequestAccessUrl', () {
    test('возвращает ссылку из ответа сервера', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({'request_access_url': 'https://forms.example/x'}),
            200,
          ));
      final url = await build(client, currentBuild: 1).fetchRequestAccessUrl();
      expect(url, 'https://forms.example/x');
    });

    test('null в ответе — null, кнопку не показываем', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({'request_access_url': null}),
            200,
          ));
      final url = await build(client, currentBuild: 1).fetchRequestAccessUrl();
      expect(url, isNull);
    });

    test('пустая строка трактуется как «ссылки нет»', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({'request_access_url': ''}),
            200,
          ));
      final url = await build(client, currentBuild: 1).fetchRequestAccessUrl();
      expect(url, isNull);
    });

    test('не-200 — null, наружу ничего не летит', () async {
      final client = MockClient((req) async => http.Response('err', 500));
      final url = await build(client, currentBuild: 1).fetchRequestAccessUrl();
      expect(url, isNull);
    });

    test('сетевая ошибка — null, наружу ничего не летит', () async {
      final client = MockClient((req) async => throw Exception('boom'));
      final url = await build(client, currentBuild: 1).fetchRequestAccessUrl();
      expect(url, isNull);
    });
  });

  // Тесты идут через РЕАЛЬНЫЙ резолв платформы (platformKeyOverride не
  // передаём — иначе сработает ранний return). Хост тестов — macOS, поэтому
  // платформа здесь bundle-keyed.
  group('bundle в запросе к version-gate', () {
    VersionGateService serviceFor({
      required http.Client client,
      required int currentBuild,
      String? packageName,
    }) =>
        VersionGateService(
          httpClient: client,
          baseUrl: 'https://vg.test',
          currentBuildOverride: currentBuild,
          packageNameOverride: packageName,
        );

    MockClient recorder(List<Uri> log, {int build = 3728}) =>
        MockClient((req) async {
          log.add(req.url);
          return http.Response(
            jsonEncode({
              'platform': 'macos',
              'build': build,
              'version': '2.4.0',
              'update_url': 'itms-beta://',
            }),
            200,
          );
        });

    test('bundle уходит query-параметром, путь платформы не меняется',
        () async {
      final requested = <Uri>[];
      await serviceFor(
        client: recorder(requested),
        currentBuild: 3728,
        packageName: 'ru.prodamus.liza',
      ).check();

      expect(requested.single.path, '/version/macos');
      expect(requested.single.queryParameters['bundle'], 'ru.prodamus.liza');
    });

    test('старое приложение шлёт свой bundle', () async {
      final requested = <Uri>[];
      await serviceFor(
        client: recorder(requested),
        currentBuild: 3728,
        packageName: 'com.prodamus.laba.liza',
      ).check();

      expect(
        requested.single.queryParameters['bundle'],
        'com.prodamus.laba.liza',
      );
    });

    test('bundle не определился — параметр не шлём вовсе', () async {
      final requested = <Uri>[];
      await serviceFor(
        client: recorder(requested),
        currentBuild: 3728,
        packageName: null,
      ).check();

      // Именно отсутствие ключа, а не пустая строка: сервер на Apple ответит
      // 404 «bundle required», и плашки не будет — это ожидаемо.
      expect(requested.single.queryParameters.containsKey('bundle'), isFalse);
      expect(requested.single.toString(), 'https://vg.test/version/macos');
    });

    test('404 от сервера — плашки нет, наружу ничего не летит', () async {
      // Так выглядит запрос старой Лизы после перехода на bundle-ключи.
      final client = MockClient(
        (req) async => http.Response(
          jsonEncode({'detail': 'bundle required'}),
          404,
        ),
      );
      final result = await serviceFor(
        client: client,
        currentBuild: 3728,
        packageName: null,
      ).check();

      expect(result.needsUpdate, isFalse);
      expect(result.updateUrl, isNull);
    });

    test('android bundle не шлёт — строка лежит под именем платформы',
        () async {
      final requested = <Uri>[];
      final client = MockClient((req) async {
        requested.add(req.url);
        return http.Response(
          jsonEncode({
            'platform': 'android',
            'build': 3728,
            'version': '2.4.0',
            'update_url': 'https://disk/x',
          }),
          200,
        );
      });
      // platformKeyOverride здесь оправдан: хост тестов — macOS, а проверяем
      // именно non-Apple ветку, где bundle не нужен.
      await VersionGateService(
        httpClient: client,
        baseUrl: 'https://vg.test',
        platformKeyOverride: 'android',
        currentBuildOverride: 3728,
        packageNameOverride: 'com.prodamus.laba.liza.android',
      ).check();

      expect(requested.single.toString(), 'https://vg.test/version/android');
    });

    test('разбор ответа не сломан: плашка по-прежнему поднимается', () async {
      final requested = <Uri>[];
      final result = await serviceFor(
        client: recorder(requested, build: 4000),
        currentBuild: 3728,
        packageName: 'ru.prodamus.liza',
      ).check();

      expect(result.needsUpdate, isTrue);
      expect(result.updateUrl, 'itms-beta://');
    });
  });
}
