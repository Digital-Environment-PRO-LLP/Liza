import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:liza/utils/handle_profile_field.dart';

Future<Client> _buildClient(http.Client httpClient) async {
  final client = Client(
    'Liza Test',
    httpClient: httpClient,
    database: await MatrixSdkDatabase.init(
      'handle_profile_field_test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    ),
  );
  client.homeserver = Uri.parse('https://fakeserver.notexisting');
  client.accessToken = 'test_token';
  return client;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('handleFromProfile', () {
    test('читает ru.liza.handle', () {
      final profile = ProfileInformation(
        additionalProperties: {lizaHandleField: 'ivanov'},
      );

      expect(handleFromProfile(profile), 'ivanov');
    });

    test('возвращает null для пустого значения', () {
      final profile = ProfileInformation(
        additionalProperties: {lizaHandleField: ''},
      );

      expect(handleFromProfile(profile), isNull);
    });

    test('возвращает null, если поле отсутствует', () {
      final profile = ProfileInformation();

      expect(handleFromProfile(profile), isNull);
    });

    test('отбрасывает невалидный ник', () {
      // Поле пишет сам владелец аккаунта — защита от мусора/подделки
      // (короткий ник, кириллица, резервное слово).
      for (final bad in ['ab', 'розенталь', 'admin', '#ivanov']) {
        final profile = ProfileInformation(
          additionalProperties: {lizaHandleField: bad},
        );
        expect(handleFromProfile(profile), isNull, reason: bad);
      }
    });

    test('отбрасывает значение неверного типа', () {
      final profile = ProfileInformation(
        additionalProperties: {lizaHandleField: 42},
      );

      expect(handleFromProfile(profile), isNull);
    });

    test('нормализует регистр', () {
      final profile = ProfileInformation(
        additionalProperties: {lizaHandleField: 'IvaNoV'},
      );

      expect(handleFromProfile(profile), 'ivanov');
    });
  });

  group('publishHandle', () {
    test('пишет поле профиля через setProfileField', () async {
      http.Request? captured;
      final mockClient = MockClient((req) async {
        captured = req;
        return http.Response('{}', 200);
      });
      final client = await _buildClient(mockClient);
      client.setUserId('@ivanov:fakeserver.notexisting');

      await publishHandle(client, 'ivanov');

      expect(captured, isNotNull);
      expect(captured!.method, 'PUT');
      expect(
        captured!.url.path,
        '/_matrix/client/v3/profile/%40ivanov%3Afakeserver.notexisting/ru.liza.handle',
      );
      expect(
        jsonDecode(captured!.body),
        {'ru.liza.handle': 'ivanov'},
      );
    });

    test('без известного userID не делает сетевого запроса', () async {
      var calls = 0;
      final mockClient = MockClient((req) async {
        calls++;
        return http.Response('{}', 200);
      });
      final client = await _buildClient(mockClient);

      await publishHandle(client, 'ivanov');

      expect(calls, 0);
    });
  });
}
