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

  testWidgets('dev-ветка показывает поле телефона, а не кнопку', (tester) async {
    await tester.pumpWidget(
      wrap(
        LoginEntryActions(
          isLoading: false,
          onRegister: () {},
          onSignIn: () {},
          onSubmitPhone: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('прод-ветка показывает две кнопки OIDC', (tester) async {
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
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
  });

  testWidgets('dev-ветка: подпись, пояснение и юр-сноска на месте', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        LoginEntryActions(
          isLoading: false,
          onRegister: () {},
          onSignIn: () {},
          onSubmitPhone: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Введите номер телефона'), findsOneWidget);
    expect(find.text('Отправим код подтверждения для входа'), findsOneWidget);

    final notice = tester.widget<Text>(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.textSpan != null &&
            w.textSpan!.toPlainText().contains('условия использования'),
      ),
    );
    final plain = notice.textSpan!.toPlainText();
    expect(plain, contains('политику конфиденциальности'));
    expect(plain, contains('Продолжить'));
  });

  testWidgets('прод-ветка: юр-сноски и подписи НЕТ', (tester) async {
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

    expect(find.text('Введите номер телефона'), findsNothing);
    expect(find.textContaining('условия использования'), findsNothing);
  });

  testWidgets('код страны подставлен, кнопка ждёт полного номера', (
    tester,
  ) async {
    String? submitted;
    await tester.pumpWidget(
      wrap(
        LoginEntryActions(
          isLoading: false,
          onRegister: () {},
          onSignIn: () {},
          onSubmitPhone: (value) => submitted = value,
          initialCountry: kDefaultPhoneCountry,
        ),
      ),
    );
    await tester.pumpAndSettle();

    ElevatedButton button() =>
        tester.widget<ElevatedButton>(find.byType(ElevatedButton));

    // Поле уже содержит код страны из локали.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '+7 ',
    );
    // Один код страны — не номер, кнопка заблокирована.
    expect(button().onPressed, isNull);

    await tester.enterText(find.byType(TextField), '+7 999');
    await tester.pumpAndSettle();
    expect(button().onPressed, isNull);

    await tester.enterText(find.byType(TextField), '+7 999 123-45-67');
    await tester.pumpAndSettle();
    expect(button().onPressed, isNotNull);

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    // Разделители срезаются, на сервер уходит E.164.
    expect(submitted, '+79991234567');
  });

  testWidgets('иностранный номер принимается', (tester) async {
    String? submitted;
    await tester.pumpWidget(
      wrap(
        LoginEntryActions(
          isLoading: false,
          onRegister: () {},
          onSignIn: () {},
          onSubmitPhone: (value) => submitted = value,
          initialCountry: kDefaultPhoneCountry,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Код страны стёрли и вписали свой — жёсткой привязки к +7 больше нет.
    await tester.enterText(find.byType(TextField), '+995 555 12-34-56');
    await tester.pumpAndSettle();

    await tester.tap(find.byType(ElevatedButton));
    await tester.pumpAndSettle();
    expect(submitted, '+995555123456');
  });

  testWidgets('плейсхолдер заметно бледнее введённого текста', (tester) async {
    await tester.pumpWidget(
      wrap(
        LoginEntryActions(
          isLoading: false,
          onRegister: () {},
          onSignIn: () {},
          onSubmitPhone: (_) {},
          initialCountry: kDefaultPhoneCountry,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    final hintColor = field.decoration!.hintStyle!.color!;
    final textColor = field.style?.color;

    // Непрозрачность подсказки заметно ниже — раньше её принимали за
    // уже введённый номер.
    expect(hintColor.a, lessThan(0.5));
    if (textColor != null) expect(hintColor.a, lessThan(textColor.a));
  });
}
