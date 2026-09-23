// ledger:RL-auth-phone-min-length-keycloak
// AC:RL-auth-phone-min-length-keycloak/2 AC:RL-auth-phone-min-length-keycloak/3
// AC:RL-auth-phone-min-length-keycloak/4
//
// LABA-2527: нижняя граница длины номера у клиента, auth-proxy и Keycloak
// realm `payform2` (User Profile `phone`: min 10) — одна и та же. Номер,
// который аккаунтом не станет, отсекается на первом экране: без SMS, без
// сироты в Synapse, без ложного «Сервис авторизации недоступен» на шаге кода.
//
// Ассерты идут по РЕАЛЬНОМУ `normalizeToE164` и РЕАЛЬНОМУ виджету
// `LoginEntryActions`; литералы длин те же, что в серверном
// `tests/test_phone_e164.py::test_min_length_is_keycloak_boundary`.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/homeserver_picker/login_entry_actions.dart';
import 'package:liza/utils/phone_country.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('ru'),
    home: Scaffold(body: child),
  );

  group('AC-2 — граница длины: те же литералы, что на сервере', () {
    test('8 и 9 цифр — отказ, 10 и 15 — принимаются, 16 — отказ', () {
      // Код страны 63 существует, поэтому отказ здесь — именно по длине.
      expect(normalizeToE164('+63118833'), isNull); // 8 — номер из тикета
      expect(normalizeToE164('+631188331'), isNull); // 9
      expect(normalizeToE164('+6311883312'), '+6311883312'); // 10
      expect(normalizeToE164('+631188331234567'), '+631188331234567'); // 15
      expect(normalizeToE164('+6311883312345678'), isNull); // 16
    });

    test('реальные короткие страны отсекаются осознанно, Дания — нет', () {
      // Фареры (+298) и о. Вознесения (+247) — живые 9-значные E.164, но
      // realm Keycloak такой `phone` не примет: отказ на входе честнее
      // отказа после SMS. Дания (+45, 10 цифр) — контроль границы.
      expect(normalizeToE164('+298 123456'), isNull);
      expect(normalizeToE164('+247 123456'), isNull);
      expect(normalizeToE164('+45 12345678'), '+4512345678');
    });
  });

  test('AC-3 — kPhoneMinDigits равен серверному _MIN_DIGITS', () {
    // Единственный страж рассинхрона зеркала: константы живут в двух
    // кодовых базах без общего источника, и до LABA-2527 сдвиг одной из
    // них не краснел нигде. Тест читает серверный модуль с диска — тот же
    // приём, что чтение intl_ru.arb в соседних тестах.
    final server = File('../../servers/auth-proxy/app/phone_e164.py');
    expect(server.existsSync(), isTrue, reason: 'нет ${server.path}');
    final source = server.readAsStringSync();
    final min = RegExp(
      r'^_MIN_DIGITS = (\d+)$',
      multiLine: true,
    ).firstMatch(source);
    final max = RegExp(
      r'^_MAX_DIGITS = (\d+)$',
      multiLine: true,
    ).firstMatch(source);
    expect(min, isNotNull, reason: '_MIN_DIGITS не найден в phone_e164.py');
    expect(max, isNotNull, reason: '_MAX_DIGITS не найден в phone_e164.py');
    expect(kPhoneMinDigits, int.parse(min!.group(1)!));
    expect(kPhoneMaxDigits, int.parse(max!.group(1)!));
    // Сама граница: 10 — валидатор `phone` realm'а payform2.
    expect(kPhoneMinDigits, 10);
  });

  testWidgets('AC-4 — 8-значный номер из тикета не уходит с первого экрана', (
    tester,
  ) async {
    var submitted = 0;
    await tester.pumpWidget(
      wrap(
        LoginEntryActions(
          isLoading: false,
          onRegister: () {},
          onSignIn: () {},
          onSubmitPhone: (_) => submitted++,
          initialCountry: kDefaultPhoneCountry,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final short in const ['+63 11 8833', '+298 123456']) {
      await tester.enterText(find.byType(TextField), short);
      await tester.pumpAndSettle();

      // Кнопка активна (порог `_isComplete` остаётся 8 — дизайн
      // LABA-2531: отказ текстом по нажатию, а не серой кнопкой).
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull, reason: short);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      expect(submitted, 0, reason: '$short ушёл на шаг кода');
      expect(
        find.text('Введите корректный номер телефона'),
        findsOneWidget,
        reason: short,
      );
    }

    // Контроль: 10-значный номер проходит ровно один раз.
    await tester.enterText(find.byType(TextField), '+45 12345678');
    await tester.pumpAndSettle();
    expect(find.text('Введите корректный номер телефона'), findsNothing);
    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(submitted, 1);
    expect(tester.takeException(), isNull);
  });
}
