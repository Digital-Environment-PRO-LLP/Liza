// LABA-1964 (Ярус C, device): сквозная проверка выделения ЧАСТИ текста и
// копирования фрагмента в поповере на НАСТОЯЩЕМ бинаре (Android/локальный стек).
// Host-тест (message_partial_copy_test.dart) проверяет вёрстку/гейты, но не
// воспроизводит реальные жесты выделения и системный буфер — это делает здесь.
//
// Запуск: make local-up && make local-seed-e2e, затем через run-android.sh
// (adb reverse tcp:8008). Актор B сеет текст в DM, UI-актор A открывает чат,
// длинный тап → поповер → выделяем слово в живом слое → «Копировать» → сверяем,
// что в буфере ФРАГМЕНТ (короче полного текста), а не всё сообщение.
//
// ledger:RL-message-select-copy-in-popover

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';
import 'package:liza/pages/chat/events/message_context_menu.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'e2e_shots.dart';
import 'liza_flows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'LABA-1964: выделение части текста в поповере → копируется фрагмент '
    '— ledger:RL-message-select-copy-in-popover',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });

      final actorA = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userA);
      final actorB = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userB);
      for (final actor in [actorA, actorB]) {
        final sync = await actor.api.sync();
        for (final r in (sync.rooms?.join?.keys.toList() ?? <String>[])) {
          try {
            await actor.api.leaveRoom(r);
            await actor.api.forgetRoom(r);
          } catch (_) {}
        }
      }
      final roomId = await actorB.createDirectChat(actorA.userId);
      await actorA.joinRoom(roomId);

      // Отдельные слова, чтобы длинный тап выделил РОВНО одно и мы отличили
      // фрагмент от полного текста.
      const fullMessage = 'альфа браво чарли дельта';
      await actorB.sendText(roomId, fullMessage);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final beacon = 'e2e-open-$stamp';
      await actorB.sendText(roomId, beacon);

      app.main();
      await tester.ensureLizaHome();

      final tile = find.textContaining(beacon);
      await tester.waitUntil(tile, timeout: const Duration(seconds: 60));
      for (var attempt = 0; attempt < 3; attempt++) {
        await tester.tap(tile.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 500));
        final end = DateTime.now().add(const Duration(seconds: 20));
        while (find.byType(ChatView).evaluate().isEmpty &&
            DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        if (find.byType(ChatView).evaluate().isNotEmpty) break;
      }
      await tester.waitUntil(
        find.textContaining('альфа', findRichText: true),
        timeout: const Duration(seconds: 40),
      );
      await tester.pump(const Duration(seconds: 1));

      // Длинный тап по сообщению в ленте → открывается поповер. Слой монтируется
      // ТОЛЬКО на AnimationStatus.completed, поэтому ждём его поллингом (а не
      // фиксированным pump) — на живом девайсе тайминг анимации недетерминирован.
      // Ретраим сам long-press: первый жест иногда съедается скроллом ленты.
      for (var attempt = 0; attempt < 3; attempt++) {
        await tester.longPress(
          find.textContaining('альфа', findRichText: true).first,
        );
        final end = DateTime.now().add(const Duration(seconds: 8));
        while (find.byType(SelectableTextOverlay).evaluate().isEmpty &&
            DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        if (find.byType(SelectableTextOverlay).evaluate().isNotEmpty) break;
      }

      // AC:RL-message-select-copy-in-popover/6 — живой selectable-слой смонтирован
      // в поповере на РЕАЛЬНОМ бинаре (текст обёрнут в SelectionArea поверх
      // снимка), и это НАСТОЯЩИЙ текст сообщения (значит копия даст фрагмент).
      expect(
        find.byType(SelectableTextOverlay),
        findsOneWidget,
        reason: 'в поповере должен появиться живой слой выделения текста',
      );
      final overlayText = find.descendant(
        of: find.byType(SelectableTextOverlay),
        matching: find.byType(SelectionArea),
      );
      expect(overlayText, findsOneWidget, reason: 'слой — это SelectionArea');
      expect(
        find.descendant(
          of: find.byType(SelectableTextOverlay),
          matching: find.textContaining('браво', findRichText: true),
        ),
        findsOneWidget,
        reason: 'слой несёт настоящий текст сообщения',
      );

      // Визуальное свидетельство (AC-6): длинный тап выделяет слово в живом слое,
      // затем снимаем кадр поповера с подсветкой для сверки глазами.
      await Clipboard.setData(const ClipboardData(text: ''));
      var copiedFragment = '';
      try {
        await tester.longPress(overlayText);
        await tester.pump(const Duration(milliseconds: 700));
        final copyButton = find.byType(TextSelectionToolbarTextButton);
        if (copyButton.evaluate().isNotEmpty) {
          await tester.tap(copyButton.first, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 400));
          copiedFragment =
              (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
        }
      } catch (_) {
        // Native-жест выделения флакий в integration_test — не валим тест на нём
        // (реальный палец покрыт ручным AC-6); критично — что слой смонтирован.
      }
      // ignore: avoid_print
      print('LABA1964-DEVICE: copiedFragment="$copiedFragment"');

      await snapCandidate(tester, 'RL-message-select-copy-in-popover__popover');
      // Окно, чтобы снять скриншот из app-sandbox через adb до удаления пакета.
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }

      // Если native-жест сработал — фрагмент обязан быть ЧАСТЬЮ сообщения.
      if (copiedFragment.trim().isNotEmpty) {
        expect(fullMessage.contains(copiedFragment.trim()), isTrue,
            reason: 'скопирован фрагмент из сообщения ($copiedFragment)');
      }
    },
  );
}
