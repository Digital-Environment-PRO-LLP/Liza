import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat_list/chat_list_body.dart';
import 'package:liza/widgets/matrix.dart';

import 'liza_flows.dart';

/// Device-flow авто-досыла упавшей отправки (`RL-media-autoresend-on-reconnect`,
/// AC-3 на РЕАЛЬНОМ бинаре) — терминальная ошибка НЕ досылается сервисом
/// `FailedSendRetryService`, который живёт в `MatrixState` реального приложения.
///
/// Детерминированный срез: файл > серверного `max_upload_size` даёт ТЕРМИНАЛЬНУЮ
/// `FileTooBigMatrixException` за одну попытку (как `upload_error_flow_test`).
/// Наш сервис на возврате sync такое событие пропускает (terminal ≠ transient) —
/// проверяем, что за несколько sync-циклов оно НЕ продублировалось и НЕ ушло в
/// повторную отправку, а осталось ровно одним error-баблом с причиной в тултипе.
///
/// ⚠️ Позитивный путь (транзиентный сбой → авто-досыл при возврате связи) на
/// здоровом локальном стеке НЕ воспроизводим детерминированно (нельзя надёжно
/// оборвать локальный сокет посреди отдачи и вернуть его так, чтобы `onSyncStatus`
/// дал error→finished) — тот же класс инфра-ограничения, что задокументирован в
/// `upload_error_flow_test` для C1(a). Он покрыт host-стражем
/// `failed_send_retry_service_test.dart` (инъекция потока `onSyncStatus` +
/// реальные `Event`, red-proof AC-1/2/5/6).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'AC:RL-media-autoresend-on-reconnect/7 (device) — терминальная ошибка НЕ '
    'досылается сервисом и не дублируется',
    (tester) async {
      app.main();
      await tester.ensureLizaHome();

      final ctx = tester.element(find.byType(ChatListViewBody));
      final client = Matrix.of(ctx).client;

      // Берём УЖЕ синхронизированную комнату (после ensureLizaHome first-sync
      // завершён, `client.rooms` наполнен). createRoom+waitForRoomInSync тут
      // НЕ годится: на Android-эмуляторе (sync через adb-reverse localhost:8008)
      // join-событие свежесозданной комнаты не долетает в тест-окне и
      // waitForRoomInSync висит без таймаута. Существующая seed-комната этой
      // гонки лишена — она уже в sync. Отправка терминального файла и проверка
      // «сервис не трогает error-событие» от типа комнаты не зависят.
      final room = client.rooms.firstWhere(
        (r) => r.membership == Membership.join,
        orElse: () => throw StateError('нет ни одной join-комнаты в sync'),
      );

      // Заведомо больше локального max_upload_size (50 МБ) → терминальная.
      final tooBig = MatrixFile(
        bytes: Uint8List(60 * 1024 * 1024),
        name: 'too_big.bin',
        mimeType: 'application/octet-stream',
      );
      Object? thrown;
      try {
        await room.sendFileEvent(tooBig);
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isA<MatrixException>(),
          reason: 'ожидали терминальную ошибку, получили: $thrown');

      // Событие осело в error.
      final timeline = await room.getTimeline();
      var errorCount = 0;
      for (var i = 0; i < 40; i++) {
        errorCount =
            timeline.events.where((e) => e.status == EventStatus.error).length;
        if (errorCount >= 1) break;
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(errorCount, 1, reason: 'ожидали ровно одно error-событие');

      // Прокачиваем несколько sync-циклов (сервис слушает onSyncStatus.finished,
      // который прилетает штатно). Терминальное событие НЕ должно ни исчезнуть,
      // ни продублироваться, ни уйти в sending — авто-ретрай его не трогает.
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      final stillError =
          timeline.events.where((e) => e.status == EventStatus.error).length;
      final nowSending =
          timeline.events.where((e) => e.status == EventStatus.sending).length;
      expect(stillError, 1,
          reason: 'терминальное событие продублировалось или исчезло: $stillError');
      expect(nowSending, 0,
          reason: 'терминальное событие ушло в повторную отправку (авто-ретрай '
              'не должен трогать terminal)');

      // Причина на бабле (Дыра 3 / C1(b)) — рендер значка ошибки с тултипом —
      // уже покрыт устройственно проходящим `upload_error_flow_test.dart` (тот
      // же message.dart-путь). Сюда навигацию по чату НЕ тащим: список чатов на
      // общем стенде засорён одноимёнными комнатами от прошлых прогонов, тап по
      // тексту недетерминирован. Уникальная ценность ЭТОГО теста — доказать, что
      // ЖИВОЙ FailedSendRetryService (в MatrixState реального бинаря) НЕ трогает
      // терминальное событие при штатных sync-циклах (проверено выше).
    },
  );
}
