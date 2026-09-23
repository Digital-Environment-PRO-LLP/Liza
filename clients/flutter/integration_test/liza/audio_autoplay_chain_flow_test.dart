import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';
import 'package:liza/pages/chat/events/audio_player.dart';
import 'package:liza/pages/chat_list/chat_list_body.dart';
import 'package:liza/widgets/liza_app.dart';
import 'package:liza/widgets/matrix.dart';

import 'liza_flows.dart';

/// Device-flow автозапуска цепочки голосовых на РЕАЛЬНОМ бинаре
/// (`RL-audio-autoplay-chain`, device-ярус AC-8/AC-10/AC-11).
///
/// Воспроизводит КОНКРЕТНЫЙ сценарий из задания: несколько (ТРИ) голосовых
/// подряд. Проверяет не «сдвинулось куда-то» (это давало ложно-зелёный и
/// пропустило оба бага), а РЕАЛЬНОЕ пользовательское поведение:
///   1) после завершения V1 играет V2 (первый автопереход);
///   2) **UI активного пузыря показывает воспроизведение** (иконка pause на
///      бабле V2, пока он играет) — иначе «эффект не отображается» (баг A);
///   3) после завершения V2 играет V3 (**цепочка идёт ДАЛЬШЕ второго** — баг B);
///   4) UI пузыря V3 тоже показывает воспроизведение.
///
/// Три коротких валидных WAV (~1.2с — достаточно, чтобы застать pause-иконку).
/// Требует локальный стек + APP_ENV=local (кнопка «Локальный сервер (пароль)»).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Валидный WAV: mono 8kHz 16-bit PCM, ~1.2с тишины (AVFoundation/ExoPlayer
  // играют напрямую, без opus→CAF).
  Uint8List wav() {
    const sampleRate = 8000;
    const samples = 9600; // ~1.2с — есть окно застать «играет» на среднем треке
    final dataLen = samples * 2;
    final b = BytesBuilder();
    void str(String s) => b.add(s.codeUnits);
    void u32(int v) =>
        b.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
    void u16(int v) => b.add([v & 0xff, (v >> 8) & 0xff]);
    str('RIFF');
    u32(36 + dataLen);
    str('WAVE');
    str('fmt ');
    u32(16);
    u16(1);
    u16(1);
    u32(sampleRate);
    u32(sampleRate * 2);
    u16(2);
    u16(16);
    str('data');
    u32(dataLen);
    b.add(Uint8List(dataLen));
    return b.toBytes();
  }

  Future<String> sendVoice(Room room, String name) async {
    // Ретрай: на медленном холодном Android-эмуляторе первая отправка иногда
    // возвращает null (загрузка медиа/синк комнаты ещё не готовы). Логируем
    // причину, чтобы не гадать.
    Object? lastErr;
    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        final id = await room.sendFileEvent(
          MatrixFile(bytes: wav(), name: name, mimeType: 'audio/wav'),
          extraContent: const {
            'org.matrix.msc3245.voice': <String, dynamic>{},
            'org.matrix.msc1767.audio': {'duration': 1200},
          },
        );
        if (id != null) return id;
        // ignore: avoid_print
        print('[flow] sendVoice $name attempt $attempt → null');
      } catch (e, s) {
        lastErr = e;
        // ignore: avoid_print
        print('[flow] sendVoice $name attempt $attempt threw: $e\n$s');
      }
      await Future.delayed(const Duration(seconds: 3));
    }
    fail('sendVoice($name) не отправилось за 4 попытки; последняя ошибка: $lastErr');
  }

  testWidgets(
    'Цепочка ТРЁХ голосовых: V1→V2→V3 играют по очереди, UI активного пузыря '
    'показывает воспроизведение — AC:RL-audio-autoplay-chain/8+10',
    (tester) async {
      app.main();
      // Холодный Android-эмулятор доходит до первого экрана дольше 30с
      // (Impeller + vodozemac init) — даём запас, иначе ensureLizaHome падает
      // «Не дождались HomeserverPicker/ChatListViewBody» ещё до сценария.
      await tester.ensureLizaHome(timeout: const Duration(seconds: 120));

      final ctx = tester.element(find.byType(ChatListViewBody));
      final matrix = Matrix.of(ctx);
      final client = matrix.client;

      final roomId = await client.createRoom(
        name: 'autoplay-chain-flow',
        preset: CreateRoomPreset.privateChat,
      );
      final room = client.getRoomById(roomId)!;

      // Три голосовых ПОДРЯД: v1 (старше) → v2 → v3 (новее).
      final v1 = await sendVoice(room, 'voice1.wav');
      final v2 = await sendVoice(room, 'voice2.wav');
      final v3 = await sendVoice(room, 'voice3.wav');

      LizaApp.router.go('/rooms/$roomId');
      await tester.waitUntil(
        find.byType(ChatView),
        timeout: const Duration(seconds: 40),
      );
      // Ждём, что ВСЕ три голосовых синхронизировались и отрисованы — иначе
      // «цепочка не перешла» может ложно упасть из-за незасинканного V2/V3.
      for (final id in [v1, v2, v3]) {
        await tester.waitUntil(
          find.byWidgetPredicate(
            (w) => w is AudioPlayerWidget && w.event.eventId == id,
          ),
          timeout: const Duration(seconds: 40),
        );
      }

      // Тап play первого голосового.
      final playV1 = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is AudioPlayerWidget && w.event.eventId == v1,
        ),
        matching: find.byIcon(Icons.play_arrow_outlined),
      );
      await tester.waitUntil(playV1);
      await tester.tap(playV1.first);

      await _waitEvent(tester, matrix, v1, reason: 'V1 не начал играть');

      // V1 → V2 (первый автопереход).
      await _waitEvent(tester, matrix, v2, reason: 'цепочка не перешла V1→V2');
      // Баг A: UI пузыря V2 обязан показывать воспроизведение (иконка pause).
      await _waitBubblePlaying(tester, v2, reason: 'UI V2 не показывает play');

      // V2 → V3 (второй автопереход — цепочка идёт дальше второго; баг B).
      await _waitEvent(tester, matrix, v3, reason: 'цепочка не перешла V2→V3');
      await _waitBubblePlaying(tester, v3, reason: 'UI V3 не показывает play');
    },
  );
}

/// Ждёт, пока глобальный активный трек станет [eventId].
Future<void> _waitEvent(
  WidgetTester tester,
  MatrixState matrix,
  String eventId, {
  required String reason,
  Duration timeout = const Duration(seconds: 40),
}) async {
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (matrix.voiceMessageEventId.value == eventId) return;
  }
  fail(
    'waitEvent timeout ($reason): '
    'активен ${matrix.voiceMessageEventId.value}, ждали $eventId',
  );
}

/// Ждёт, пока пузырь [eventId] покажет иконку паузы (=реально играет в UI).
/// Ловит баг «эффект воспроизведения не отображается»: активный трек играет
/// звуком, но виджет остаётся на play_arrow.
Future<void> _waitBubblePlaying(
  WidgetTester tester,
  String eventId, {
  required String reason,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final pauseOnBubble = find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is AudioPlayerWidget && w.event.eventId == eventId,
    ),
    matching: find.byIcon(Icons.pause_outlined),
  );
  final end = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 150));
    if (pauseOnBubble.evaluate().isNotEmpty) return;
  }
  fail('waitBubblePlaying timeout ($reason)');
}
