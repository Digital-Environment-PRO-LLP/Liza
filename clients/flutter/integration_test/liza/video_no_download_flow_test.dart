// Ярус C (device): при ПРОБЛЕМЕ воспроизведения видео в просмотрщике НЕТ кнопок
// «Скачать»/«Сохранить» — только «Повторить» (требование руководителя 2026-08-31:
// «никакого скачивания рядом с ошибкой воспроизведения»). Host-тесты проверяют
// диагностику; здесь — реальный жест: тап по видео → ImageViewer → форс-фейл
// (НЕвоспроизводимый мусор вместо видео) → assert структуры overlay.
//
// Воспроизводит суть жалобы: видео не играет → раньше «вылазила кнопка Скачать»,
// которая всё равно не качает. Теперь при провале — только «Повторить».
//
// Запуск: make local-up && local-seed, затем prove-ui/run.sh
//   (--dart-define=APP_ENV=local; Android — E2E_HOMESERVER=http://localhost:8008).
//
// AC:RL-video-viewer-save-and-overlay/1 — ledger:RL-video-viewer-save-and-overlay

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';
import 'package:liza/pages/chat/events/video_player.dart';
import 'package:liza/pages/image_viewer/image_viewer.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'liza_flows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'провал воспроизведения видео → «Повторить», без «Скачать»/«Сохранить» '
    '— ledger:RL-video-viewer-save-and-overlay',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });
      // Форс-фейл видео (мусор-байты) НАМЕРЕННО генерит async-ошибки декода/
      // загрузки в приложении — они ОЖИДАЕМЫ. Без перехвата FlutterError.onError
      // integration_test-биндинг на tearDown падает «unexpected additional errors»
      // (_pendingExceptionDetails). Глушим (логируем) на время флоу, восстанавливаем
      // в конце — иначе провал воспроизведения ронял бы сам страж.
      final origOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        // ignore: avoid_print
        print('EXPECTED-VIDEO-FAIL: ${details.exceptionAsString()}');
      };
      addTearDown(() => FlutterError.onError = origOnError);

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

      // НЕвоспроизводимый «видео»-мусор → плеер гарантированно провалится.
      await actorB.sendVideo(roomId);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final beacon = 'e2e-open-$stamp';
      await actorB.sendText(roomId, beacon);

      app.main();
      await tester.ensureLizaHome();

      // Открыть чат по маяку.
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

      // Дождаться inline-видео и открыть просмотрщик тапом.
      final inlineVideo = find.byType(EventVideoPlayer);
      await tester.waitUntil(inlineVideo, timeout: const Duration(seconds: 40));
      for (var attempt = 0; attempt < 3; attempt++) {
        await tester.tap(inlineVideo.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 500));
        final end = DateTime.now().add(const Duration(seconds: 10));
        while (find.byType(ImageViewer).evaluate().isEmpty &&
            DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        if (find.byType(ImageViewer).evaluate().isNotEmpty) break;
      }
      expect(find.byType(ImageViewer), findsWidgets,
          reason: 'тап по видео должен открыть просмотрщик');

      // Прокручиваем окно провала (мусор проходит watchdog 15с + swap + retry).
      // ДЕТЕРМИНИРОВАННЫЙ инвариант руководителя: пока просмотрщик открыт и видео
      // в состоянии загрузки/ошибки — кнопки СКАЧИВАНИЯ (Icons.file_download_
      // outlined, была и в error-overlay, и в overlay загрузки) НЕТ НИ РАЗУ.
      // На КАЖДОМ кадре окна проверяем отсутствие — не «в конце» (могла мелькнуть).
      final download = find.byIcon(Icons.file_download_outlined);
      final retry = find.byIcon(Icons.refresh);
      // Вторая поверхность сообщения: до 2026-09-04 рядом с оверлеем всплывал
      // SnackBar «Ой, что-то пошло не так…» с ВТОРОЙ кнопкой «Повторить» — на
      // экране висели два сообщения об одной ошибке (регресс с 1dbabb74).
      final snack = find.byType(SnackBar);
      final end = DateTime.now().add(const Duration(seconds: 80));
      var retrySeen = false;
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 500));
        // Инвариант проверяем НА КАЖДОМ кадре: download-кнопка не должна мелькнуть.
        // AC:RL-video-viewer-save-and-overlay/2 — overlay загрузки/буферизации
        // тоже без кнопки «Сохранить»: цикл покрывает ОБА состояния (ошибка и
        // докачка), т.к. пампит всё окно провала целиком.
        expect(download, findsNothing,
            reason: 'рядом с ошибкой/загрузкой видео НЕ должно быть кнопки '
                'скачивания ни в один момент');
        // AC:RL-video-viewer-save-and-overlay/6 — покадрово, а не «в конце»:
        // SnackBar эфемерен (жил 12с), проверка постфактум его пропускала.
        // AC:RL-video-viewer-save-and-overlay/4 — тем же ассертом закрыт баннер
        // «Скачать полностью?» на слабом канале: он тоже был SnackBar'ом.
        expect(snack, findsNothing,
            reason: 'AC-6: при провале видео вторая поверхность сообщения '
                '(SnackBar) запрещена — сообщение ровно одно');
        if (retry.evaluate().isNotEmpty) retrySeen = true;
      }

      // Просмотрщик остался открыт (не вылетел), download-кнопки не было.
      expect(find.byType(ImageViewer), findsWidgets,
          reason: 'просмотрщик видео должен оставаться открытым');
      expect(download, findsNothing);
      // AC:RL-video-viewer-save-and-overlay/1 — РАНЬШЕ факт наличия «Повторить»
      // только вычислялся и уходил в print, в expect не попадал: страж оставался
      // зелёным даже когда оверлея не было вовсе (ложно-зелёный, разбор
      // 2026-09-04). Теперь это жёсткий ассерт — иначе AC-1 записи реестра
      // утверждал бы то, чего никто не проверяет.
      expect(retrySeen, isTrue,
          reason: 'AC-1: при провале воспроизведения обязан появиться '
              'error-overlay с кнопкой «Повторить»');
      // ignore: avoid_print
      print('VIDEO-NO-DOWNLOAD-DEVICE: download-buttons=0, snackbars=0 '
          '(инвариант «одна поверхность» держался), retry-overlay-seen=$retrySeen');
    },
  );
}
