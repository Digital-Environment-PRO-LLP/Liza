import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:liza/pages/demo_auth/demo_auth_service.dart';

void main() {
  group('DemoAuthService', () {
    late List<http.Request> requests;

    MockClient mock(Map<String, dynamic> body, {int status = 200}) {
      return MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(body),
          status,
          headers: {'content-type': 'application/json'},
        );
      });
    }

    setUp(() => requests = []);

    test('startPhone возвращает ticket и маскированный получатель', () async {
      final service = DemoAuthService(
        client: mock({
          'ticket': 'tkt-1',
          'masked_destination': '+7 (968) ***-**-80',
        }),
      );

      final result = await service.startPhone('+79687995380');

      expect(result.ticket, 'tkt-1');
      expect(result.maskedDestination, '+7 (968) ***-**-80');
      expect(requests.single.url.path, '/api/auth/phone/start');
      expect(jsonDecode(requests.single.body)['phone'], '+79687995380');
    });

    test('verifyPhone различает вход и регистрацию', () async {
      final login = DemoAuthService(
        client: mock({
          'status': 'login',
          'email_masked': 'i***v@example.com',
          'has_email': true,
        }),
      );
      final loginResult = await login.verifyPhone(ticket: 't', code: '12345');
      expect(loginResult.isExistingUser, isTrue);
      expect(loginResult.hasEmail, isTrue);
      expect(loginResult.maskedEmail, 'i***v@example.com');

      requests = [];
      final register = DemoAuthService(client: mock({'status': 'register'}));
      final registerResult = await register.verifyPhone(
        ticket: 't',
        code: '12345',
      );
      expect(registerResult.isExistingUser, isFalse);
      expect(registerResult.hasEmail, isFalse);
    });

    test('ошибка сервера превращается в код для UI', () async {
      final service = DemoAuthService(
        client: mock({
          'error': 'invalid_code',
          'attempts_remain': 2,
        }, status: 400),
      );

      await expectLater(
        service.verifyPhone(ticket: 't', code: '00000'),
        throwsA(
          isA<DemoAuthException>()
              .having((e) => e.code, 'code', 'invalid_code')
              .having((e) => e.attemptsRemain, 'attemptsRemain', 2),
        ),
      );
    });

    test('sendEmailCode возвращает маскированный адрес', () async {
      final service = DemoAuthService(
        client: mock({
          'masked_destination': 'i***v@example.com',
          'expires_in': 300,
        }),
      );

      final result = await service.sendEmailCode(
        ticket: 't',
        email: 'ivanov@example.com',
      );

      expect(result.maskedDestination, 'i***v@example.com');
      expect(requests.single.url.path, '/api/auth/email/send');
    });

    test('слишком частая пересылка отдаёт resend_too_soon', () async {
      final service = DemoAuthService(
        client: mock({'error': 'resend_too_soon'}, status: 429),
      );

      await expectLater(
        service.sendEmailCode(ticket: 't', email: 'a@b.ru'),
        throwsA(
          isA<DemoAuthException>().having(
            (e) => e.code,
            'code',
            'resend_too_soon',
          ),
        ),
      );
    });

    test('complete отдаёт данные для входа в Matrix', () async {
      final service = DemoAuthService(
        client: mock({
          'login_token': 'syt_token',
          'server_name': 'dev.liza.laba.prodamus.tech',
          'user_id': '@ivan:dev.liza.laba.prodamus.tech',
        }),
      );

      final result = await service.complete(ticket: 't');

      expect(result.needsServerChoice, isFalse);
      expect(result.tokens!.loginToken, 'syt_token');
      expect(result.tokens!.userId, '@ivan:dev.liza.laba.prodamus.tech');
    });

    test('несколько аккаунтов — сервер просит выбрать инстанс', () async {
      final service = DemoAuthService(
        client: mock({
          'status': 'select_server',
          'accounts': [
            {
              'server_name': 'synapse.liza.laba.prodamus.tech',
              'user_id': '@ivan:synapse.liza.laba.prodamus.tech',
              'is_default': false,
            },
            {
              'server_name': 'bots.liza.ru',
              'user_id': '@ivan:bots.liza.ru',
              'is_default': true,
            },
          ],
        }),
      );

      final result = await service.complete(ticket: 't');

      expect(result.needsServerChoice, isTrue);
      expect(result.accounts, hasLength(2));
      expect(
        result.accounts.first.serverName,
        'synapse.liza.laba.prodamus.tech',
      );
      expect(result.accounts.last.isDefault, isTrue);
    });

    test('выбранный инстанс уходит в запрос', () async {
      final service = DemoAuthService(
        client: mock({
          'login_token': 'syt_token',
          'server_name': 'bots.liza.ru',
          'user_id': '@ivan:bots.liza.ru',
        }),
      );

      await service.complete(ticket: 't', serverName: 'bots.liza.ru');

      expect(jsonDecode(requests.single.body)['server_name'], 'bots.liza.ru');
    });

    test(
      '429 отдаёт код лимита и время ожидания, а не internal_error',
      () async {
        // Серверные лимиты отвечают Too Many Requests: без разбора тела
        // клиент показывал бы «что-то пошло не так».
        final service = DemoAuthService(
          client: mock({
            'error': 'otp_rate_limited',
            'resend_available_in': 42,
          }, status: 429),
        );

        await expectLater(
          service.startPhone('+79991234567'),
          throwsA(
            isA<DemoAuthException>()
                .having((e) => e.code, 'code', 'otp_rate_limited')
                .having((e) => e.resendAvailableIn, 'resendAvailableIn', 42),
          ),
        );
      },
    );

    test('422 часового потолка тоже разбирается', () async {
      // Часовой потолок auth-proxy отвечает 422 (как otpverification),
      // а не 429 — разбор тела не должен зависеть от статуса.
      final service = DemoAuthService(
        client: mock({
          'error': 'otp_request_limit_per_hour',
          'resend_available_in': 0,
        }, status: 422),
      );

      await expectLater(
        service.startPhone('+79991234567'),
        throwsA(
          isA<DemoAuthException>().having(
            (e) => e.code,
            'code',
            'otp_request_limit_per_hour',
          ),
        ),
      );
    });

    test('таймер повтора берётся из ответа сервера', () async {
      final service = DemoAuthService(
        client: mock({
          'ticket': 'tkt-1',
          'masked_destination': '+7 (999) ***-**-67',
          'resend_available_in': 55,
          'expires_in': 300,
        }),
      );

      final result = await service.startPhone('+79991234567');

      expect(result.resendAvailableIn, 55);
      expect(result.expiresIn, 300);
    });

    test('выбранный канал уходит в запрос', () async {
      final service = DemoAuthService(
        client: mock({'ticket': 't', 'channel': 'email'}),
      );

      final result = await service.startPhone('+79991234567', channel: 'email');

      expect(jsonDecode(requests.single.body)['channel'], 'email');
      expect(result.isEmailChannel, isTrue);
    });

    test(
      'смена с email на SMS сохраняет тикет и не вызывает email endpoint',
      () async {
        final service = DemoAuthService(
          client: mock({'ticket': 't', 'channel': 'phone'}),
        );

        final result = await service.startPhone(
          '+79991234567',
          ticket: 't',
          channel: 'phone',
        );

        expect(result.isEmailChannel, isFalse);
        expect(jsonDecode(requests.single.body), {
          'phone': '+79991234567',
          'ticket': 't',
          'channel': 'phone',
        });
        expect(requests.single.url.path, '/api/auth/phone/start');
        expect(
          requests.map((request) => request.url.path),
          isNot(contains('/api/auth/email/send')),
        );
      },
    );

    test('иностранный номер уходит на сервер как есть', () async {
      final service = DemoAuthService(client: mock({'ticket': 't'}));

      await service.startPhone('+995555123456');

      expect(jsonDecode(requests.single.body)['phone'], '+995555123456');
    });

    test('недоступность сети даёт network_error', () async {
      final service = DemoAuthService(
        client: MockClient((_) async => throw const SocketExceptionStub()),
      );

      await expectLater(
        service.startPhone('+79687995380'),
        throwsA(
          isA<DemoAuthException>().having(
            (e) => e.code,
            'code',
            'network_error',
          ),
        ),
      );
    });
  });
}

class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
