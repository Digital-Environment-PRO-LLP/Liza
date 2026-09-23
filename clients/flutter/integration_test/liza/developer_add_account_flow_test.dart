// Device-flow страж (Ярус C, живой прогон): developer-пункты меню аккаунта —
// строго роль «Разработчик», и разработчик РЕАЛЬНО добавляет второй аккаунт.
// ledger:RL-developer-gates-strict
//
// Гейт — `UserRoleService.isCurrentUserDeveloper` (строго `developer`). 21–22.09
// гейт открывали и роли `admin` — откатили по решению владельца: «Добавить
// аккаунт» с 2026-05-15 только разработчикам (a7608de1). Host-тест держит
// предикат; здесь — что роль доезжает до меню на устройстве, а мультиаккаунт у
// разработчика доходит до конца: вход вторым аккаунтом → экран входа закрыт →
// оба аккаунта в меню.
//
// ⚠️ Оракул видимости — «Приложения» (`miniAppCatalogTitle`), а НЕ «Добавить
// аккаунт»: у второго поблажка `|| AppConfig.isLocal`, на локальном стенде он
// виден при ЛЮБОЙ роли и дал бы ложно-зелёный.
//
// Роль аккаунта задаёт стенд, тест сверяется с фактической:
//   curl -k -X PUT https://synapse.liza.local/_synapse/client/roles/v1/role/<mxid> \
//        -H "Authorization: Bearer <admin-token>" -d '{"role":"developer"}'

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat_list/chat_list_body.dart';
import 'package:liza/pages/chat_list/client_chooser_button.dart';
import 'package:liza/pages/login/login_view.dart';
import 'package:liza/utils/user_role_service.dart';
import 'package:liza/widgets/liza_app.dart';
import 'package:liza/widgets/matrix.dart';

import 'e2e_config.dart';
import 'liza_flows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'разработчик видит developer-пункты и добавляет второй аккаунт; остальные роли — нет',
    (tester) async {
      app.main();
      await _ensureHomePastBootstrap(tester);

      final chooser = find.byType(ClientChooserButton);
      await tester.waitUntil(chooser);

      final matrix = Matrix.of(tester.element(chooser.first));
      final roles = matrix.userRoleService;
      final firstUserId = matrix.client.userID!;
      await roles.fetchRoles([firstUserId]);
      final code = roles.getRole(firstUserId)?.code;
      final internal = code == UserRoleService.developerRole;

      await tester.tap(chooser.first);
      await tester.pump(const Duration(milliseconds: 700));

      final apps = find.text('Приложения');
      if (!internal) {
        expect(
          apps,
          findsNothing,
          reason:
              'роль $code — не «Разработчик» (в т.ч. admin): developer-пункты '
              'ей не показываем [AC:RL-developer-gates-strict/3]',
        );
        expect(tester.takeException(), isNull);
        return;
      }

      await tester.waitUntil(apps);
      expect(
        apps,
        findsWidgets,
        reason:
            'разработчик обязан видеть developer-пункты меню '
            '[AC:RL-developer-gates-strict/1]',
      );

      // Второй аккаунт доводим до конца: пункт → экран входа → логин → в меню
      // два аккаунта. Видимость пункта сама по себе ничего не доказывает.
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
      await tester.enterText(fields.at(0), E2eConfig.userB.name);
      await tester.pump();
      await tester.enterText(fields.at(1), E2eConfig.userB.password);
      await tester.pump();
      final loginButton = find.descendant(
        of: find.byType(LoginView),
        matching: find.byType(ElevatedButton),
      );
      await _dismissOverlays(tester);
      // Роль developer: список чатов под экраном входа показывает плашку
      // «Один из ваших сеансов не подтверждён» (chat_list.dart), вместе с
      // клавиатурой она закрывает «Войти». Закрываем как человек — крестиком.
      final snackClose = find.descendant(
        of: find.byType(SnackBar),
        matching: find.byIcon(Icons.close),
      );
      if (snackClose.evaluate().isNotEmpty) {
        await tester.tap(snackClose.first);
        await tester.pump(const Duration(milliseconds: 500));
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.ensureVisible(loginButton);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(loginButton);

      // Второй клиент появляется в бандлах — это и есть «аккаунт добавлен».
      final end = DateTime.now().add(const Duration(seconds: 120));
      var loggedInIds = <String>{};
      while (DateTime.now().isBefore(end)) {
        loggedInIds = matrix.widget.clients
            .where((c) => c.isLogged())
            .map((c) => c.userID!)
            .toSet();
        if (loggedInIds.length >= 2) break;
        await tester.pump(const Duration(milliseconds: 200));
      }

      expect(
        loggedInIds.length,
        greaterThanOrEqualTo(2),
        reason:
            'второй аккаунт не добавился: вошли только $loggedInIds. Роль $code '
            'видит пункт, но мультиаккаунт не доходит до конца',
      );
      expect(
        loggedInIds,
        contains(firstUserId),
        reason: 'первый аккаунт пропал при добавлении второго',
      );

      // Видимый эффект: экран входа закрылся, человек вернулся в список чатов.
      // Раньше навигация падала («Future already completed») и экран входа
      // оставался на месте, хотя аккаунт уже добавился.
      final leaveEnd = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(leaveEnd) &&
          find.byType(LoginView).evaluate().isNotEmpty) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(
        find.byType(LoginView),
        findsNothing,
        reason:
            'после входа вторым аккаунтом экран входа не закрылся '
            '[AC:RL-developer-gates-strict/4]',
      );
      await tester.waitUntil(
        find.byType(ChatListViewBody),
        timeout: const Duration(seconds: 30),
      );

      // И в меню аккаунта теперь оба аккаунта — переключение доступно.
      // Переход на список чатов ещё может анимироваться: открываем меню, пока
      // не появится его постоянный пункт «Архив».
      await tester.pump(const Duration(seconds: 2));
      final menuMarker = find.text('Архив');
      for (var i = 0; i < 5 && menuMarker.evaluate().isEmpty; i++) {
        await tester.tap(find.byType(ClientChooserButton).first);
        await tester.pump(const Duration(milliseconds: 900));
      }
      await tester.waitUntil(menuMarker);
      await tester.waitUntil(find.text(E2eConfig.userB.name));
      expect(
        find.text(E2eConfig.userB.name),
        findsWidgets,
        reason: 'второй аккаунт не появился в меню переключения',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

/// Роль `developer` после входа штатно попадает на экран ключа восстановления
/// (`/backup`) — `ensureLizaHome` ждёт список чатов и на нём застревает. Этот
/// тест про мультиаккаунт, поэтому шаг ключей пропускаем переходом на `/rooms`
/// (тот же путь, что у кнопки «Пропустить» этого экрана).
Future<void> _ensureHomePastBootstrap(WidgetTester tester) async {
  try {
    await tester.ensureLizaHome(timeout: const Duration(seconds: 30));
    return;
  } on Exception {
    // упёрлись в экран ключа — ниже
  }
  LizaApp.router.go('/rooms');
  await tester.pump(const Duration(milliseconds: 500));
  await tester.waitUntil(
    find.byType(ChatListViewBody),
    timeout: const Duration(seconds: 60),
  );
  await _dismissOverlays(tester);
}

/// Предупреждение о пушах (debug без push-провайдера) перекрывает кнопки;
/// `ensureLizaHome` закрывает его сам, а обходной путь выше — нет.
Future<void> _dismissOverlays(WidgetTester tester) async {
  final end = DateTime.now().add(const Duration(seconds: 4));
  while (DateTime.now().isBefore(end)) {
    final dismiss = find.text('Больше не показывать');
    if (dismiss.evaluate().isNotEmpty) {
      await tester.tap(dismiss.first);
      await tester.pump(const Duration(milliseconds: 300));
      return;
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}
