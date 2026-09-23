// ledger:RL-auth-otp-resend-timer-mmss
//
// LABA-2526: таймер повторной отправки кода показывал «1985 с». Теперь —
// «33:05» на реальном шаге кода, а отсчёт перезапускается ТОЛЬКО по новому
// ответу сервера (эпоха): прежнее сравнение «больше текущего» после
// «Отправить ещё раз» держало второй 33-минутный таймер при cooldown 60 с.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/demo_auth_flow.dart';
import 'package:liza/pages/demo_auth/demo_auth_service.dart';
import 'package:liza/pages/demo_auth/resend_countdown_format.dart';

DemoAuthStartResult _start(int seconds, {bool email = false}) =>
    DemoAuthStartResult(
      ticket: 't',
      maskedDestination: email ? 'd***@example.com' : '+7 980 ***-**-04',
      channel: email ? 'email' : 'phone',
      resendAvailableIn: seconds,
    );

Future<Never> _unexpected() => Future.error(StateError('не ожидалось'));

/// Сервис с управляемыми ответами `/phone/start` по номеру вызова и
/// отказом проверки кода — ровно то, что нужно таймеру.
class _FakeService extends DemoAuthService {
  _FakeService({required this.start, this.verify})
    : super(client: MockClient((_) async => http.Response('', 500)));

  final Future<DemoAuthStartResult> Function(int call) start;
  final Future<DemoAuthPhoneResult> Function()? verify;
  int startCalls = 0;

  @override
  Future<DemoAuthStartResult> startPhone(
    String phone, {
    String? ticket,
    String? channel,
  }) => start(++startCalls);

  @override
  Future<DemoAuthPhoneResult> verifyPhone({
    required String ticket,
    required String code,
  }) => (verify ?? _unexpected)();

  @override
  Future<void> verifyEmail({required String ticket, required String code}) =>
      _unexpected();

  @override
  Future<DemoAuthStartResult> sendEmailCode({
    required String ticket,
    required String email,
  }) => _unexpected();

  @override
  Future<DemoAuthCompleteResult> complete({
    required String ticket,
    String? serverName,
  }) => _unexpected();
}

const _ruPrefix = 'Отправить повторно через ';
const _enPrefix = 'Resend in ';
const _resendAgain = {'ru': 'Отправить ещё раз', 'en': 'Send again'};

/// Хвост старого формата: «… 1985 с» / «… 1985 s».
final _rawSeconds = RegExp(r'\d+ (с|s)$');

void main() {
  Future<void> settleFrames(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<DemoAuthFlowController> pumpFlow(
    WidgetTester tester,
    DemoAuthService service, {
    String locale = 'ru',
  }) async {
    // use-deferred-loading: первую загрузку локали делает настоящий
    // loadLibrary(), под fakeAsync он не резолвится — дерево остаётся пустым.
    await tester.runAsync(() => L10n.delegate.load(Locale(locale)));
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: Locale(locale),
        home: DemoAuthFlow(
          phone: '+79800550404',
          service: service,
          onAuthenticated: (_) async {},
        ),
      ),
    );
    // Не pumpAndSettle: Timer.periodic на секунду никогда не «уляжется».
    await settleFrames(tester);
    return tester.state<DemoAuthFlowController>(find.byType(DemoAuthFlow));
  }

  Finder timerText(String prefix, String time) => find.text('$prefix$time');

  // AC:RL-auth-otp-resend-timer-mmss/1
  test('AC-1: formatResendCountdown — м:сс без часовой ветки', () {
    const cases = {
      0: '0:00',
      -5: '0:00',
      59: '0:59',
      60: '1:00',
      61: '1:01',
      599: '9:59',
      600: '10:00',
      1985: '33:05',
      3599: '59:59',
      3600: '60:00',
      3605: '60:05',
    };
    for (final MapEntry(key: seconds, value: expected) in cases.entries) {
      expect(formatResendCountdown(seconds), expected, reason: '$seconds с');
    }
  });

  // AC:RL-auth-otp-resend-timer-mmss/2
  group(
    'AC-2: реальный шаг кода показывает м:сс на обоих каналах и языках',
    () {
      for (final email in [false, true]) {
        for (final MapEntry(key: locale, value: prefix) in {
          'ru': _ruPrefix,
          'en': _enPrefix,
        }.entries) {
          for (final seconds in [59, 1985, 3600]) {
            testWidgets('${email ? 'email' : 'sms'} / $locale / $seconds', (
              tester,
            ) async {
              final controller = await pumpFlow(
                tester,
                _FakeService(start: (_) async => _start(seconds, email: email)),
                locale: locale,
              );
              expect(controller.step, DemoAuthStep.sms);
              expect(controller.smsCodeSentByEmail, email);

              expect(
                timerText(prefix, formatResendCountdown(seconds)),
                findsOneWidget,
              );
              expect(find.text(_resendAgain[locale]!), findsNothing);
              expect(
                find.textContaining(_rawSeconds),
                findsNothing,
                reason: 'сырые секунды («1985 с») на экране — регресс',
              );
            });
          }
        }
      }
    },
  );

  // AC:RL-auth-otp-resend-timer-mmss/3
  group('AC-3: тики через границу минуты и до нуля', () {
    for (final MapEntry(key: seconds, value: after) in {
      60: '0:59',
      600: '9:59',
    }.entries) {
      testWidgets('$seconds → $after', (tester) async {
        await pumpFlow(
          tester,
          _FakeService(start: (_) async => _start(seconds)),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(timerText(_ruPrefix, after), findsOneWidget);
      });
    }

    testWidgets('2 → через два тика кнопка «Отправить ещё раз»', (
      tester,
    ) async {
      await pumpFlow(tester, _FakeService(start: (_) async => _start(2)));
      expect(timerText(_ruPrefix, '0:02'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(find.textContaining(_ruPrefix), findsNothing);
      expect(find.text(_resendAgain['ru']!), findsOneWidget);
    });
  });

  // AC:RL-auth-otp-resend-timer-mmss/5
  test('AC-5: оба шага кода форматируют через один хелпер', () {
    for (final step in ['demo_sms_step', 'demo_email_code_step']) {
      final source = File(
        'lib/pages/demo_auth/steps/$step.dart',
      ).readAsStringSync();
      expect(
        source,
        contains('demoAuthResendIn(formatResendCountdown(_secondsLeft))'),
        reason: '$step: таймер обязан идти через formatResendCountdown',
      );
      expect(
        source,
        isNot(contains('demoAuthResendIn(_secondsLeft)')),
        reason: '$step: сырые секунды в строке таймера',
      );
    }
  });

  // AC:RL-auth-otp-resend-timer-mmss/6
  testWidgets(
    'AC-6: после отсчёта «Отправить ещё раз» рисует серверные 60 с, а не остаток часа',
    (tester) async {
      // Ровно сценарий тикета: часовой лимит (1985 с) дотикал до нуля,
      // повторная отправка прошла, сервер отдал обычный cooldown.
      final service = _FakeService(
        start: (call) async => _start(call == 1 ? 1985 : 60),
      );
      await pumpFlow(tester, service);
      expect(timerText(_ruPrefix, '33:05'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1985));
      expect(find.text(_resendAgain['ru']!), findsOneWidget);

      await tester.tap(find.text(_resendAgain['ru']!));
      await settleFrames(tester);

      expect(service.startCalls, 2);
      expect(timerText(_ruPrefix, '1:00'), findsOneWidget);
      expect(find.textContaining('33:0'), findsNothing);
    },
  );

  // AC:RL-auth-otp-resend-timer-mmss/7
  testWidgets(
    'AC-7: перерисовка контроллера не перезапускает отсчёт, новый ответ — перезапускает, ноль — не гасит',
    (tester) async {
      var resendError = const DemoAuthException(
        'resend_too_soon',
        resendAvailableIn: 42,
      );
      final service = _FakeService(
        start: (call) =>
            call == 1 ? Future.value(_start(60)) : Future.error(resendError),
        verify: () => Future.error(
          const DemoAuthException('invalid_code', attemptsRemain: 2),
        ),
      );
      final controller = await pumpFlow(tester, service);

      await tester.pump(const Duration(seconds: 30));
      expect(timerText(_ruPrefix, '0:30'), findsOneWidget);

      // Неверный код: контроллер перерисовывается (isLoading → ошибка),
      // серверного значения таймера в ответе нет — отсчёт продолжается.
      await controller.submitSmsCode('123456');
      await settleFrames(tester);
      expect(controller.errorCode, 'invalid_code');
      // Кадры ожидания могли задеть границу секунды — допускаем один тик,
      // но не перезапуск к 1:00.
      expect(
        tester.widget<Text>(find.textContaining(_ruPrefix)).data,
        anyOf('${_ruPrefix}0:30', '${_ruPrefix}0:29'),
      );

      // Сервер прислал новое значение — отсчёт идёт от него.
      await controller.resendSms();
      await settleFrames(tester);
      expect(timerText(_ruPrefix, '0:42'), findsOneWidget);

      // Часовой потолок провайдера приходит с нулём — отсчёт не гасится.
      resendError = const DemoAuthException(
        'otp_request_limit_per_hour',
        resendAvailableIn: 0,
      );
      await tester.pump(const Duration(milliseconds: 1700));
      await controller.resendSms();
      await settleFrames(tester);
      expect(timerText(_ruPrefix, '0:40'), findsOneWidget);
      expect(find.text(_resendAgain['ru']!), findsNothing);
    },
  );
}
