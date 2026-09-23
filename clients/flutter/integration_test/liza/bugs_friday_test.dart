import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';
import 'package:liza/pages/chat/events/audio_player.dart';
import 'package:liza/pages/chat/events/message.dart';
import 'package:liza/pages/chat/input_bar.dart';
import 'package:liza/widgets/avatar.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'liza_flows.dart';

/// E2E-кейсы под «баги пятницы» (см. plans/bugs.md, tests/e2e.md).
/// Локальный стек: make local-up && make local-seed-e2e.
/// A — UI (testuser), B — headless-актор (testuser2) через Matrix CS API.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Минимальный валидный WAV (mono, 8 кГц, 16-bit, тишина) — формат, который
  // AVFoundation/ExoPlayer играют нативно; нужен лишь чтобы проверить, что
  // play не падает MissingPluginException (ядро бага #1), без зависимости от
  // opus/CAF. [seconds] подлиннее, чтобы плеер ещё играл к моменту проверки.
  Uint8List silenceWav({int seconds = 3, int sampleRate = 8000}) {
    final dataSize = sampleRate * 2 * seconds; // 16-bit mono
    final bytes = BytesBuilder();
    void str(String s) => bytes.add(s.codeUnits);
    void u32(int v) => bytes.add([
      v & 0xff,
      (v >> 8) & 0xff,
      (v >> 16) & 0xff,
      (v >> 24) & 0xff,
    ]);
    void u16(int v) => bytes.add([v & 0xff, (v >> 8) & 0xff]);
    str('RIFF');
    u32(36 + dataSize);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1); // PCM
    u16(1); // mono
    u32(sampleRate);
    u32(sampleRate * 2); // byteRate
    u16(2); // blockAlign
    u16(16); // bitsPerSample
    str('data');
    u32(dataSize);
    bytes.add(Uint8List(dataSize)); // тишина
    return bytes.toBytes();
  }

  Future<void> openDmWith(
    WidgetTester tester,
    E2eActor actorB,
    String roomId,
    String firstInbound,
  ) async {
    app.main();
    await tester.ensureLizaHome();
    final roomTile = find.textContaining(firstInbound);
    await tester.waitUntil(roomTile);
    await tester.tap(roomTile.first);
    await tester.waitUntil(find.byType(ChatView));
  }

  // Увести UI из чата в список ДО выхода из комнаты в teardown: открытый
  // ChatController иначе дёргает requestHistory по уже покинутой комнате →
  // M_FORBIDDEN (на iOS всплывает как post-completion failure и роняет тест,
  // на macOS тайминг это прятал).
  Future<void> closeChatToList(WidgetTester tester) async {
    final back = find.byType(BackButton);
    if (back.evaluate().isNotEmpty) {
      await tester.tap(back.first);
    }
    for (
      var i = 0;
      i < 20 && find.byType(ChatView).evaluate().isNotEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<void> sendFromUi(WidgetTester tester, String text) async {
    final input = find.descendant(
      of: find.byType(InputBar),
      matching: find.byType(TextField),
    );
    await tester.waitUntil(input);
    await tester.enterText(input.first, text);
    await tester.pump(const Duration(milliseconds: 300));
    final sendButton = find.byIcon(Icons.send_outlined);
    if (sendButton.evaluate().isNotEmpty) {
      await tester.tap(sendButton.first);
    } else {
      await tester.testTextInput.receiveAction(TextInputAction.done);
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  group('Баги пятницы: квитанции и сепаратор', () {
    // ── Баг #2 — РУЧНОЙ gate (не автоматизируется надёжно) ─────────────────
    // Сепаратор «Непрочитанное» якорится на room.fullyRead. В свежем e2e A
    // только что вступил и НИЧЕГО не читал → fullyRead пуст → сепаратор не
    // отрисовывается вовсе, поэтому любой UI-assert тривиален (ложно-зелёный).
    // Баг #2 требует состояния «прочитал часть → пришли новые → переоткрыл»,
    // т.е. ПРЕДыдущей сессии. Repro (ручной, tests/e2e.md §9):
    //   1) A в чате прочитал всё. 2) B шлёт N сообщений. 3) A переоткрывает —
    //   сепаратор над первым непрочитанным B. 4) A пишет свой ответ → сепаратор
    //   НЕ должен оказаться над собственным сообщением A.
    // Фикс (send()→_suppressReadMarkerIfAllMine + вызов из updateView) покрыт
    // код-ревью; UI-проверка — ручная.

    // ── Баг #5 ────────────────────────────────────────────────────────────
    // Кластер аватарок не должен пропадать, когда новейшее событие — от
    // собеседника. В модели-границе у каждого аватарка под его последним
    // прочитанным: после ответа B его аватарка уходит на его же новое
    // сообщение, а под сообщением A остаётся аватарка самого A (п.2.1) —
    // SeenByAvatars всё равно отрисован, индикатор прочтения не исчезает.
    testWidgets('#5 кластер аватарок остаётся при новом сообщении собеседника', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });
      final actorA = await E2eActor.login(
        E2eConfig.homeserver,
        E2eConfig.userA,
      );
      final actorB = await E2eActor.login(
        E2eConfig.homeserver,
        E2eConfig.userB,
      );
      final roomId = await actorB.createDirectChat(actorA.userId);
      await actorA.joinRoom(roomId);

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final seed = 'seenby seed $stamp';
      final outbound = 'seenby mine $stamp';
      final after = 'seenby after $stamp';
      // B пишет первое сообщение, чтобы A нашёл комнату в списке.
      await actorB.sendText(roomId, seed);

      try {
        await openDmWith(tester, actorB, roomId, seed);
        await tester.waitUntil(find.textContaining(seed, findRichText: true));

        // A отправляет своё сообщение.
        await sendFromUi(tester, outbound);
        final mine = await actorB.waitForEvent(
          roomId,
          (e) => e.type == 'm.room.message' && e.content['body'] == outbound,
        );

        // B читает сообщение A, затем шлёт СВОЁ новое (становится новейшим).
        await actorB.sendReadReceipt(roomId, mine.eventId);
        await actorB.sendText(roomId, after);

        // Аватарка прочтения остаётся на сообщении A, несмотря на то что
        // новейшее событие теперь — сообщение B.
        await tester.waitUntil(
          find.descendant(
            of: find.byType(SeenByAvatars),
            matching: find.byType(Avatar),
          ),
          timeout: const Duration(seconds: 15),
        );
      } finally {
        await closeChatToList(tester);
        await actorA.leaveAndForget(roomId);
        await actorB.leaveAndForget(roomId);
        await actorB.logout();
        await actorA.logout();
      }
    });

    // ── Баги #4 + #6 ──────────────────────────────────────────────────────
    // Аватарка «прочитал до сюда» появляется по ОДНОЙ квитанции, без нового
    // события в комнате (баг #4 — раньше индикатор обновлялся только со
    // следующим событием). Аватарка и есть единый индикатор прочтения, поэтому
    // рассинхрон «аватарка есть, а статуса нет» (баг #6) невозможен.
    testWidgets('#4/#6 аватарка прочтения по одной квитанции без нового события', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });
      final actorA = await E2eActor.login(
        E2eConfig.homeserver,
        E2eConfig.userA,
      );
      final actorB = await E2eActor.login(
        E2eConfig.homeserver,
        E2eConfig.userB,
      );
      final roomId = await actorB.createDirectChat(actorA.userId);
      await actorA.joinRoom(roomId);

      final stamp = DateTime.now().millisecondsSinceEpoch;
      final inbound = 'consist ping $stamp';
      final outbound = 'consist pong $stamp';
      await actorB.sendText(roomId, inbound);

      try {
        await openDmWith(tester, actorB, roomId, inbound);
        await tester.waitUntil(
          find.textContaining(inbound, findRichText: true),
        );
        await sendFromUi(tester, outbound);

        final replyEvent = await actorB.waitForEvent(
          roomId,
          (e) => e.type == 'm.room.message' && e.content['body'] == outbound,
        );

        // До прочтения — одна галочка done; своя аватарка под сообщением видна
        // сразу (п.2.1), но done_all (прочитано собеседником) ещё нет.
        await tester.waitUntil(find.byIcon(Icons.done_rounded));
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);

        // B читает → БЕЗ нового события от B (баг #4) галочка становится
        // done_all (единый индикатор прочтения по одной квитанции).
        await actorB.sendReadReceipt(roomId, replyEvent.eventId);

        await tester.waitUntil(
          find.byIcon(Icons.done_all_rounded),
          timeout: const Duration(seconds: 30),
        );
      } finally {
        await closeChatToList(tester);
        await actorA.leaveAndForget(roomId);
        await actorB.leaveAndForget(roomId);
        await actorB.logout();
        await actorA.logout();
      }
    });

    // ── Баги #5/#6 в ГРУППЕ (сценарий пользователя) ───────────────────────
    // На скриншотах баги были в групповом чате, а не в DM. Проверяем
    // ГРУППОВУЮ семантику новой модели: A пишет в группу, ДВА собеседника
    // (B, C) читают → на сообщении A РОВНО ТРИ аватарки (A под своим — п.2/2.1,
    // плюс B и C, дочитавшие до него).
    testWidgets('#5/#6 группа: автор + два читателя на сообщении (три аватарки)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });
      final actorA = await E2eActor.login(
        E2eConfig.homeserver,
        E2eConfig.userA,
      );
      final actorB = await E2eActor.login(
        E2eConfig.homeserver,
        E2eConfig.userB,
      );
      final actorC = await E2eActor.login(
        E2eConfig.homeserver,
        E2eConfig.userC,
      );
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final roomId = await actorB.createGroupChat([
        actorA.userId,
        actorC.userId,
      ], name: 'e2e group $stamp');
      await actorA.joinRoom(roomId);
      await actorC.joinRoom(roomId);

      // B шлёт первое сообщение, чтобы A нашёл комнату по превью в списке.
      final seed = 'group seed $stamp';
      await actorB.sendText(roomId, seed);
      final outbound = 'group hello $stamp';

      try {
        app.main();
        await tester.ensureLizaHome();
        final roomTile = find.textContaining(seed);
        await tester.waitUntil(roomTile);
        await tester.tap(roomTile.first);
        await tester.waitUntil(find.byType(ChatView));

        await sendFromUi(tester, outbound);
        final replyEvent = await actorB.waitForEvent(
          roomId,
          (e) => e.type == 'm.room.message' && e.content['body'] == outbound,
        );

        // Оба собеседника читают сообщение A.
        await actorB.sendReadReceipt(roomId, replyEvent.eventId);
        await actorC.sendReadReceipt(roomId, replyEvent.eventId);

        // Ровно ТРИ аватарки на сообщении A: своя (A, п.2.1) + B и C (дочитали).
        final seenAvatars = find.descendant(
          of: find.byType(SeenByAvatars),
          matching: find.byType(Avatar),
        );
        await tester.waitUntil(
          seenAvatars,
          timeout: const Duration(seconds: 30),
        );
        // Дать прийти обеим квитанциям (могут в разных sync-батчах).
        for (var i = 0; i < 20 && seenAvatars.evaluate().length < 3; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(
          seenAvatars,
          findsNWidgets(3),
          reason: 'В группе: автор A + два читателя B,C = три аватарки',
        );
      } finally {
        await closeChatToList(tester);
        await actorA.leaveAndForget(roomId);
        await actorB.leaveAndForget(roomId);
        await actorC.leaveAndForget(roomId);
        await actorC.logout();
        await actorB.logout();
        await actorA.logout();
      }
    });

    // ── Баг #1 — голосовое проигрывается без MissingPluginException ────────
    // B шлёт аудио (WAV), A открывает и жмёт play. Успешный play → иконка
    // становится pause: значит per-player канал поднялся (await источника до
    // play) и MissingPluginException нет. Формат WAV (а не opus) — чтобы
    // проверить ИМЕННО гонку канала независимо от CAF-конверсии.
    testWidgets('#1 голосовое проигрывается (нет MissingPluginException)', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });
      final actorA = await E2eActor.login(
        E2eConfig.homeserver,
        E2eConfig.userA,
      );
      final actorB = await E2eActor.login(
        E2eConfig.homeserver,
        E2eConfig.userB,
      );
      final roomId = await actorB.createDirectChat(actorA.userId);
      await actorA.joinRoom(roomId);

      final stamp = DateTime.now().millisecondsSinceEpoch;
      // Аудио раньше текста, чтобы тайл комнаты искался по тексту-seed.
      await actorB.sendAudio(
        roomId,
        silenceWav(seconds: 3),
        filename: 'voice_$stamp.wav',
      );
      final seed = 'audio seed $stamp';
      await actorB.sendText(roomId, seed);

      try {
        await openDmWith(tester, actorB, roomId, seed);

        final playBtn = find.descendant(
          of: find.byType(AudioPlayerWidget),
          matching: find.byIcon(Icons.play_arrow_outlined),
        );
        await tester.waitUntil(playBtn, timeout: const Duration(seconds: 20));
        await tester.tap(playBtn.first);

        // Успешный play → pause-иконка. MissingPluginException не дал бы её.
        await tester.waitUntil(
          find.descendant(
            of: find.byType(AudioPlayerWidget),
            matching: find.byIcon(Icons.pause_outlined),
          ),
          timeout: const Duration(seconds: 25),
        );
      } finally {
        await closeChatToList(tester);
        await actorA.leaveAndForget(roomId);
        await actorB.leaveAndForget(roomId);
        await actorB.logout();
        await actorA.logout();
      }
    });
  });
}
