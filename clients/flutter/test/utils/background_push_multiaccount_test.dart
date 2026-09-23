// ignore_for_file: depend_on_referenced_packages

// Страж регистрации pusher для КАЖДОГО залогиненного аккаунта устройства.
// Инцидент 2026-09-03: `BackgroundPush` был привязан к одному клиенту
// (`clients.first`) → у второго/третьего аккаунта Нади pusher-ов не было вовсе, а
// `append:false` на одном хоумсервере сносил pusher соседа («были, пропали»).
// Гоняет РЕАЛЬНЫЙ `BackgroundPush.setupPusher` против FakeMatrixApi с
// per-user памятью pushers (см. per_user_fake_api.dart), не реплику.
//
// ledger:RL-push-multiaccount-pusher-per-client

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/background_push.dart';
import 'package:liza/utils/push_helper.dart';

import 'per_user_fake_api.dart';
import 'test_client.dart';

const _gateway = 'https://push.tech.liza.ru/_matrix/push/v1/notify';
const _token = 'fcm-token-of-this-device';

const _prod = '@nadya:synapse.liza.laba.prodamus.tech';
const _n2 = '@nadezhda.rozental:nadezhda.liza.ru';
const _n3 = '@rozental.nadezhda:nadezhda.liza.ru';

class _Acc {
  _Acc(this.client, this.api);
  final Client client;
  final PerUserFakeMatrixApi api;
}

Future<_Acc> _acc(String name, String userId) async {
  final host = userId.split(':').last;
  final api = PerUserFakeMatrixApi(userId: userId, homeserverHost: host);
  final client = await prepareTestClient(
    loggedIn: true,
    clientName: name,
    userId: userId,
    homeserver: Uri.parse('https://$host'),
    httpClient: api,
  );
  return _Acc(client, api);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Acc a, b, c;

  setUp(() async {
    a = await _acc('Liza android', _prod);
    b = await _acc('Liza-1786629781847', _n2);
    c = await _acc('Liza-1787253958881', _n3);
    for (final x in [a, b, c]) {
      x.api.peers.addAll([a.api, b.api, c.api].where((p) => p != x.api));
    }
  });

  tearDown(() async {
    await a.client.dispose();
    await b.client.dispose();
    await c.client.dispose();
  });

  Future<void> registerAll(BackgroundPush push, List<_Acc> accs) async {
    for (final x in accs) {
      await push.setupPusher(
        client: x.client,
        gatewayUrl: _gateway,
        token: _token,
      );
    }
  }

  // AC:RL-push-multiaccount-pusher-per-client/1
  test('∀ конфигураций число POST /pushers/set == число клиентов', () async {
    final configs = <String, List<_Acc>>{
      '1 клиент': [a],
      '2 на разных HS': [a, b],
      '2 на одном HS': [b, c],
      '3 как у Нади': [a, b, c],
    };
    for (final entry in configs.entries) {
      for (final x in [a, b, c]) {
        x.api.posted.clear();
        x.api.deleted.clear();
        x.api.pushers.clear();
      }
      final push = BackgroundPush.forTest(
        entry.value.map((x) => x.client).toList(),
      );
      await registerAll(push, entry.value);
      for (final x in entry.value) {
        expect(x.api.posted.length, 1,
            reason: '${entry.key}: ${x.client.clientName}');
        expect(x.api.pushers.length, 1,
            reason: '${entry.key}: pusher ${x.client.clientName} жив');
        expect(push.pusherRegisteredByClient[x.client.clientName], isTrue);
      }
      expect(push.pusherRegistered, isTrue, reason: entry.key);
    }
  });

  // AC:RL-push-multiaccount-pusher-per-client/2
  test('append: false для единственного аккаунта на HS, true при ≥2 своих; '
      'red-proof — с append:false второй на том же HS сносит первого', () async {
    final push = BackgroundPush.forTest([a.client, b.client, c.client]);
    await registerAll(push, [a, b, c]);
    expect(a.api.posted.single['append'], isFalse, reason: 'prod — один на HS');
    expect(b.api.posted.single['append'], isTrue, reason: 'nadezhda №2');
    expect(c.api.posted.single['append'], isTrue, reason: 'nadezhda №3');
    // оба pusher-а на nadezhda живы одновременно
    expect(b.api.pushers.length, 1);
    expect(c.api.pushers.length, 1);

    // red-proof серверной семантики: append:false у c снёс бы pusher b.
    c.api.pushers.clear();
    await c.client.postPusher(
      Pusher(
        pushkey: _token,
        appId: 'x.y.z',
        appDisplayName: 'Liza',
        deviceDisplayName: 'dev',
        lang: 'en',
        data: PusherData(url: Uri.parse(_gateway)),
        kind: 'http',
      ),
      append: false,
    );
    expect(b.api.pushers.where((p) => p['app_id'] == 'x.y.z'), isEmpty);
  });

  // AC:RL-push-multiaccount-pusher-per-client/3
  test('default_payload.client_name == clientName у каждого pusher-а', () async {
    final push = BackgroundPush.forTest([a.client, b.client, c.client]);
    await registerAll(push, [a, b, c]);
    for (final x in [a, b, c]) {
      final data = x.api.posted.single['data'] as Map<String, dynamic>;
      final dp = data['default_payload'] as Map<String, dynamic>;
      expect(dp[pushClientNameKey], x.client.clientName);
    }
    // форма карты по платформам: apple — рядом aps, android — без aps
    final apple = BackgroundPush.pusherAdditionalProperties(
      'Liza android',
      dataMessage: 'ios',
      apple: true,
    );
    expect(apple['default_payload'][pushClientNameKey], 'Liza android');
    expect(apple['default_payload']['aps']['mutable-content'], 1);
    final android = BackgroundPush.pusherAdditionalProperties(
      'Liza android',
      dataMessage: 'android',
      apple: false,
    );
    expect(android['default_payload'][pushClientNameKey], 'Liza android');
    expect(android['default_payload'].containsKey('aps'), isFalse);
    expect(android['data_message'], 'android');
  });

  // AC:RL-push-multiaccount-pusher-per-client/5
  test('повторная регистрация → 0 POST, 0 DELETE (нет churn) для N∈{1,3}',
      () async {
    for (final accs in [
      [a],
      [a, b, c],
    ]) {
      for (final x in [a, b, c]) {
        x.api.posted.clear();
        x.api.deleted.clear();
        x.api.pushers.clear();
      }
      final push = BackgroundPush.forTest(accs.map((x) => x.client).toList());
      await registerAll(push, accs);
      for (final x in accs) {
        x.api.posted.clear();
        x.api.deleted.clear();
      }
      await registerAll(push, accs);
      for (final x in accs) {
        expect(x.api.posted, isEmpty, reason: '${x.client.clientName} POST');
        expect(x.api.deleted, isEmpty, reason: '${x.client.clientName} DELETE');
      }
    }
  });

  // AC:RL-push-multiaccount-pusher-per-client/6
  test('расхождение только по data (старый pusher без client_name) → 1 POST, '
      '0 DELETE (upsert); расхождение по app_id → DELETE + POST', () async {
    final push = BackgroundPush.forTest([a.client]);
    await registerAll(push, [a]);
    // «старый» pusher прежней сборки: тот же app_id/pushkey, data без client_name
    final old = Map<String, dynamic>.from(a.api.pushers.single);
    old['data'] = {
      'url': _gateway,
      'format': null,
      'data_message': 'ios',
    };
    a.api.pushers
      ..clear()
      ..add(old);
    a.api.posted.clear();
    a.api.deleted.clear();
    await registerAll(push, [a]);
    expect(a.api.posted.length, 1, reason: 'один POST (upsert)');
    expect(a.api.deleted, isEmpty, reason: 'без окна «удалён → не создан»');
    expect(a.api.pushers.length, 1);

    // смена идентичности строки (app_id) — legacy-путь: DELETE + POST
    final foreign = Map<String, dynamic>.from(a.api.pushers.single);
    foreign['app_id'] = 'legacy.app.id';
    a.api.pushers
      ..clear()
      ..add(foreign);
    a.api.posted.clear();
    a.api.deleted.clear();
    await registerAll(push, [a]);
    expect(a.api.posted.length, 1);
    expect(a.api.deleted.length, 1);
  });

  // AC:RL-push-multiaccount-pusher-per-client/6
  test('pusherUpsertNeedsDelete: только app_id/kind/число pushers по токену', () {
    expect(BackgroundPush.pusherUpsertNeedsDelete('additionalProperties'), isFalse);
    expect(BackgroundPush.pusherUpsertNeedsDelete('data.url'), isFalse);
    expect(BackgroundPush.pusherUpsertNeedsDelete('deviceDisplayName'), isFalse);
    expect(BackgroundPush.pusherUpsertNeedsDelete('appId'), isTrue);
    expect(BackgroundPush.pusherUpsertNeedsDelete('kind'), isTrue);
    expect(BackgroundPush.pusherUpsertNeedsDelete('pusherCount=0'), isTrue);
    expect(BackgroundPush.pusherUpsertNeedsDelete('pusherCount=2'), isTrue);
  });

  // AC:RL-push-multiaccount-pusher-per-client/7
  test('ротация FCM-токена → перерегистрация pusher-а КАЖДОГО аккаунта', () async {
    final push = BackgroundPush.forTest([a.client, b.client, c.client]);
    // Первый «refresh» = первичное получение токена (кэш _fcmToken) — как
    // setupFirebase в проде; pushers регистрируются, churn-а нет при повторе.
    await push.onFcmTokenRefresh(_token);
    for (final x in [a, b, c]) {
      expect(x.api.posted.length, 1, reason: x.client.clientName);
      x.api.posted.clear();
      x.api.deleted.clear();
    }
    await push.onFcmTokenRefresh('fcm-token-rotated');
    for (final x in [a, b, c]) {
      expect(x.api.posted.length, 1, reason: x.client.clientName);
      expect(x.api.posted.single['pushkey'], 'fcm-token-rotated');
      expect(x.api.deleted.length, 1,
          reason: '${x.client.clientName}: старый токен снят');
      expect(x.api.pushers.map((p) => p['pushkey']), ['fcm-token-rotated']);
    }
  });

  // AC:RL-push-multiaccount-pusher-per-client/4
  // AC:RL-pusher-dedup-nested-payload/9 — тот же инвариант со стороны dedup-реестра
  test('pusherMismatchReason: карта с client_name после JSON round-trip → null; '
      'другой client_name → additionalProperties', () {
    final props = BackgroundPush.pusherAdditionalProperties(
      'Liza-1786629781847',
      dataMessage: 'android',
      apple: false,
    );
    final roundTrip =
        (jsonDecode(jsonEncode(props)) as Map).cast<String, dynamic>();
    Pusher p(Map<String, Object?> add) => Pusher(
          pushkey: _token,
          appId: 'com.prodamus.laba.liza.data_message',
          appDisplayName: 'Liza',
          deviceDisplayName: 'Liza android',
          lang: 'en',
          kind: 'http',
          data: PusherData(url: Uri.parse(_gateway), additionalProperties: add),
        );
    String? reason(Map<String, Object?> add) =>
        BackgroundPush.pusherMismatchReason(
          pusher: p(add),
          expectedAppId: 'com.prodamus.laba.liza.data_message',
          expectedAppDisplayName: 'Liza',
          expectedDeviceDisplayName: 'Liza android',
          expectedGatewayUrl: _gateway,
          expectedFormat: null,
          expectedAdditionalProperties: props,
        );
    expect(reason(roundTrip), isNull);
    final other = BackgroundPush.pusherAdditionalProperties(
      'Liza-1787253958881',
      dataMessage: 'android',
      apple: false,
    );
    expect(reason(other), 'additionalProperties');
  });

  test('bootstrap smoke: FakeMatrixApi per-user login даёт разные userID', () {
    expect(a.client.userID, _prod);
    expect(b.client.userID, _n2);
    expect(c.client.userID, _n3);
    expect(debugDefaultTargetPlatformOverride, isNull);
  });
}
