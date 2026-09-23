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

  test('needsUpdate when client build is lower', () async {
    final client = MockClient((req) async => http.Response(
          jsonEncode({'platform': 'ios', 'build': 3700, 'version': '2.5.0', 'update_url': 'https://u'}),
          200,
        ));
    final result = await build(client, currentBuild: 3643, platformKey: 'ios').check();
    expect(result.needsUpdate, isTrue);
    expect(result.updateUrl, 'https://u');
    expect(result.latestVersion, '2.5.0');
  });

  test('no update when client build equal or higher', () async {
    final client = MockClient((req) async => http.Response(
          jsonEncode({'platform': 'ios', 'build': 3643, 'version': '2.4.0', 'update_url': 'https://u'}),
          200,
        ));
    final result = await build(client, currentBuild: 3643, platformKey: 'ios').check();
    expect(result.needsUpdate, isFalse);
  });

  test('fail-open on non-200', () async {
    final client = MockClient((req) async => http.Response('err', 500));
    final result = await build(client, currentBuild: 1, platformKey: 'ios').check();
    expect(result.needsUpdate, isFalse);
  });

  test('fail-open on network error', () async {
    final client = MockClient((req) async => throw Exception('boom'));
    final result = await build(client, currentBuild: 1, platformKey: 'ios').check();
    expect(result.needsUpdate, isFalse);
  });

  test('skips unsupported platform', () async {
    var called = false;
    final client = MockClient((req) async {
      called = true;
      return http.Response('{}', 200);
    });
    final result = await build(client, currentBuild: 1, platformKey: null).check();
    expect(result.needsUpdate, isFalse);
    expect(called, isFalse);
  });

  test('fail-open when build is not a number', () async {
    final client = MockClient((req) async => http.Response(
          jsonEncode({'platform': 'ios', 'build': 'oops', 'version': '2.5.0', 'update_url': 'https://u'}),
          200,
        ));
    final result = await build(client, currentBuild: 1, platformKey: 'ios').check();
    expect(result.needsUpdate, isFalse);
  });

  test('handles build as double', () async {
    final client = MockClient((req) async => http.Response(
          jsonEncode({'platform': 'ios', 'build': 3700.0, 'version': '2.5.0', 'update_url': 'https://u'}),
          200,
        ));
    final result = await build(client, currentBuild: 3643, platformKey: 'ios').check();
    expect(result.needsUpdate, isTrue);
  });
}
