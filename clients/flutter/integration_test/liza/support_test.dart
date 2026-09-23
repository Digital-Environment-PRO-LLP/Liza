import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';
import 'package:liza/pages/chat_list/client_chooser_button.dart';

import 'liza_flows.dart';

/// E2E службы поддержки на РЕАЛЬНОМ бинаре: пункт меню «Поддержка» открывает чат
/// с ботом @support, живой бот на локальном стенде ведёт диалог.
///
/// Требует запущенного локального стека + бота @support (support/run_local.py)
/// и `adb reverse tcp:8008 tcp:8008` на Android. Логин UI — testuser/testpass
/// через «Локальный сервер (пароль)» (ensureLizaHome).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Поддержка: меню → чат с @support → живой диалог', (tester) async {
    app.main();
    await tester.ensureLizaHome();

    // Открыть меню аккаунта (аватар сверху — ClientChooserButton) и «Поддержка».
    final chooser = find.byType(ClientChooserButton);
    await tester.waitUntil(chooser);
    await tester.tap(chooser.first);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.waitUntil(find.text('Поддержка'));
    await tester.tap(find.text('Поддержка').last);
    await tester.pump(const Duration(milliseconds: 700));

    // Открылся чат с ботом поддержки.
    await tester.waitUntil(
      find.byType(ChatView),
      timeout: const Duration(seconds: 40),
    );

    // Живой бот @support поприветствовал пользователя (сообщение отрендерено в чате).
    await tester.waitUntil(
      find.textContaining('Опишите ваш вопрос', findRichText: true),
      timeout: const Duration(seconds: 90),
    );
  });
}
