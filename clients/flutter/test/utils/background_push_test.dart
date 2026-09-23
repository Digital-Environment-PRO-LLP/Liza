import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/background_push.dart';

/// Форма `additionalProperties` iOS/macOS-пушера: вложенная карта
/// `default_payload.aps` — именно она ломала поверхностный `mapEquals`.
Map<String, dynamic> _iosProps() => {
      'data_message': 'ios',
      'default_payload': {
        'aps': {
          'mutable-content': 1,
          'sound': 'liza_ding.aiff',
        },
      },
    };

/// Плоская форма Android — на ней бага нет (нет вложенных карт).
Map<String, dynamic> _androidProps() => {'data_message': 'android'};

const _gatewayUrl = 'https://sygnal.example/_matrix/push/v1/notify';

Pusher _pusher({
  String appId = 'ru.prodamus.liza',
  String appDisplayName = 'Liza',
  String deviceDisplayName = 'Liza ios',
  String kind = 'http',
  String lang = 'en',
  String url = _gatewayUrl,
  String? format,
  Map<String, Object?>? additionalProperties,
}) =>
    Pusher(
      pushkey: 'token-abc',
      appId: appId,
      appDisplayName: appDisplayName,
      deviceDisplayName: deviceDisplayName,
      kind: kind,
      lang: lang,
      data: PusherData(
        url: Uri.parse(url),
        format: format,
        additionalProperties: additionalProperties ?? _iosProps(),
      ),
    );

/// Вызов реальной прод-функции с дефолтами, совпадающими с `_pusher()`.
String? _reason(
  Pusher pusher, {
  String appId = 'ru.prodamus.liza',
  String appDisplayName = 'Liza',
  String? deviceDisplayName = 'Liza ios',
  String gatewayUrl = _gatewayUrl,
  String? format,
  Map<String, dynamic>? additionalProperties,
}) =>
    BackgroundPush.pusherMismatchReason(
      pusher: pusher,
      expectedAppId: appId,
      expectedAppDisplayName: appDisplayName,
      expectedDeviceDisplayName: deviceDisplayName,
      expectedGatewayUrl: gatewayUrl,
      expectedFormat: format,
      expectedAdditionalProperties: additionalProperties ?? _iosProps(),
    );

void main() {
  group('BackgroundPush.getTokenWithRetry', () {
    test('возвращает токен с первой попытки, если getToken отдаёт значение',
        () async {
      var calls = 0;
      final token = await BackgroundPush.getTokenWithRetry(
        () async {
          calls++;
          return 'token-abc';
        },
        sleep: (_) async {},
      );
      expect(token, 'token-abc');
      expect(calls, 1);
    });

    test('повторяет ровно 3 раза, если все попытки возвращают null', () async {
      var calls = 0;
      final token = await BackgroundPush.getTokenWithRetry(
        () async {
          calls++;
          return null;
        },
        sleep: (_) async {},
      );
      expect(token, isNull);
      expect(calls, 3);
    });

    test('повторяет до 3 раз при исключениях, потом возвращает null',
        () async {
      var calls = 0;
      final token = await BackgroundPush.getTokenWithRetry(
        () async {
          calls++;
          throw Exception('native not ready');
        },
        sleep: (_) async {},
      );
      expect(token, isNull);
      expect(calls, 3);
    });

    test('возвращает токен с поздней попытки, если ранние вернули null',
        () async {
      var calls = 0;
      final token = await BackgroundPush.getTokenWithRetry(
        () async {
          calls++;
          if (calls < 3) return null;
          return 'late-token';
        },
        sleep: (_) async {},
      );
      expect(token, 'late-token');
      expect(calls, 3);
    });

    test('экспоненциальный backoff: задержки 1s, 2s между 3 попытками',
        () async {
      final delays = <Duration>[];
      await BackgroundPush.getTokenWithRetry(
        () async => null,
        sleep: (d) async {
          delays.add(d);
        },
      );
      // Между 3 попытками: 2 паузы.
      expect(delays.length, 2);
      expect(delays[0], const Duration(seconds: 1));
      expect(delays[1], const Duration(seconds: 2));
    });

    test('пустая строка интерпретируется как отсутствие токена', () async {
      var calls = 0;
      final token = await BackgroundPush.getTokenWithRetry(
        () async {
          calls++;
          return '';
        },
        sleep: (_) async {},
      );
      expect(token, isNull);
      expect(calls, 3);
    });
  });

  // ledger:RL-pusher-dedup-nested-payload
  // Дедуп pusher'а НЕ пересоздаёт идентичный pusher: сравнение
  // additionalProperties — глубокое (DeepCollectionEquality), а не поверхностное
  // mapEquals. Иначе вложенный default_payload.aps давал вечное ложное
  // расхождение → петля delete+post на каждый resume → потеря пушей у всех
  // Apple-устройств. Тестируем РЕАЛЬНУЮ прод-функцию pusherMismatchReason.
  // ledger:RL-apns-debug-pusher-skip
  group('BackgroundPush.shouldRegisterPusher', () {
    test(
      'AC:RL-apns-debug-pusher-skip/1 отладочная сборка на iOS/macOS вне локального стека pusher НЕ регистрирует (sandbox-токен отвергается production APNs → петля удалений)',
      () {
        for (final (apple, release, local) in [(true, false, false)]) {
          expect(
            BackgroundPush.shouldRegisterPusher(
              apple: apple,
              releaseMode: release,
              localHomeserver: local,
            ),
            isFalse,
          );
        }
      },
    );
    test(
      'AC:RL-apns-debug-pusher-skip/2 release-сборка на iOS/macOS регистрирует pusher',
      () {
        for (final (apple, release, local) in [(true, true, false)]) {
          expect(
            BackgroundPush.shouldRegisterPusher(
              apple: apple,
              releaseMode: release,
              localHomeserver: local,
            ),
            isTrue,
          );
        }
      },
    );
    test(
      'AC:RL-apns-debug-pusher-skip/3 Android регистрирует pusher и в отладочной сборке (FCM-токен от типа сборки не зависит)',
      () {
        for (final (apple, release, local) in [(false, false, false), (false, true, false)]) {
          expect(
            BackgroundPush.shouldRegisterPusher(
              apple: apple,
              releaseMode: release,
              localHomeserver: local,
            ),
            isTrue,
          );
        }
      },
    );
    test(
      'AC:RL-apns-debug-pusher-skip/4 локальный стек (APP_ENV=local) регистрирует pusher и в отладочной сборке',
      () {
        for (final (apple, release, local) in [(true, false, true)]) {
          expect(
            BackgroundPush.shouldRegisterPusher(
              apple: apple,
              releaseMode: release,
              localHomeserver: local,
            ),
            isTrue,
          );
        }
      },
    );
    // Найдено живым прогоном 2026-09-16: гейт смотрел на РЕЖИМ СБОРКИ
    // (AppConfig.isLocal), а в одном приложении рядом живут локальный и прод
    // аккаунт → local-сборка зарегистрировала sandbox-pusher на ПРОД-аккаунт
    // владельца. Это ровно петля pusher_rechurn, от которой и защищались.
    test(
      'AC:RL-apns-debug-pusher-skip/5 отладочная local-сборка НЕ регистрирует '
      'pusher для ПРОД-аккаунта (решает хоумсервер клиента, а не режим сборки)',
      () {
        expect(
          BackgroundPush.shouldRegisterPusher(
            apple: true,
            releaseMode: false,
            localHomeserver: BackgroundPush.isLocalHomeserver(
              Uri.parse('https://synapse.liza.laba.prodamus.tech'),
            ),
          ),
          isFalse,
        );
      },
    );
    test(
      'AC:RL-apns-debug-pusher-skip/6 распознавание локального хоумсервера '
      'по адресу клиента',
      () {
        for (final host in [
          'https://synapse.liza.local',
          'http://localhost:8008',
          'http://127.0.0.1:8008',
          // физический телефон против локального стенда (prove-ui, LAN-IP Mac'а)
          'http://192.168.8.217:8008',
          'http://10.0.0.5:8008',
          'http://172.20.1.9:8008',
        ]) {
          expect(
            BackgroundPush.isLocalHomeserver(Uri.parse(host)),
            isTrue,
            reason: host,
          );
        }
        for (final host in [
          'https://synapse.liza.laba.prodamus.tech',
          'https://liza.cyber-agro.ru',
          'https://nadezhda.liza.ru',
          // публичные IP — не LAN
          'http://172.32.0.1:8008',
          'http://8.8.8.8',
        ]) {
          expect(
            BackgroundPush.isLocalHomeserver(Uri.parse(host)),
            isFalse,
            reason: host,
          );
        }
        expect(BackgroundPush.isLocalHomeserver(null), isFalse);
      },
    );
  });

  group('BackgroundPush.pusherMismatchReason', () {
    test('AC:RL-pusher-dedup-nested-payload/1 идентичный вложенный '
        'default_payload (разные инстансы) → совпадение (null)', () {
      // pusher и expected — РАЗНЫЕ инстансы одинаковых по значению вложенных карт.
      expect(_reason(_pusher(additionalProperties: _iosProps())), isNull);
    });

    test('AC:RL-pusher-dedup-nested-payload/2 red-proof: поверхностный mapEquals '
        'ложно расходится на вложенной карте, DeepCollectionEquality — нет', () {
      final a = _iosProps();
      final b = _iosProps();
      // Механизм бага: mapEquals сравнивает вложенный Map по ссылке → false,
      // хотя содержимое идентично. Откат прод-функции на mapEquals → AC-1 red.
      expect(mapEquals(a, b), isFalse,
          reason: 'shallow mapEquals должен ложно расходиться (это и есть баг)');
      expect(const DeepCollectionEquality().equals(a, b), isTrue,
          reason: 'deep-сравнение видит структурное равенство');
    });

    test('AC:RL-pusher-dedup-nested-payload/3 плоская Android-карта совпадает → '
        'null (регрессии на плоском кейсе нет)', () {
      // Android НЕ мигрирует: app_id = com.prodamus.laba.liza(.data_message).
      // Берём через прод-хелпер, а не литералом — чтобы фикстура не запекала
      // баговый ru.prodamus.liza.data_message (инцидент сборки 3734).
      final androidAppId =
          BackgroundPush.androidDataMessageAppId('com.prodamus.laba.liza');
      final p = _pusher(
        appId: androidAppId,
        deviceDisplayName: 'Liza android',
        additionalProperties: _androidProps(),
      );
      expect(
        _reason(p,
            appId: androidAppId,
            deviceDisplayName: 'Liza android',
            additionalProperties: _androidProps()),
        isNull,
      );
    });

    test('AC:RL-pusher-dedup-nested-payload/4 отличие ВЛОЖЕННОГО aps.sound → '
        'расхождение additionalProperties (легитимная перерегистрация)', () {
      final changed = _iosProps();
      (changed['default_payload'] as Map)['aps'] = {
        'mutable-content': 1,
        'sound': 'other.aiff',
      };
      expect(_reason(_pusher(additionalProperties: changed)),
          'additionalProperties');
    });

    test('AC:RL-pusher-dedup-nested-payload/5 отличие ВЕРХНЕГО data_message → '
        'расхождение additionalProperties', () {
      expect(_reason(_pusher(additionalProperties: _androidProps())),
          'additionalProperties');
    });

    test('AC:RL-pusher-dedup-nested-payload/6 пустые карты совпадают, '
        'пустая vs непустая — расходятся', () {
      expect(
        _reason(_pusher(additionalProperties: {}), additionalProperties: {}),
        isNull,
      );
      expect(
        _reason(_pusher(additionalProperties: {}),
            additionalProperties: _iosProps()),
        'additionalProperties',
      );
    });

    test('AC:RL-pusher-dedup-nested-payload/7 int переживает JSON round-trip '
        '(1 остаётся int, не bool/double) → совпадение', () {
      // Имитируем серверный round-trip: клиент постит → Synapse хранит JSON →
      // getPushers отдаёт jsonDecode. mutable-content:1 обязан остаться int.
      final roundTripped =
          jsonDecode(jsonEncode(_iosProps())) as Map<String, dynamic>;
      final aps = ((roundTripped['default_payload'] as Map)['aps'] as Map);
      expect(aps['mutable-content'], isA<int>());
      expect(_reason(_pusher(additionalProperties: roundTripped)), isNull);
    });

    test('AC:RL-pusher-dedup-nested-payload/8 deviceDisplayName расходится '
        '(в т.ч. ожидаемое null) → расхождение, а не молчаливая петля', () {
      // Мина-2: deviceName мог быть непустым при POST и пустым при сверке.
      expect(_reason(_pusher(deviceDisplayName: 'Liza macos')),
          'deviceDisplayName');
      expect(_reason(_pusher(), deviceDisplayName: null), 'deviceDisplayName');
    });

    test('AC:RL-pusher-dedup-nested-payload/10 переезд push-хоста: pusher на '
        'старом url при новом ожидаемом → data.url (новая сборка перерегистрирует)',
        () {
      const oldUrl =
          'https://sygnal.liza.laba.prodamus.tech/_matrix/push/v1/notify';
      const newUrl = 'https://push.tech.liza.ru/_matrix/push/v1/notify';
      expect(_reason(_pusher(url: oldUrl), gatewayUrl: newUrl), 'data.url');
      expect(_reason(_pusher(url: newUrl), gatewayUrl: newUrl), isNull);
    });
  });
}
