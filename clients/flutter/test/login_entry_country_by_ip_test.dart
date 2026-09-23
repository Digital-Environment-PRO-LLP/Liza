import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/homeserver_picker/login_entry_actions.dart';
import 'package:liza/utils/phone_country.dart';
import 'package:liza/utils/phone_country_resolver.dart';

/// Резолвер, отвечающий сразу.
class _FakeResolver implements PhoneCountryResolver {
  _FakeResolver(this.country);

  final PhoneCountry? country;
  int calls = 0;

  @override
  Future<PhoneCountry?> resolveByIp() async {
    calls++;
    return country;
  }
}

/// Резолвер с ручным управлением моментом ответа: `pumpAndSettle` его не
/// торопит, поэтому тест может ввести текст ДО прихода страны по IP —
/// ровно тот порядок, в котором баг и проявлялся бы.
class _ManualResolver implements PhoneCountryResolver {
  final _completer = Completer<PhoneCountry?>();
  int calls = 0;

  @override
  Future<PhoneCountry?> resolveByIp() {
    calls++;
    return _completer.future;
  }

  void complete(PhoneCountry? country) => _completer.complete(country);
}

const _armenia = PhoneCountry(
  isoCode: 'AM',
  dialCode: '374',
  example: '77 123-456',
);

void main() {
  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(body: child),
      );

  Widget entry({
    PhoneCountryResolver? resolver,
    PhoneCountry? initialCountry = kDefaultPhoneCountry,
  }) =>
      LoginEntryActions(
        isLoading: false,
        onRegister: () {},
        onSignIn: () {},
        onSubmitPhone: (_) {},
        countryResolver: resolver,
        initialCountry: initialCountry,
      );

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('страна по IP заменяет префикс, если поле не трогали', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(entry(resolver: _FakeResolver(_armenia))),
    );
    await tester.pumpAndSettle();

    expect(fieldText(tester), '+374 ');
  });

  testWidgets('null от резолвера оставляет префикс локали', (tester) async {
    await tester.pumpWidget(
      wrap(entry(resolver: _FakeResolver(null))),
    );
    await tester.pumpAndSettle();

    expect(fieldText(tester), '+7 ');
  });

  testWidgets('без резолвера префикс остаётся от локали', (tester) async {
    await tester.pumpWidget(wrap(entry()));
    await tester.pumpAndSettle();

    expect(fieldText(tester), '+7 ');
  });

  testWidgets(
    'гард _touched: набранный номер НЕ затирается поздним ответом по IP',
    (tester) async {
      // Главная регрессия: ответ приходит асинхронно и мог бы стереть уже
      // введённый человеком номер.
      final resolver = _ManualResolver();
      await tester.pumpWidget(wrap(entry(resolver: resolver)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '+7 999 123-45-67');
      await tester.pumpAndSettle();

      // Ответ по IP приходит уже ПОСЛЕ ввода.
      resolver.complete(_armenia);
      await tester.pumpAndSettle();

      expect(resolver.calls, 1);
      expect(fieldText(tester), '+7 999 123-45-67');
    },
  );

  testWidgets('резолвер не дёргается в прод-ветке (без поля телефона)', (
    tester,
  ) async {
    final resolver = _FakeResolver(_armenia);
    await tester.pumpWidget(
      wrap(
        LoginEntryActions(
          isLoading: false,
          onRegister: () {},
          onSignIn: () {},
          countryResolver: resolver,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(resolver.calls, 0);
  });
}
