import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/settings_email/settings_email.dart';
import 'package:liza/pages/settings_email/settings_email_view.dart';

void main() {
  testWidgets('шаг ввода почты объясняет, зачем она нужна', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ru'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: SettingsEmailReason()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Введите свой email. Резервный способ, если код для входа не '
        'придёт по SMS',
      ),
      findsOneWidget,
    );
  });

  testWidgets('подпись рендерится на реальном виджете, когда её показывают', (
    tester,
  ) async {
    // Реальный SettingsEmailReason внутри условия из shouldShowEmailReason:
    // так проверяется связка «предикат → показанный текст», а не только
    // предикат сам по себе.
    const state = AccountEmailState(maskedEmail: null, verified: false);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              if (shouldShowEmailReason(state)) const SettingsEmailReason(),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SettingsEmailReason), findsOneWidget);
  });

  testWidgets('при подтверждённой почте подпись не рендерится', (tester) async {
    const state = AccountEmailState(
      maskedEmail: 'i***n@example.com',
      verified: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              if (shouldShowEmailReason(state)) const SettingsEmailReason(),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SettingsEmailReason), findsNothing);
  });

  group('видимость обоснования почты', () {
    // Правило одно на оба шага экрана, поэтому проверяем сам предикат:
    // подпись нужна лишь тому, у кого запасного входа ещё нет.
    test('почта не подтверждена — подпись показываем', () {
      const state = AccountEmailState(maskedEmail: null, verified: false);
      expect(shouldShowEmailReason(state), isTrue);
    });

    test('почта есть, но не подтверждена — подпись показываем', () {
      const state = AccountEmailState(
        maskedEmail: 'i***n@example.com',
        verified: false,
      );
      expect(shouldShowEmailReason(state), isTrue);
    });

    test('почта подтверждена — подписи нет', () {
      const state = AccountEmailState(
        maskedEmail: 'i***n@example.com',
        verified: true,
      );
      expect(shouldShowEmailReason(state), isFalse);
    });

    test('состояние ещё грузится — подпись не мигает', () {
      expect(shouldShowEmailReason(null), isFalse);
    });
  });

  test('оба шага экрана применяют условие видимости', () {
    // Рендер-тесты выше проверяют связку на собранной вручную колонке; этот
    // ассерт стережёт, что сам экран не показывает подпись безусловно.
    final src =
        File('lib/pages/settings_email/settings_email_view.dart')
            .readAsStringSync();
    expect(
      src.contains('shouldShowEmailReason(state)'),
      isTrue,
      reason: 'шаг overview должен показывать подпись через предикат',
    );
    expect(
      src.contains('if (state?.verified != true)'),
      isTrue,
      reason: 'шаг ввода почты должен скрывать подпись при верифицированной почте',
    );
  });

  group('AccountEmailState', () {
    test('нет почты — не подтверждена', () {
      const state = AccountEmailState(maskedEmail: null, verified: false);
      expect(state.hasEmail, isFalse);
    });

    test('есть маска — считается привязанной', () {
      const state = AccountEmailState(
        maskedEmail: 'i***n@example.com',
        verified: true,
      );
      expect(state.hasEmail, isTrue);
    });

    test('разбор ответа сервера', () {
      final state = AccountEmailState.fromJson({
        'email_masked': 'i***n@example.com',
        'verified': true,
      });
      expect(state.maskedEmail, 'i***n@example.com');
      expect(state.verified, isTrue);
    });

    test('пустой ответ — почты нет', () {
      final state = AccountEmailState.fromJson({});
      expect(state.hasEmail, isFalse);
      expect(state.verified, isFalse);
    });
  });
}
