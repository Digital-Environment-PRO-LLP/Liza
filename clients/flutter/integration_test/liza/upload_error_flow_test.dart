import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';
import 'package:liza/pages/chat_list/chat_list_body.dart';
import 'package:liza/widgets/matrix.dart';

import 'liza_flows.dart';

/// Device-flow терминальной ошибки загрузки медиа на РЕАЛЬНОМ бинаре
/// (`RL-upload-terminal-error-no-retry`, C1(b) рендер причины).
///
/// Триггер: `room.sendFileEvent` файла > серверного `max_upload_size` (локальный
/// Synapse — дефолтные 50 МБ). SDK `uploadContent` бросает
/// `FileTooBigMatrixException` (терминальная) ещё до отдачи → `sendFileEvent`
/// ставит `EventStatus.error` за ОДНУ попытку (не retry-шторм 30-60с), а
/// `message.dart` рисует значок ошибки с человекочитаемой причиной (тултип), а
/// не голый ⚠️.
///
/// ⚠️ C1(a) (перехват серверного 413/403 в `UploadProgressHttpClient`) на
/// локальном стеке НЕ воспроизводим: нет MMR, а у Synapse advertised==enforced
/// `max_upload_size` → клиент отсекает файл сам. C1(a) покрыт unit-стражем
/// `test/utils/upload_error_classifier_test.dart` (red-proof).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Терминальная ошибка загрузки: одна попытка (не шторм) + причина на бабле',
    (tester) async {
      app.main();
      await tester.ensureLizaHome();

      final ctx = tester.element(find.byType(ChatListViewBody));
      final client = Matrix.of(ctx).client;

      // Комната для отправки: своя новая (детерминизм — свежая лента без чужих
      // событий), ждём её появления в списке.
      final roomId = await client.createRoom(
        name: 'upload-error-flow',
        preset: CreateRoomPreset.privateChat,
      );
      final room = client.getRoomById(roomId)!;

      // Файл заведомо больше серверного max_upload_size (локально 50 МБ).
      final tooBig = MatrixFile(
        bytes: Uint8List(60 * 1024 * 1024),
        name: 'too_big.bin',
        mimeType: 'application/octet-stream',
      );

      final started = DateTime.now();
      Object? thrown;
      try {
        await room.sendFileEvent(tooBig);
      } catch (e) {
        thrown = e;
      }
      final elapsed = DateTime.now().difference(started);

      // Инвариант «одна попытка, не retry-шторм»: терминальная ошибка приходит
      // быстро (клиентский size-guard мгновенен), а НЕ через 30-60с ретраев.
      expect(
        elapsed.inSeconds,
        lessThan(20),
        reason: 'терминальная ошибка ушла в retry-шторм (>20с): $elapsed',
      );
      expect(
        thrown,
        isA<MatrixException>(),
        reason: 'ожидали терминальную MatrixException, получили: $thrown',
      );

      // Событие осело в ленте в статусе error (не висит «отправляется»).
      var hasErrorEvent = false;
      final timeline = await room.getTimeline();
      for (var i = 0; i < 40 && !hasErrorEvent; i++) {
        hasErrorEvent =
            timeline.events.any((e) => e.status == EventStatus.error);
        if (hasErrorEvent) break;
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(hasErrorEvent, isTrue,
          reason: 'ожидали событие в EventStatus.error в ленте комнаты');

      // Открываем комнату в UI и проверяем, что error-бабл несёт значок ошибки
      // с тултипом-причиной (C1(b) — message.dart, не голый ⚠️).
      await tester.waitUntil(find.text('upload-error-flow'));
      await tester.tap(find.text('upload-error-flow').last);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.waitUntil(
        find.byType(ChatView),
        timeout: const Duration(seconds: 30),
      );

      // Значок ошибки отправки отрисован (наш Tooltip оборачивает Icons.error).
      await tester.waitUntil(
        find.byIcon(Icons.error),
        timeout: const Duration(seconds: 20),
      );
      final tooltip = find.ancestor(
        of: find.byIcon(Icons.error),
        matching: find.byType(Tooltip),
      );
      expect(tooltip, findsWidgets,
          reason: 'значок ошибки должен нести Tooltip с причиной, не голый ⚠️');
    },
  );
}
