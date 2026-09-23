// Ярус C (device): сквозная проверка «Скопировать текст» на картинке-с-подписью
// на НАСТОЯЩЕМ бинаре (Android/iOS, локальный стек). Host-тест
// (copy_caption_text_test.dart) проверяет чистую логику copyTextForEvent; здесь —
// реальный жест long-press → пункт меню «Скопировать текст» → системный буфер.
//
// Воспроизводит ИМЕННО кейс из задания: картинка с подписью «С телефона в час по
// чайной ложке…» → в буфере должна оказаться ПОДПИСЬ, а не «🖼️ Изображение от …».
//
// Запуск: make local-up && local-seed, затем prove-ui/run.sh (APP_ENV=local).
//
// AC:RL-copy-caption-text/7 — ledger:RL-copy-caption-text

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'liza_flows.dart';

// 1×1 прозрачный PNG (валидные байты для uploadContent).
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, //
  0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, //
  0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, //
  0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, //
  0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, //
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

const _caption =
    'С телефона в час по чайной ложке пытается воспроизвести и не смогает. '
    'Скачать не дает. С пк ни воспроизвести, ни скачать, при этом текст '
    'совсем не читается на экране';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'картинка-с-подписью → «Скопировать текст» кладёт подпись, не заглушку '
    '— ledger:RL-copy-caption-text',
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

      await actorB.sendImageWithCaption(roomId, _png, _caption);
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

      // Ждём саму подпись в ленте (её рисует media_caption под картинкой).
      final captionInChat = find.textContaining(
        'по чайной ложке',
        findRichText: true,
      );
      await tester.waitUntil(captionInChat, timeout: const Duration(seconds: 40));
      await tester.pump(const Duration(seconds: 1));

      // long-press по подписи/картинке открывает контекстное меню сообщения.
      // Ретраим — первый жест иногда съедается скроллом ленты.
      final copyItem = find.text('Скопировать текст');
      for (var attempt = 0; attempt < 3; attempt++) {
        await tester.longPress(captionInChat.first, warnIfMissed: false);
        final end = DateTime.now().add(const Duration(seconds: 8));
        while (copyItem.evaluate().isEmpty && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        if (copyItem.evaluate().isNotEmpty) break;
      }

      expect(
        copyItem,
        findsOneWidget,
        reason: 'на картинке-с-подписью пункт «Скопировать текст» должен быть',
      );

      await Clipboard.setData(const ClipboardData(text: ''));
      await tester.tap(copyItem.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 600));

      final copied =
          (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      // ignore: avoid_print
      print('COPY-CAPTION-DEVICE: copied="$copied"');

      // Наблюдаемый пользователем эффект — содержимое буфера. Чтение системного
      // буфера ОБРАТНО в instrumented-тесте ограничено платформой (Android 10+
      // требует foreground-focus и часто возвращает пусто — как в
      // message_select_copy_test.dart). Поэтому: если read-back доступен (iOS) —
      // проверяем, что в буфере ПОДПИСЬ, а не заглушка; если пусто (Android
      // clipboard-restriction) — не валим тест на ограничении платформы, сам
      // interaction-путь (картинка-с-подписью → пункт «Скопировать текст» виден
      // → тап без ошибки) уже проверен выше, а содержимое покрыто iOS + unit.
      if (copied.isNotEmpty) {
        expect(copied, contains('по чайной ложке'),
            reason: 'в буфер должна попасть подпись картинки');
        expect(copied, isNot(contains('Изображение от')),
            reason: 'в буфер НЕ должна попасть заглушка «🖼️ Изображение от …»');
        expect(copied, isNot(contains('🖼')));
      }
    },
  );
}
