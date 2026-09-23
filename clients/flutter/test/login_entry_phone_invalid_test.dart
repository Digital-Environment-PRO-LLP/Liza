// ledger:RL-login-phone-invalid-inline
// AC:RL-login-phone-invalid-inline/1 AC:RL-login-phone-invalid-inline/2
// AC:RL-login-phone-invalid-inline/3 AC:RL-login-phone-invalid-inline/4
// AC:RL-login-phone-invalid-inline/5 AC:RL-login-phone-invalid-inline/6
//
// LABA-2531: номер проверяется на ПЕРВОМ экране, отказ показывается там же.
//
// Ассерты идут по РЕАЛЬНОМУ виджету `LoginEntryActions` и реальной цепочке
// форматтеров — реплика раскладки не поймала бы ни маску, ни навигацию.
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

  group('AC-1/AC-5/AC-6 — normalizeToE164 как зеркало сервера', () {
    test('AC-1: номер из тикета не проходит', () {
      // `000` не существует как код страны — сервер отвечает 400
      // invalid_phone, клиент обязан сказать это сам.
      expect(normalizeToE164('+00000000'), isNull);
      expect(normalizeToE164('+0'), isNull);
      expect(normalizeToE164('+99912345678'), isNull);
    });

    test('AC-5: клиент НЕ строже сервера', () {
      // Каждый из этих номеров сервер принимает (10–15 цифр + существующий
      // код страны), значит клиент не имеет права отвергнуть: ложный отказ
      // означает, что человек не войдёт вовсе и обойти это ему нечем.
      // Кейсы 972/375 — red-proof против гейта на `isValid()`: парсер
      // считает эти живые мобильные невалидными.
      //
      // Пересмотрен LABA-2527 (2026-09-14): прежний список содержал
      // `+11111111`, `+79991234` (8 цифр) и `+247123456` (9) — контракт
      // LABA-2531 не учитывал границу Keycloak (`phone` min 10), и такие
      // номера доходили до `/complete`, где падали как «сервис недоступен».
      // Теперь сервер их тоже отвергает; смысл AC-5 (анти-`isValid`)
      // держится на 10+-значных кейсах ниже.
      expect(normalizeToE164('+4512345678'), '+4512345678');
      expect(normalizeToE164('+4930901820'), '+4930901820');
      expect(normalizeToE164('+375251234567'), '+375251234567');
      expect(normalizeToE164('+972581234567'), '+972581234567');
      expect(normalizeToE164('+972501234567'), '+972501234567');
      // И прежние, ради которых снимали привязку к РФ.
      expect(normalizeToE164('+7 (999) 123-45-67'), '+79991234567');
      expect(normalizeToE164('+995 555 12-34-56'), '+995555123456');
      expect(normalizeToE164('+1 201 555-0123'), '+12015550123');
    });

    test(
      'AC-6: национальные формы разбираются, а не уезжают в чужую страну',
      () {
        // Поле предзаполнено «+7 », и россиянин по привычке набирает «8 915…»
        // поверх. Раньше уходило `+789151234567`: сервер принимал его (код 7,
        // длина в диапазоне) и слал СМС в никуда — тихо, без ошибки.
        expect(normalizeToE164('+7 891 512 345 67'), '+79151234567');
        expect(normalizeToE164('+7 880 055 535 35'), '+78005553535');
        // Префикс стёрли и набрали национальную форму.
        expect(normalizeToE164('89151234567'), '+79151234567');
        // Раньше уезжало в Индию: `+91` — реальный код страны.
        expect(normalizeToE164('9151234567'), '+79151234567');
        // `00` — международный префикс набора (европейский аналог `+`).
        expect(normalizeToE164('007 999 123 45 67'), '+79991234567');
      },
    );
  });

  group('AC-2/AC-3/AC-4 — отказ виден на первом экране', () {
    testWidgets('AC-2+AC-3: +00000000 не уводит с экрана и объясняет почему', (
      tester,
    ) async {
      var submitted = 0;
      await tester.pumpWidget(
        wrap(
          LoginEntryActions(
            isLoading: false,
            onRegister: () {},
            onSignIn: () {},
            // Вызов колбэка = переход на /auth/phone (экран ожидания
            // кода): именно его тикет требует не допускать.
            onSubmitPhone: (_) => submitted++,
            initialCountry: kDefaultPhoneCountry,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '+00000000');
      await tester.pumpAndSettle();

      // Кнопка ОСТАЁТСЯ активной: серая кнопка не объясняет, что не так.
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();

      // AC-2: перехода на шаг ожидания кода не произошло.
      expect(submitted, 0);
      // AC-3: причина названа здесь же. Ищем по русской строке — так тест
      // заодно ловит пропажу перевода в intl_ru.arb.
      expect(find.text('Введите корректный номер телефона'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('AC-4: правка номера убирает прежний отказ', (tester) async {
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

      await tester.enterText(find.byType(TextField), '+00000000');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(find.text('Введите корректный номер телефона'), findsOneWidget);

      // Человек исправляет номер — старый отказ больше не про него.
      await tester.enterText(find.byType(TextField), '+7 999 123-45-67');
      await tester.pumpAndSettle();
      expect(find.text('Введите корректный номер телефона'), findsNothing);

      await tester.tap(find.byType(ElevatedButton));
      await tester.pumpAndSettle();
      expect(submitted, 1);
    });

    testWidgets('прод-ветка не знает ни поля, ни отказа', (tester) async {
      await tester.pumpWidget(
        wrap(
          LoginEntryActions(
            isLoading: false,
            onRegister: () {},
            onSignIn: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Введите корректный номер телефона'), findsNothing);
    });
  });
}
