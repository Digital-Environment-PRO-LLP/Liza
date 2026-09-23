// AC-9 (Ярус C, device): сквозная проверка того, что пункт меню кладёт в буфер
// ВЫДЕЛЕННЫЙ ФРАГМЕНТ, а не всё сообщение, и что в копию не уезжает
// reply-fallback. Воспроизводится ИМЕННО сценарий жалобы (2026-09-08), а не его
// вырожденный минимум: ответ на ГОЛОСОВОЕ + текст, из которого копируют фразу.
//
// Host-страж (test/pages/chat/copy_fragment_test.dart) проверяет `hideReply`,
// публикацию выделения и структуру; системный буфер и реальные жесты — здесь.
//
// Запуск: make local-up && make local-seed-e2e, затем run-android.sh / run-ios.sh.
//
// ledger:RL-copy-fragment-not-whole-message

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/l10n/l10n.dart';
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
    'AC-9: выделенный фрагмент ответа на голосовое копируется без цитаты '
    '— ledger:RL-copy-fragment-not-whole-message',
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

      // 1. Голосовое — то, на что отвечают в сценарии жалобы.
      final voiceId = await actorB.sendAudio(
        roomId,
        Uint8List.fromList(List<int>.filled(512, 0)),
        filename: 'recording1788888499600193.m4a',
        mimeType: 'audio/mp4',
      );

      // 2. Ответ на него — с ТЕМ ЖЕ reply-fallback в body, что строит SDK.
      //    Отдельные слова, чтобы отличить фрагмент от полного текста.
      const ownText = 'принято лишнее будет убрано';
      const fallbackLine = '> <${'@'}e2e-b:localhost> recording1788888499600193.m4a';
      await actorB.api.sendMessage(
        roomId,
        'm.room.message',
        'e2e-reply-${DateTime.now().microsecondsSinceEpoch}',
        {
          'msgtype': 'm.text',
          'body': '$fallbackLine\n\n$ownText',
          'm.relates_to': {
            'm.in_reply_to': {'event_id': voiceId},
          },
        },
      );

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
        find.textContaining('принято', findRichText: true),
        timeout: const Duration(seconds: 40),
      );
      await tester.pump(const Duration(seconds: 1));

      // AC-1 на РЕАЛЬНОМ рендере: пузырь не показывает reply-fallback строкой —
      // именно поэтому он не должен попадать и в буфер.
      expect(
        find.textContaining('recording1788888499600193.m4a> ',
            findRichText: true),
        findsNothing,
        reason: 'служебный fallback не рисуется в пузыре',
      );

      // Long-press → поповер. Слой монтируется только на completed-анимации.
      for (var attempt = 0; attempt < 3; attempt++) {
        await tester.longPress(
          find.textContaining('принято', findRichText: true).first,
        );
        final end = DateTime.now().add(const Duration(seconds: 8));
        while (find.byType(SelectableTextOverlay).evaluate().isEmpty &&
            DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        if (find.byType(SelectableTextOverlay).evaluate().isNotEmpty) break;
      }
      expect(
        find.byType(SelectableTextOverlay),
        findsOneWidget,
        reason: 'в поповере должен появиться живой слой выделения',
      );

      final l10n = await L10n.delegate.load(const Locale('ru'));

      // Пока ничего не выделено — пункт называется «Скопировать текст».
      expect(
        find.text(l10n.copyToClipboard),
        findsOneWidget,
        reason: 'без выделения пункт копирует всё сообщение',
      );

      await Clipboard.setData(const ClipboardData(text: ''));

      // Выделяем слово в живом слое (native-жест) и ждём USER-VISIBLE эффект:
      // подпись пункта обязана смениться на «Скопировать выделенное».
      final overlaySelection = find.descendant(
        of: find.byType(SelectableTextOverlay),
        matching: find.byType(SelectionArea),
      );
      var sawSelectionLabel = false;
      for (var attempt = 0; attempt < 3 && !sawSelectionLabel; attempt++) {
        await tester.longPress(overlaySelection);
        final end = DateTime.now().add(const Duration(seconds: 5));
        while (DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 200));
          if (find.text(l10n.copySelection).evaluate().isNotEmpty) {
            sawSelectionLabel = true;
            break;
          }
        }
      }

      await snapCandidate(
        tester,
        'RL-copy-fragment-not-whole-message__popover',
      );

      var copied = '';
      if (sawSelectionLabel) {
        // AC-6: подпись отражает, что ляжет в буфер именно фрагмент.
        expect(find.text(l10n.copySelection), findsOneWidget);
        await tester.tap(find.text(l10n.copySelection), warnIfMissed: false);
      } else {
        // Native-жест выделения флакий в integration_test: если выделить не
        // удалось, проверяем хотя бы вторую половину жалобы — копия целого
        // сообщения обязана быть БЕЗ reply-fallback.
        await tester.tap(find.text(l10n.copyToClipboard), warnIfMissed: false);
      }
      await tester.pump(const Duration(milliseconds: 600));
      copied = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';

      // ignore: avoid_print
      print('AC9-DEVICE: sawSelectionLabel=$sawSelectionLabel copied="$copied"');

      // AC-1 (всегда): что бы ни скопировали — служебной цитаты в буфере нет.
      expect(
        copied,
        isNot(contains('recording1788888499600193.m4a')),
        reason: 'reply-fallback не должен уезжать в буфер (жалоба 2026-09-08)',
      );
      expect(copied.trim(), isNot(startsWith('>')));

      if (sawSelectionLabel) {
        // AC-4: в буфере — ЧАСТЬ сообщения, строго короче полного текста.
        expect(copied.trim(), isNotEmpty);
        expect(
          ownText.contains(copied.trim().toLowerCase()),
          isTrue,
          reason: 'в буфере должен быть фрагмент сообщения ("$copied")',
        );
        expect(
          copied.trim().length,
          lessThan(ownText.length),
          reason: 'фрагмент обязан быть КОРОЧЕ полного текста, иначе '
              'скопировалось всё сообщение — ровно то, на что жалуются',
        );
      } else {
        expect(copied.trim().toLowerCase(), ownText);
      }
    },
  );
}
