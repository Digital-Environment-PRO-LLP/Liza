// Device-flow страж: вход через «Добавить аккаунт» тем же аккаунтом, что уже
// открыт, не «выкидывает» молча в список чатов.
// ledger:RL-add-account-phone-stays-in-flow
//
// Жалоба (2026-09-23, @maksim.korolev:liza.cyber-agro.ru): «Добавить аккаунт»
// → номер телефона СВОЕГО аккаунта → выкидывает из приложения. Телефонный
// маршрут закрыт host-стражем `test/add_account_phone_test.dart` (на стенде
// APP_ENV=local входа по телефону нет). Здесь — общая для телефона и пароля
// развилка в `Matrix.getLoginClient`: дубль сворачивает стек добавления и
// ГОВОРИТ, что аккаунт уже добавлен, второй копии не заводит.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat_list/chat_list_body.dart';
import 'package:liza/pages/chat_list/client_chooser_button.dart';
import 'package:liza/pages/homeserver_picker/homeserver_picker.dart';
import 'package:liza/pages/login/login_view.dart';
import 'package:liza/widgets/matrix.dart';

import 'e2e_config.dart';
import 'liza_flows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('вход уже открытым аккаунтом: сообщение, экран входа закрыт, '
      'копии аккаунта нет', (tester) async {
    app.main();
    await tester.ensureLizaHome(timeout: const Duration(seconds: 90));

    final chooser = find.byType(ClientChooserButton);
    await tester.waitUntil(chooser);
    final matrix = Matrix.of(tester.element(chooser.first));
    final me = matrix.client.userID!;
    final user = [
      E2eConfig.userA,
      E2eConfig.userB,
      E2eConfig.userC,
    ].firstWhere((u) => me.startsWith('@${u.name}:'));
    int loggedIn() => matrix.widget.clients.where((c) => c.isLogged()).length;
    final before = loggedIn();

    await tester.tap(chooser.first);
    await tester.pump(const Duration(milliseconds: 700));
    final addAccount = find.text('Добавить аккаунт');
    await tester.waitUntil(addAccount);
    await tester.tap(addAccount.last);
    await tester.pump(const Duration(milliseconds: 800));

    await tester.waitUntil(find.text('Локальный сервер (пароль)'));
    await tester.tap(find.text('Локальный сервер (пароль)'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.waitUntil(find.byType(LoginView));
    await tester.pump(const Duration(milliseconds: 300));

    final fields = find.descendant(
      of: find.byType(LoginView),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), user.name);
    await tester.pump();
    await tester.enterText(fields.at(1), user.password);
    await tester.pump();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump(const Duration(milliseconds: 500));
    final loginButton = find.descendant(
      of: find.byType(LoginView),
      matching: find.byType(ElevatedButton),
    );
    await tester.ensureVisible(loginButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(loginButton);

    // AC:RL-add-account-phone-stays-in-flow/5
    await tester.waitUntil(
      find.text('Этот аккаунт уже добавлен'),
      timeout: const Duration(seconds: 60),
    );
    final leaveEnd = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(leaveEnd) &&
        (find.byType(LoginView).evaluate().isNotEmpty ||
            find.byType(HomeserverPicker).evaluate().isNotEmpty)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(
      find.byType(LoginView),
      findsNothing,
      reason: 'экран входа остался поверх списка чатов',
    );
    expect(
      find.byType(HomeserverPicker),
      findsNothing,
      reason: 'экран «Добавить аккаунт» остался поверх списка чатов',
    );
    await tester.waitUntil(
      find.byType(ChatListViewBody),
      timeout: const Duration(seconds: 30),
    );
    expect(
      loggedIn(),
      before,
      reason: 'вход тем же аккаунтом завёл его копию',
    );
    expect(matrix.client.userID, me);
    expect(tester.takeException(), isNull);
  });
}
