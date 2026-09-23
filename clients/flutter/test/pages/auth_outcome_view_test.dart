// ledger:RL-auth-orphan-after-oidc
// AC:RL-auth-orphan-after-oidc/3 AC:RL-auth-orphan-after-oidc/4
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/homeserver_picker/auth_outcome_view.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('ru'),
    home: Scaffold(body: child),
  );

  test('коды ошибок сервера мапятся на исходы', () {
    expect(
      authOutcomeFromErrorCode('access_not_granted'),
      AuthOutcome.accessNotGranted,
    );
    expect(
      authOutcomeFromErrorCode('invite_invalid'),
      AuthOutcome.inviteInvalid,
    );
    expect(authOutcomeFromErrorCode('something_else'), isNull);
    expect(authOutcomeFromErrorCode(null), isNull);
  });

  testWidgets('AC-3: сирота — текст без доступа и кнопка заявки', (
    tester,
  ) async {
    var tapped = 0;
    await tester.pumpWidget(
      wrap(
        AuthOutcomeView(
          outcome: AuthOutcome.accessNotGranted,
          requestAccessUrl: 'https://forms.example/x',
          onRequestAccess: () => tapped++,
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Упс, у вас нет доступа!'), findsOneWidget);
    expect(find.textContaining('Хотите создавать сообщества'), findsOneWidget);
    expect(find.text('Оставить заявку'), findsOneWidget);

    await tester.tap(find.text('Оставить заявку'));
    expect(tapped, 1);
  });

  testWidgets('AC-3: без requestAccessUrl кнопки заявки нет', (tester) async {
    await tester.pumpWidget(
      wrap(
        AuthOutcomeView(
          outcome: AuthOutcome.accessNotGranted,
          requestAccessUrl: null,
          onRequestAccess: () {},
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Упс, у вас нет доступа!'), findsOneWidget);
    expect(find.text('Оставить заявку'), findsNothing);
  });

  testWidgets('AC-3: пустой requestAccessUrl — кнопки заявки тоже нет',
      (tester) async {
    // Пустая строка — осознанный ответ version-gate «кнопку скрыть», не то же
    // самое, что null. Кнопка на пустой URL вела бы в никуда:
    // requestAccessAction молча вернётся, клик остался бы без реакции.
    await tester.pumpWidget(
      wrap(
        AuthOutcomeView(
          outcome: AuthOutcome.accessNotGranted,
          requestAccessUrl: '',
          onRequestAccess: () {},
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Упс, у вас нет доступа!'), findsOneWidget);
    expect(find.text('Оставить заявку'), findsNothing);
  });

  testWidgets('AC-4: невалидная ссылка — свой текст, без кнопки заявки', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AuthOutcomeView(
          outcome: AuthOutcome.inviteInvalid,
          requestAccessUrl: 'https://forms.example/x',
          onRequestAccess: () {},
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('больше не действует'), findsOneWidget);
    // Невалидная ссылка — это НЕ «нет доступа»: тексты не смешиваются.
    expect(find.textContaining('Упс, у вас нет доступа!'), findsNothing);
    expect(find.text('Оставить заявку'), findsNothing);
  });
}
