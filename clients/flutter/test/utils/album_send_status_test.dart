// ledger:RL-album-send-partial-failure
//
// Сводный статус своего альбома, единая точка повтора упавшего медиа и гард
// превью отправляемого видео. Жалоба 2026-09-25: «Какой значок повтора
// нажимать?» / «Тут тоже не понятно все загружено или процесс еще идет».

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:flutter/widgets.dart' show Locale;

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/gallery.dart';
import 'package:liza/utils/failed_send_retry_service.dart';
import 'package:liza/utils/file_description.dart';
import 'package:liza/utils/resend_failed_media.dart';
import 'package:liza/utils/upload_progress_tracker.dart';
import 'package:liza/widgets/mxc_image.dart';
import 'test_client.dart';

({bool isError, bool isSending, bool ownedBySeries}) _m({
  bool error = false,
  bool sending = false,
  bool owned = false,
}) => (isError: error, isSending: sending, ownedBySeries: owned);

Event _video(Room room, String id, {EventStatus status = EventStatus.error}) =>
    Event.fromMatrixEvent(
      MatrixEvent(
        content: {'msgtype': MessageTypes.Video, 'body': 'IMG_7043.mov'},
        type: EventTypes.Message,
        eventId: id,
        senderId: room.client.userID!,
        originServerTs: DateTime.now(),
        unsigned: {'transaction_id': id},
      ),
      room,
      status: status,
    );

MatrixVideoFile _bytes() =>
    MatrixVideoFile(bytes: Uint8List.fromList([0, 0, 0, 1]), name: 'v.mp4');

void main() {
  group('AC:RL-album-send-partial-failure/10 — сводный статус альбома', () {
    test('все отправлены → sent', () {
      expect(
        aggregateGallerySendState([_m(), _m(), _m()]),
        GallerySendState.sent,
      );
    });

    test('якорь отправлен, остальные ещё идут (кейс скрина) → sending, '
        'а не «✓✓»', () {
      expect(
        aggregateGallerySendState([_m(), _m(sending: true), _m(sending: true)]),
        GallerySendState.sending,
      );
    });

    test('упавший, которым владеет идущая серия (дошлёт сама) → sending', () {
      expect(
        aggregateGallerySendState([_m(), _m(error: true, owned: true)]),
        GallerySendState.sending,
      );
    });

    test('упавший вне серии → error, приоритет над sending', () {
      for (final order in [
        [_m(sending: true), _m(error: true)],
        [_m(error: true), _m(sending: true)],
        [_m(), _m(error: true), _m()],
      ]) {
        expect(aggregateGallerySendState(order), GallerySendState.error);
      }
    });
  });

  group('единая точка повтора (FailedMediaResender)', () {
    late Client client;
    late Room room;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
      room = Room(id: '!album:example.invalid', client: client);
      FailedMediaResender.resetForTest();
    });

    tearDown(() async {
      FailedMediaResender.resetForTest();
      await client.dispose(closeDatabase: true);
    });

    test('AC:RL-album-send-partial-failure/8 — байтов нет (перезапуск): '
        'sendAgain НЕ зовётся, сообщение не удаляется', () {
      final e = _video(room, 'txn-missing');
      expect(e.isUnresendableMissingMedia, isTrue);
      expect(FailedMediaResender.resend(e), ResendOutcome.missingMedia);
      expect(FailedMediaResender.isInFlight(e.eventId), isFalse);
    });

    test('AC:RL-album-send-partial-failure/7 — двойной тап по ↻: второй '
        'отсечён, повтор в полёте один', () {
      final e = _video(room, 'txn-double');
      room.sendingFilePlaceholders[e.eventId] = _bytes();
      FailedMediaResender.markInFlightForTest(e.eventId);
      expect(FailedMediaResender.resend(e), ResendOutcome.alreadyInFlight);
    });

    test('AC:RL-album-send-partial-failure/6 — txid во владении серии: ни '
        'ручной ↻, ни авто-досыл его не трогают', () {
      final e = _video(room, 'txn-owned');
      room.sendingFilePlaceholders[e.eventId] = _bytes();
      final tracker = UploadProgressTracker.instance;
      tracker.claimForSeries([e.eventId]);
      addTearDown(() => tracker.releaseFromSeries([e.eventId]));

      expect(FailedMediaResender.resend(e), ResendOutcome.ownedBySeries);
      expect(canAutoResend(e), isFalse);

      tracker.releaseFromSeries([e.eventId]);
      expect(canAutoResend(e), isTrue, reason: 'после серии — снова можно');
    });

    test('авто-досыл не дублирует ручной повтор в полёте', () {
      final e = _video(room, 'txn-manual-inflight');
      room.sendingFilePlaceholders[e.eventId] = _bytes();
      FailedMediaResender.markInFlightForTest(e.eventId);
      expect(canAutoResend(e), isFalse);
    });

    test('релиз серии тикает seriesChanges — оверлеи перерисуют ↻', () {
      final tracker = UploadProgressTracker.instance;
      final before = tracker.seriesChanges.value;
      tracker.claimForSeries(['a']);
      tracker.releaseFromSeries(['a']);
      expect(tracker.seriesChanges.value, before + 2);
    });
  });

  group('AC:RL-album-send-partial-failure/13 — превью отправляемого видео не '
      'декодирует байты MP4', () {
    test('sending + isThumbnail + m.video → гард срабатывает', () {
      expect(
        MxcImage.isSendingVideoThumbnail(
          isSending: true,
          isThumbnail: true,
          msgtype: MessageTypes.Video,
        ),
        isTrue,
      );
    });

    test('фото, отправленное видео и полноразмер — гард НЕ трогает', () {
      for (final (sending, thumb, type) in [
        (true, true, MessageTypes.Image),
        (false, true, MessageTypes.Video),
        (true, false, MessageTypes.Video),
      ]) {
        expect(
          MxcImage.isSendingVideoThumbnail(
            isSending: sending,
            isThumbnail: thumb,
            msgtype: type,
          ),
          isFalse,
          reason: '$sending/$thumb/$type',
        );
      }
    });
  });

  test('AC:RL-album-send-partial-failure/12 — итог «Не отправлено K из N» с '
      'русским plural', () async {
    final ru = await lookupL10n(const Locale('ru'));
    expect(ru.albumNotSentCount(1, 23), 'Не отправлен 1 файл из 23.');
    expect(ru.albumNotSentCount(2, 23), 'Не отправлены 2 файла из 23.');
    expect(ru.albumNotSentCount(5, 23), 'Не отправлено 5 файлов из 23.');
    expect(ru.albumNotSentCount(21, 23), 'Не отправлен 21 файл из 23.');
    final en = await lookupL10n(const Locale('en'));
    expect(en.albumNotSentCount(17, 23), '17 of 23 files were not sent.');
    // Отсылки к «значку повтора», которого у альбома не было, больше нет.
    expect(ru.albumNotSentRetryHint, contains('«!»'));
  });
}
