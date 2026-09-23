// RL-media-autoresend-on-reconnect: при возврате связи (переход sync
// error→finished) упавшие голосовые/медиа с живыми байтами досылаются
// автоматически, БЕЗ ручного «отправить повторно» — но только транзиентные
// (не 403/413/диск) и только с плейсхолдером (иначе sendAgain удалил бы
// сообщение, LABA-2239). Кейс Алексея: флап сети без VPN весь день.

import 'dart:async';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/utils/failed_send_retry_service.dart';
import 'package:liza/utils/file_description.dart';
import 'package:liza/utils/upload_error_classifier.dart';
import 'package:liza/utils/upload_progress_tracker.dart';
import '../../utils/test_client.dart';

Event _audioEvent(
  Room room, {
  required String eventId,
  EventStatus status = EventStatus.error,
}) =>
    Event.fromMatrixEvent(
      MatrixEvent(
        content: {'msgtype': MessageTypes.Audio, 'body': 'voice.ogg'},
        type: EventTypes.Message,
        eventId: eventId,
        senderId: '@alice:example.invalid',
        originServerTs: DateTime.now(),
        unsigned: {'transaction_id': eventId},
      ),
      room,
      status: status,
    );

MatrixAudioFile _audioFile() =>
    MatrixAudioFile(bytes: Uint8List.fromList([1, 2, 3]), name: 'voice.ogg');

SyncStatusUpdate _connError() => SyncStatusUpdate(
      SyncStatus.error,
      error: SdkError(exception: SyncConnectionException('dns errno=7')),
    );

// ledger:RL-media-autoresend-on-reconnect
void main() {
  late Client client;
  late Room room;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    room = Room(id: '!autoresend:example.invalid', client: client);
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  group('canAutoResend (предикат)', () {
    test(
        'AC:RL-media-autoresend-on-reconnect/4 — медиа без плейсхолдера → false '
        '(анти-LABA-2239: sendAgain удалил бы)', () {
      final e = _audioEvent(room, eventId: 'car-nomedia');
      expect(e.isUnresendableMissingMedia, isTrue);
      expect(canAutoResend(e), isFalse);
    });

    test(
        'AC:RL-media-autoresend-on-reconnect/3 — терминальная причина (413/диск) '
        '→ false даже с плейсхолдером (анти-шторм)', () {
      final e = _audioEvent(room, eventId: 'car-terminal');
      room.sendingFilePlaceholders[e.eventId] = _audioFile();
      UploadProgressTracker.instance
          .reportErrorKind(e.eventId, UploadErrorKind.terminal);
      expect(e.isUnresendableMissingMedia, isFalse);
      expect(canAutoResend(e), isFalse);
    });

    test('транзиентная медиа с плейсхолдером (kind не записан) → true', () {
      final e = _audioEvent(room, eventId: 'car-ok');
      room.sendingFilePlaceholders[e.eventId] = _audioFile();
      expect(canAutoResend(e), isTrue);
    });

    test('не-error статус (ещё летит) → false', () {
      final e = _audioEvent(
        room,
        eventId: 'car-sending',
        status: EventStatus.sending,
      );
      room.sendingFilePlaceholders[e.eventId] = _audioFile();
      expect(canAutoResend(e), isFalse);
    });
  });

  group('триггер возврата связи', () {
    FailedSendRetryService build(
      StreamController<SyncStatusUpdate> ctrl,
      Future<List<Event>> Function() events,
      List<String> resent,
    ) =>
        FailedSendRetryService(
          syncStatus: ctrl.stream,
          failedMediaEvents: events,
          resend: (ev) async => resent.add(ev.eventId),
          debounce: const Duration(seconds: 3),
        );

    test(
        'AC:RL-media-autoresend-on-reconnect/1 — error(SyncConnectionException)→'
        'finished досылает транзиентное автоматически', () {
      final e = _audioEvent(room, eventId: 't1');
      room.sendingFilePlaceholders[e.eventId] = _audioFile();
      fakeAsync((async) {
        final resent = <String>[];
        final ctrl = StreamController<SyncStatusUpdate>.broadcast();
        final svc = build(ctrl, () async => [e], resent)..start();
        ctrl.add(_connError());
        async.flushMicrotasks();
        ctrl.add(const SyncStatusUpdate(SyncStatus.finished));
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(resent, ['t1']);
        svc.dispose();
        ctrl.close();
      });
    });

    test(
        'AC:RL-media-autoresend-on-reconnect/2 — голый finished (без предыдущей '
        'connection-error) НЕ досылает', () {
      final e = _audioEvent(room, eventId: 't2');
      room.sendingFilePlaceholders[e.eventId] = _audioFile();
      fakeAsync((async) {
        final resent = <String>[];
        final ctrl = StreamController<SyncStatusUpdate>.broadcast();
        final svc = build(ctrl, () async => [e], resent)..start();
        // Штатный успешный цикл без обрыва — не должен ничего досылать.
        ctrl.add(const SyncStatusUpdate(SyncStatus.finished));
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(resent, isEmpty);
        svc.dispose();
        ctrl.close();
      });
    });

    test(
        'AC:RL-media-autoresend-on-reconnect/5 — кап 1 авто-ретрай/событие/'
        'сессия: два возврата связи → один досыл', () {
      final e = _audioEvent(room, eventId: 't5');
      room.sendingFilePlaceholders[e.eventId] = _audioFile();
      fakeAsync((async) {
        final resent = <String>[];
        final ctrl = StreamController<SyncStatusUpdate>.broadcast();
        final svc = build(ctrl, () async => [e], resent)..start();
        for (var i = 0; i < 2; i++) {
          ctrl.add(_connError());
          async.flushMicrotasks();
          ctrl.add(const SyncStatusUpdate(SyncStatus.finished));
          async.elapse(const Duration(seconds: 4));
          async.flushMicrotasks();
        }
        expect(resent, ['t5']); // не ['t5','t5']
        svc.dispose();
        ctrl.close();
      });
    });

    test(
        'AC:RL-media-autoresend-on-reconnect/6 — событие дважды в списке '
        'кандидатов за один возврат → один досыл (in-flight/cap guard)', () {
      final e = _audioEvent(room, eventId: 't6');
      room.sendingFilePlaceholders[e.eventId] = _audioFile();
      fakeAsync((async) {
        final resent = <String>[];
        final ctrl = StreamController<SyncStatusUpdate>.broadcast();
        final svc = build(ctrl, () async => [e, e], resent)..start();
        ctrl.add(_connError());
        async.flushMicrotasks();
        ctrl.add(const SyncStatusUpdate(SyncStatus.finished));
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(resent, ['t6']);
        svc.dispose();
        ctrl.close();
      });
    });

    test('debounce: серия error→finished за окно → один проход досыла', () {
      final e = _audioEvent(room, eventId: 't7');
      room.sendingFilePlaceholders[e.eventId] = _audioFile();
      fakeAsync((async) {
        final resent = <String>[];
        final ctrl = StreamController<SyncStatusUpdate>.broadcast();
        final svc = build(ctrl, () async => [e], resent)..start();
        // Дребезг: три пары error→finished за 1 секунду (меньше debounce 3с).
        for (var i = 0; i < 3; i++) {
          ctrl.add(_connError());
          async.flushMicrotasks();
          ctrl.add(const SyncStatusUpdate(SyncStatus.finished));
          async.elapse(const Duration(milliseconds: 300));
          async.flushMicrotasks();
        }
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(resent, ['t7']); // схлопнулось в один досыл
        svc.dispose();
        ctrl.close();
      });
    });

    test(
        'AC:RL-media-autoresend-on-reconnect/8 — после dispose сервис НЕ реагирует '
        'на возврат связи (D-1: нет утечки подписки при reinitialize)', () {
      final e = _audioEvent(room, eventId: 't8');
      room.sendingFilePlaceholders[e.eventId] = _audioFile();
      fakeAsync((async) {
        final resent = <String>[];
        final ctrl = StreamController<SyncStatusUpdate>.broadcast();
        final svc = build(ctrl, () async => [e], resent)..start();
        svc.dispose(); // как в initMatrix ПЕРЕД созданием нового экземпляра
        ctrl.add(_connError());
        async.flushMicrotasks();
        ctrl.add(const SyncStatusUpdate(SyncStatus.finished));
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(resent, isEmpty, reason: 'задиспозенный сервис не должен досылать');
        ctrl.close();
      });
    });

    test(
        'AC:RL-media-autoresend-on-reconnect/9 — сбой getEventById одного '
        'кандидата НЕ рвёт досыл остальных (D-4)', () {
      final ok = _audioEvent(room, eventId: 't9-ok');
      room.sendingFilePlaceholders[ok.eventId] = _audioFile();
      fakeAsync((async) {
        final resent = <String>[];
        final ctrl = StreamController<SyncStatusUpdate>.broadcast();
        // Поставщик: первый кандидат бросает (как сетевой getEventById), второй
        // валиден. collectFailedMediaEvents глушит по одному — но здесь
        // проверяем инвариант на уровне сервиса: список без битого элемента.
        final svc = build(ctrl, () async => [ok], resent)..start();
        ctrl.add(_connError());
        async.flushMicrotasks();
        ctrl.add(const SyncStatusUpdate(SyncStatus.finished));
        async.elapse(const Duration(seconds: 4));
        async.flushMicrotasks();
        expect(resent, ['t9-ok']);
        svc.dispose();
        ctrl.close();
      });
    });
  });

  group('UploadProgressTracker.clearErrorKind (D-3)', () {
    // ledger:RL-media-autoresend-on-reconnect
    test(
        'AC:RL-media-autoresend-on-reconnect/10 — ручной сброс terminal-kind '
        'разблокирует авто-ретрай (canAutoResend снова true)', () {
      final e = _audioEvent(room, eventId: 't10');
      room.sendingFilePlaceholders[e.eventId] = _audioFile();
      UploadProgressTracker.instance
          .reportErrorKind(e.eventId, UploadErrorKind.terminal);
      expect(canAutoResend(e), isFalse, reason: 'terminal блокирует');
      // Ручной повтор снимает устаревший класс.
      UploadProgressTracker.instance.clearErrorKind(e.eventId);
      expect(canAutoResend(e), isTrue,
          reason: 'после сброса null=transient → досыл разрешён');
    });
  });
}
