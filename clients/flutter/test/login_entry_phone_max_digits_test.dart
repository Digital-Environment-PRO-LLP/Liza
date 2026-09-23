// ledger:RL-login-phone-input-max-digits
// AC:RL-login-phone-input-max-digits/1 AC:RL-login-phone-input-max-digits/2
// AC:RL-login-phone-input-max-digits/7
//
// LABA-2524: в поле телефона первого экрана не влезает больше 15 цифр, а
// вставка номера поверх подставленного «+7 » не приклеивается к префиксу.
//
// Ассерты идут по РЕАЛЬНОМУ `LoginEntryActions` с его цепочкой форматтеров:
// лимит в 24 символа жил именно в цепочке, а не в маске.
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

  Future<List<String>> pumpEntry(WidgetTester tester) async {
    final submitted = <String>[];
    await tester.pumpWidget(
      wrap(
        LoginEntryActions(
          isLoading: false,
          onRegister: () {},
          onSignIn: () {},
          onSubmitPhone: submitted.add,
          initialCountry: kDefaultPhoneCountry,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return submitted;
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  String digitsOf(String text) => text.replaceAll(RegExp(r'\D'), '');

  testWidgets('AC-1: 16-я цифра не появляется в поле', (tester) async {
    await pumpEntry(tester);

    await tester.enterText(find.byType(TextField), '+7 915 123 45 67 8901');
    await tester.pumpAndSettle();
    final full = fieldText(tester);
    expect(digitsOf(full), '791512345678901');

    await tester.enterText(find.byType(TextField), '${full}2');
    await tester.pumpAndSettle();
    expect(fieldText(tester), full);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AC-2: 16+ цифр одним изменением поле не меняют', (
    tester,
  ) async {
    await pumpEntry(tester);

    for (final long in const [
      '+7 915 123 45 67 89012',
      '+7 915 123 45 67 8901234567',
      '+7 915 123 45 67 8901234567890',
    ]) {
      await tester.enterText(find.byType(TextField), long);
      await tester.pumpAndSettle();
      expect(fieldText(tester), '+7 ', reason: long);
    }
  });

  testWidgets(
    'AC-7: вставка номера поверх «+7 » заменяет префикс, уходит верный номер',
    (tester) async {
      for (final (pasted, e164) in const [
        ('+79151234567', '+79151234567'),
        ('+49 151 12345678', '+4915112345678'),
        ('+491511234567890', '+491511234567890'),
      ]) {
        final submitted = await pumpEntry(tester);
        expect(fieldText(tester), '+7 ');

        // Вставка из буфера в позицию каретки — одно изменение поверх
        // текущего значения, а не замена поля целиком, как у enterText.
        await tester.showKeyboard(find.byType(TextField));
        final text = '+7 $pasted';
        tester.testTextInput.updateEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
        );
        await tester.pumpAndSettle();
        expect(digitsOf(fieldText(tester)), digitsOf(e164), reason: pasted);

        await tester.tap(find.byType(ElevatedButton));
        await tester.pumpAndSettle();
        expect(submitted, [e164], reason: pasted);

        // Свежий экран на следующий кейс.
        await tester.pumpWidget(const SizedBox());
      }
      expect(tester.takeException(), isNull);
    },
  );
}
