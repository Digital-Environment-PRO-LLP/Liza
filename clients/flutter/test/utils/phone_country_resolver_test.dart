import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:liza/utils/phone_country.dart';
import 'package:liza/utils/phone_country_resolver.dart';

void main() {
  HttpPhoneCountryResolver resolverWith(
    Future<http.Response> Function(http.Request request) handler,
  ) =>
      HttpPhoneCountryResolver(
        baseUrl: 'auth.example.com',
        httpClient: MockClient(handler),
      );

  group('HttpPhoneCountryResolver', () {
    test('успешный ответ даёт страну из справочника', () async {
      final resolver = resolverWith(
        (_) async => http.Response(jsonEncode({'country': 'AM'}), 200),
      );

      final country = await resolver.resolveByIp();

      expect(country, isNotNull);
      expect(country!.isoCode, 'AM');
      expect(country.dialCode, '374');
    });

    test('код в нижнем регистре тоже распознаётся', () async {
      final resolver = resolverWith(
        (_) async => http.Response(jsonEncode({'country': 'kz'}), 200),
      );

      expect((await resolver.resolveByIp())?.isoCode, 'KZ');
    });

    test('country: null оставляет страну на локали', () async {
      final resolver = resolverWith(
        (_) async => http.Response(jsonEncode({'country': null}), 200),
      );

      expect(await resolver.resolveByIp(), isNull);
    });

    test('неизвестный ISO-код не ломает экран, а даёт null', () async {
      // Страны нет в коротком справочнике kPhoneCountries — это штатный
      // случай, а не ошибка.
      final resolver = resolverWith(
        (_) async => http.Response(jsonEncode({'country': 'ZW'}), 200),
      );

      expect(await resolver.resolveByIp(), isNull);
    });

    test('сетевая ошибка даёт null', () async {
      final resolver = resolverWith(
        (_) async => throw http.ClientException('сеть недоступна'),
      );

      expect(await resolver.resolveByIp(), isNull);
    });

    test('таймаут даёт null и не подвешивает экран', () async {
      final resolver = resolverWith((_) async {
        // Дольше внутреннего таймаута резолвера (3 с).
        await Future<void>.delayed(const Duration(seconds: 10));
        return http.Response(jsonEncode({'country': 'AM'}), 200);
      });

      expect(await resolver.resolveByIp(), isNull);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('429 (лимит) даёт null', () async {
      final resolver = resolverWith(
        (_) async => http.Response(jsonEncode({'error': 'rate_limited'}), 429),
      );

      expect(await resolver.resolveByIp(), isNull);
    });

    test('500 даёт null', () async {
      final resolver = resolverWith((_) async => http.Response('boom', 500));

      expect(await resolver.resolveByIp(), isNull);
    });

    test('битый JSON даёт null', () async {
      final resolver = resolverWith(
        (_) async => http.Response('не json вовсе', 200),
      );

      expect(await resolver.resolveByIp(), isNull);
    });

    test('country не строка — null', () async {
      final resolver = resolverWith(
        (_) async => http.Response(jsonEncode({'country': 42}), 200),
      );

      expect(await resolver.resolveByIp(), isNull);
    });

    test('JSON-массив вместо объекта — null', () async {
      final resolver = resolverWith(
        (_) async => http.Response(jsonEncode(['AM']), 200),
      );

      expect(await resolver.resolveByIp(), isNull);
    });

    test('запрос идёт по https на хост auth-proxy', () async {
      // Регрессия: baseUrl — ГОЛЫЙ хост. Uri.parse от него дал бы
      // относительный адрес, и на вебе запрос ушёл бы на origin страницы.
      late Uri seen;
      final resolver = resolverWith((request) async {
        seen = request.url;
        return http.Response(jsonEncode({'country': 'AM'}), 200);
      });

      await resolver.resolveByIp();

      expect(seen.scheme, 'https');
      expect(seen.host, 'auth.example.com');
      expect(seen.path, '/api/geo/country');
      expect(seen.isAbsolute, isTrue);
    });
  });

  group('NoopPhoneCountryResolver', () {
    test('ничего не уточняет', () async {
      expect(await const NoopPhoneCountryResolver().resolveByIp(), isNull);
    });
  });

  group('phoneCountryByIso', () {
    test('маппит известные коды', () {
      expect(phoneCountryByIso('AM')?.dialCode, '374');
      expect(phoneCountryByIso('ru')?.dialCode, '7');
    });

    test('неизвестный код — null', () {
      expect(phoneCountryByIso('ZW'), isNull);
      expect(phoneCountryByIso(''), isNull);
      expect(phoneCountryByIso(null), isNull);
    });
  });
}
