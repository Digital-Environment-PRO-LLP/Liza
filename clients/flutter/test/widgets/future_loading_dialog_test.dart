// ledger:RL-direct-chat-single-flight
// AC:RL-direct-chat-single-flight/6 AC:RL-direct-chat-single-flight/7
// guard.render:real-widget
//
// Два `showFutureLoadingDialog` стеком (двойной клик в 300-мс окне до показа
// первого диалога). До фикса `LoadingDialogState` делал `Navigator.pop` —
// снимал ВЕРХНИЙ (чужой) роут и отдавал ему свой результат, а свой диалог
// висел модально до перезапуска приложения; второй завершался на unmounted
// State с «Null check operator used on a null value» (лог Windows 2026-09-16).
//
// Red-proof (RP-6): откатить future_loading_dialog.dart к
// `Navigator.of(context).pop(...)` → после completerA на экране остаётся диалог
// A (а не B), showFutureLoadingDialog(B) получает результат 'a',
// tester.takeException() — Null check. Проверено на HEAD до фикса.
import 'dart:async';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/widgets/future_loading_dialog.dart';

void main() {
  late BuildContext hostContext;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              hostContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // CircularProgressIndicator крутится бесконечно — pumpAndSettle не сходится.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<Result<String>> open(Completer<String> c, String title) =>
      showFutureLoadingDialog<String>(
        context: hostContext,
        future: () => c.future,
        title: title,
        delay: false,
      );

  testWidgets(
    'AC-6: два диалога стеком, первый завершается раньше → снят именно первый, '
    'результаты свои, без исключений',
    (tester) async {
      await pumpHost(tester);
      final a = Completer<String>();
      final b = Completer<String>();

      final resultA = open(a, 'DIALOG-A');
      final resultB = open(b, 'DIALOG-B');
      await settle(tester);
      expect(find.byType(LoadingDialog<String>), findsNWidgets(2));

      a.complete('a');
      await settle(tester);
      expect(tester.takeException(), isNull);
      // Снят A, B на месте.
      expect(find.text('DIALOG-A'), findsNothing);
      expect(find.text('DIALOG-B'), findsOneWidget);
      expect((await resultA).result, 'a');

      b.complete('b');
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(LoadingDialog<String>), findsNothing);
      expect((await resultB).result, 'b');
    },
  );

  testWidgets(
    'AC-7: первый падает, второй завершается → первый показывает ошибку, '
    'второй закрыт своим результатом, без исключений',
    (tester) async {
      await pumpHost(tester);
      final a = Completer<String>();
      final b = Completer<String>();

      final resultA = open(a, 'DIALOG-A');
      final resultB = open(b, 'DIALOG-B');
      await settle(tester);

      a.completeError(Exception('federation down'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      // Ошибка — в СВОЁМ диалоге (A), B по-прежнему грузится.
      expect(find.byType(LoadingDialog<String>), findsNWidgets(2));
      expect(find.text('DIALOG-B'), findsOneWidget);
      expect(find.text('DIALOG-A'), findsNothing);

      b.complete('b');
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byType(LoadingDialog<String>), findsOneWidget);
      expect((await resultB).result, 'b');

      // «Закрыть» у A → его собственный error-результат.
      await tester.tap(find.byType(TextButton).first);
      await settle(tester);
      expect(find.byType(LoadingDialog<String>), findsNothing);
      expect((await resultA).error, isA<Exception>());
    },
  );
}
