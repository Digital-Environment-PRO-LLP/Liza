// Device-flow страж ledger:RL-composer-bot-command-passthrough (Ярус C, живой ввод).
//
// Регресс инцидента /miniapp-constraction: НАБРАННАЯ в композере команда
// бота-ассистента должна уходить боту, а НЕ резаться клиентским диалогом
// «Недопустимая команда». Это ловит ТОЛЬКО живой ввод на реальном бинаре —
// ни golden, ни pure-function-стражи шов клиент↔сервер не видят.
//
// Гейт команды (chat.dart send()) чат-независим → используем ЛЮБОЙ живой чат
// (@support, открывается меню→«Поддержка» — проверенный путь support_test).
// Требует локального стека (make local-up) + APP_ENV=local + E2E_HOMESERVER на
// Android. Гоняется оркестратором .claude/tools/prove-ui/run.sh на iOS И Android.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';
import 'package:liza/pages/chat/input_bar.dart';
import 'package:liza/pages/chat_list/client_chooser_button.dart';

import 'liza_flows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Композер: /miniapp-constraction уходит боту, НЕ «Недопустимая команда»',
      (tester) async {
    app.main();
    await tester.ensureLizaHome();

    // Открыть живой чат (@support) через меню аккаунта — проверенный путь.
    final chooser = find.byType(ClientChooserButton);
    await tester.waitUntil(chooser);
    await tester.tap(chooser.first);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.waitUntil(find.text('Поддержка'));
    await tester.tap(find.text('Поддержка').last);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.waitUntil(find.byType(ChatView),
        timeout: const Duration(seconds: 40));

    // Ввести команду в композер (InputBar → TextField) и отправить.
    final input =
        find.descendant(of: find.byType(InputBar), matching: find.byType(TextField));
    await tester.waitUntil(input);
    await tester.enterText(input.first, '/miniapp-constraction');
    await tester.pump(const Duration(milliseconds: 400));

    await tester.waitUntil(find.byIcon(Icons.send_outlined));
    // Тапаем IconButton-обёртку (большая hit-зона), а не голую иконку у края —
    // на live-биндинге центр иконки капризен к hit-test.
    final sendBtn = find.ancestor(
      of: find.byIcon(Icons.send_outlined),
      matching: find.byType(IconButton),
    );
    await tester.tap(sendBtn.first, warnIfMissed: false);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    // КЛЮЧЕВОЙ (и единственный корректный) ассерт инцидента: клиент НЕ показал
    // диалог «Недопустимая команда». Если бы гейт композера зарезал команду
    // (баг до фикса) — диалог всплыл бы, и команда не ушла бы боту. Его
    // отсутствие = команда классифицирована как bot-команда и отправлена.
    // (Проверять «поле очистилось» через find.text нельзя: успешно отправленная
    //  команда рендерится пузырём в ленте с тем же текстом.)
    expect(find.text('Недопустимая команда'), findsNothing,
        reason: 'Клиент зарезал /miniapp-constraction диалогом commandInvalid — '
            'команда не дошла до бота (регресс инцидента).');
    // Диалог commandInvalid показывается как AlertDialog — его точно нет.
    expect(find.byType(AlertDialog), findsNothing,
        reason: 'Всплыл диалог поверх чата — вероятно commandInvalid.');
  });
}
