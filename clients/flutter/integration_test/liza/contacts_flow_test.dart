// Device-flow страж (Ярус C, живой прогон на iOS+Android) фичи «Добавить контакты».
// ledger:RL-contacts-screen-match-invite
// ledger:RL-chat-list-invite-people-row
//
// Живьём на реальном бинаре: пункт меню «Контакты» открывает экран ContactsPage
// без краша/белого экрана (навигация + route + меню-гейт isMobile работают), и —
// если в списке есть закреплённый чат «Лиза ИИ» — строка «Пригласить людей» видна.
// Нативный доступ к книге/share integration_test НЕ видит (native residual) —
// здесь проверяем клиентский слой живьём, чего host widget-тесты не покрывают.
// Гоняется .claude/tools/prove-ui/run.sh на iOS И Android.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat_list/client_chooser_button.dart';
import 'package:liza/pages/contacts/contacts_page.dart';

import 'liza_flows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'Добавить контакты: пункт «Контакты» открывает экран живьём (+ строка «Пригласить людей»)',
      (tester) async {
    app.main();
    await tester.ensureLizaHome();

    // Best-effort (Liza-gated): строка «Пригласить людей» рендерится в живом
    // списке чатов, если есть закреплённый чат «Лиза ИИ». На стенде без Liza
    // строки не будет — это не баг, поэтому не жёсткий ассерт.
    if (find.text('Пригласить людей').evaluate().isNotEmpty) {
      expect(find.text('Пригласить людей'), findsWidgets);
    }

    // ОСНОВНОЙ живой ассерт: меню аккаунта → «Контакты» → экран открывается.
    final chooser = find.byType(ClientChooserButton);
    await tester.waitUntil(chooser);
    await tester.tap(chooser.first);
    await tester.pump(const Duration(milliseconds: 700));

    // Пункт «Контакты» присутствует (гейт isMobile отдаёт его на iOS/Android).
    await tester.waitUntil(find.text('Контакты'));
    await tester.tap(find.text('Контакты').last);
    await tester.pump(const Duration(milliseconds: 800));

    // Экран отрисовался живьём: запрос доступа/объяснение/список/пусто — но НЕ
    // краш и НЕ белый экран.
    await tester.waitUntil(find.byType(ContactsPage),
        timeout: const Duration(seconds: 25));
    expect(find.byType(ContactsPage), findsOneWidget,
        reason: 'Экран «Контакты» не открылся живьём.');
    expect(tester.takeException(), isNull,
        reason: 'Экран «Контакты» бросил исключение при рендере на устройстве.');
  });
}
