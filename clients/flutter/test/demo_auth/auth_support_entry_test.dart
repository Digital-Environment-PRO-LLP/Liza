import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/demo_auth_flow.dart';
import 'package:liza/pages/demo_auth/widgets/demo_auth_scaffold.dart';
import 'package:liza/pages/demo_auth/widgets/otp_actions_row.dart';

/// Поддержка должна оставаться достижимой после удаления иконки «?» из
/// AppBar: иначе человек, у которого код не приходит, упирается в тупик.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: child,
      );

  testWidgets('иконки «?» в AppBar больше нет', (tester) async {
    await tester.pumpWidget(
      wrap(
        const DemoAuthScaffold(
          title: 'Код подтверждения',
          child: SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.help_outline), findsNothing);
  });

  testWidgets('поддержка доступна кнопкой внизу экрана', (tester) async {
    await tester.pumpWidget(
      wrap(
        const DemoAuthScaffold(
          title: 'Код подтверждения',
          child: SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Написать в поддержку'), findsOneWidget);

    await tester.tap(find.text('Написать в поддержку'));
    await tester.pumpAndSettle();
    // Открылась форма обращения: обратный адрес и текст.
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('тупиковая ошибка по-прежнему выводит в поддержку', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const DemoAuthScaffold(
          title: 'Код подтверждения',
          error: 'Попытки исчерпаны',
          errorCode: 'otp_attempts_exhausted',
          child: SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Кнопка ошибки плюс постоянная внизу.
    expect(find.text('Написать в поддержку'), findsNWidgets(2));
  });

  group('OtpActionsRow', () {
    testWidgets('«Другой способ» скрыт, когда альтернативы нет', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const Scaffold(body: OtpActionsRow(step: 'sms'))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Другой способ'), findsNothing);
      expect(find.text('Написать в поддержку'), findsOneWidget);
    });

    testWidgets('«Другой способ» появляется при доступной альтернативе', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: OtpActionsRow(
              step: 'sms',
              channels: DemoAuthChannel.values,
              currentChannel: DemoAuthChannel.phone,
              onSelectChannel: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Другой способ'), findsOneWidget);
    });

    testWidgets('клик по «Другой способ» открывает меню, а не переключает', (
      tester,
    ) async {
      // Регресс прежнего поведения: кнопка была плоским тумблером и слала
      // код по «другому» каналу сразу по нажатию. Теперь она обязана лишь
      // ОТКРЫТЬ выбор — отправка уходит по клику на конкретный способ.
      DemoAuthChannel? picked;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: OtpActionsRow(
              step: 'sms',
              channels: DemoAuthChannel.values,
              currentChannel: DemoAuthChannel.phone,
              onSelectChannel: (channel) => picked = channel,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Другой способ'));
      await tester.pumpAndSettle();

      expect(picked, isNull, reason: 'открытие меню ничего не отправляет');
      expect(find.text('Как отправить код'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      // Текущий способ помечен, а не спрятан: список сразу читается как
      // выбор, и видно, чем человек пользуется сейчас.
      expect(find.text('СМС-код — сейчас'), findsOneWidget);
    });

    testWidgets('переключение происходит по клику на конкретный способ', (
      tester,
    ) async {
      DemoAuthChannel? picked;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: OtpActionsRow(
              step: 'sms',
              channels: DemoAuthChannel.values,
              currentChannel: DemoAuthChannel.phone,
              onSelectChannel: (channel) => picked = channel,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Другой способ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Email'));
      await tester.pumpAndSettle();

      expect(picked, DemoAuthChannel.email);
    });

    testWidgets('ряд кнопок легче текста таймера над ним', (tester) async {
      // Иерархия экрана кода: таймер «Отправить повторно через N с» —
      // главный текст, ряд действий под ним второстепенен. Сравниваем
      // фактические кегли, а не «на глаз».
      late double timerSize;
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: Builder(
              builder: (context) {
                final theme = Theme.of(context);
                timerSize = theme.textTheme.bodyMedium!.fontSize!;
                return const OtpActionsRow(step: 'sms');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final label = tester.widget<Text>(find.text('Написать в поддержку'));
      final buttonStyle = DefaultTextStyle.of(
        tester.element(find.text('Написать в поддержку')),
      ).style;
      final buttonSize = label.style?.fontSize ?? buttonStyle.fontSize!;
      expect(
        buttonSize,
        lessThan(timerSize),
        reason: 'кнопки должны читаться легче таймера',
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.support_agent));
      expect(icon.size, lessThan(18.0), reason: 'иконки уменьшены согласованно');
    });
  });

  testWidgets(
    'на экране кода кнопка поддержки одна, а не две подряд',
    (tester) async {
      // Регресс: каркас рисовал постоянную кнопку внизу, а OtpActionsRow —
      // такую же под полем кода. На экране кода это одно и то же место,
      // и пользователь видел «Написать в поддержку» дважды встык.
      await tester.pumpWidget(
        wrap(
          const DemoAuthScaffold(
            title: 'Код подтверждения',
            step: 'email',
            showBottomSupport: false,
            child: OtpActionsRow(step: 'email'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Написать в поддержку'), findsOneWidget);
    },
  );

  testWidgets('вне экранов кода нижняя кнопка остаётся', (tester) async {
    await tester.pumpWidget(
      wrap(
        const DemoAuthScaffold(
          title: 'Выбор сервера',
          child: SizedBox.shrink(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Написать в поддержку'), findsOneWidget);
  });
}
