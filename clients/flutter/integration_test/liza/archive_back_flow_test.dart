import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat_list/chat_list_body.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'liza_flows.dart';

/// Страж РЕГРЕССИИ (ledger:RL-archive-chat-back-to-archive), LABA-2543.
/// AC:RL-archive-chat-back-to-archive/9
/// AC:RL-archive-chat-back-to-archive/10
///
/// Сквозная проверка на устройстве: из АРХИВНОГО чата в КОЛОНОЧНОМ режиме есть
/// стрелка «назад», и она возвращает в НЕПУСТОЙ список архива.
///
/// ⚠️ КЛАСС ДЕФЕКТА ВОСПРОИЗВОДИТСЯ ТОЛЬКО ШИРЕ 840dp
/// (`LizaThemes.isColumnModeByWidth` = 380*2 + 80). Телефонный сим/AVD в
/// портрете даёт 360–440dp → узкая ветка `leading`, где кнопка была всегда →
/// прогон БЕЗ форсирования вьюпорта ложно-зелёный и НЕ засчитывается (AC-9).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Liza e2e: возврат из архивного чата в архив (LABA-2543)', () {
    testWidgets('колоночный режим: стрелка ведёт в непустой список архива', (
      tester,
    ) async {
      // AC-9 — ПЕРВЫМ делом: без колоночного вьюпорта тест проверяет не тот
      // класс дефекта.
      final dpr = tester.view.devicePixelRatio;
      tester.view.physicalSize = Size(1200 * dpr, 900 * dpr);
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });

      // Готовим архивную комнату: актор A создаёт чат, вступает и выходит БЕЗ
      // forget — комната уезжает в архив (forget вычистил бы её и оттуда).
      final actorA = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userA);
      final actorB = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userB);
      final roomId = await actorB.createGroupChat(
        [actorA.userId],
        name: 'Архивный чат LABA-2543',
      );
      await actorA.joinRoom(roomId);
      await actorA.sendText(roomId, 'сообщение до архивации');
      await actorA.leaveWithoutForget(roomId);

      app.main();
      await tester.ensureLizaHome();

      final context = tester.element(find.byType(ChatListViewBody));
      GoRouter.of(context).go('/rooms/archive');

      // Список архива загрузился и НЕ пуст.
      final archiveItem = find.text('Архивный чат LABA-2543');
      await tester.waitUntil(archiveItem, timeout: const Duration(seconds: 30));

      await tester.tap(archiveItem.first);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // AC-1/AC-8: в шапке архивного чата есть стрелка «назад».
      final backButton = find.byType(BackButton);
      await tester.waitUntil(backButton, timeout: const Duration(seconds: 20));

      await tester.tap(backButton.first);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));

      // AC-10: вернулись именно в АРХИВ, и список не пуст.
      await tester.waitUntil(archiveItem, timeout: const Duration(seconds: 30));
      expect(
        archiveItem,
        findsWidgets,
        reason: 'после стрелки обязан быть непустой список архива, '
            'а не пустой экран и не «вы больше не участвуете»',
      );

      await actorA.leaveAndForget(roomId);
      await actorB.leaveAndForget(roomId);
    });
  });
}
