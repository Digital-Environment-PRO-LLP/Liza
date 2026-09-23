// ledger:RL-forwarded-attribution
// AC-2/AC-3 на РЕАЛЬНОМ прод-виджете ForwardedContent (не реплике), изолированно
// и без Matrix Client — стабильное покрытие текста плашки: имя есть → «Переслано
// от X», имени нет/пусто → голое «Переслано».

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/forwarded_content.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(body: Center(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // AC:RL-forwarded-attribution/2
  testWidgets('AC-2 имя есть → «Переслано от <Имя>»', (tester) async {
    await _pump(tester, const ForwardedContent(name: 'Иван Петров'));
    expect(find.text('Переслано от Иван Петров'), findsOneWidget);
    expect(find.byIcon(Icons.forward_outlined), findsOneWidget);
  });

  // AC:RL-forwarded-attribution/3
  testWidgets('AC-3 имя null → голое «Переслано»', (tester) async {
    await _pump(tester, const ForwardedContent(name: null));
    expect(find.text('Переслано'), findsOneWidget);
    expect(find.textContaining('от'), findsNothing);
  });

  testWidgets('AC-3 имя из пробелов → голое «Переслано» (не пустая строка)', (
    tester,
  ) async {
    await _pump(tester, const ForwardedContent(name: '   '));
    expect(find.text('Переслано'), findsOneWidget);
  });

  testWidgets('своё пересланное тоже несёт плашку (ownMessage)', (tester) async {
    await _pump(
      tester,
      const ForwardedContent(name: 'Иван Петров', ownMessage: true),
    );
    expect(find.text('Переслано от Иван Петров'), findsOneWidget);
  });
}
