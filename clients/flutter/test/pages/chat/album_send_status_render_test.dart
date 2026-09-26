// ledger:RL-album-send-partial-failure
// Страж РЕАЛЬНОГО виджета Message → GalleryBubble (guard.render:real-widget).
//
// Жалоба 2026-09-25 (Александр, iOS, 23 видео альбомом): «Какой значок
// повтора нажимать?» — у плитки альбома значка повтора не было вовсе, упавшее
// видео выглядело отправленным; «Тут тоже не понятно все загружено или процесс
// еще идет» — время альбома «15:10 ✓✓» бралось от якоря i=0.
//
// ignore_for_file: depend_on_referenced_packages

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/message.dart';
import 'package:liza/pages/chat/events/message_time.dart';
import 'package:liza/utils/resend_failed_media.dart';
import 'package:liza/utils/upload_progress_tracker.dart';
import 'package:liza/widgets/matrix.dart' as liza_matrix;

import '../../utils/test_client.dart';

class _TestMatrixState extends liza_matrix.MatrixState {
  _TestMatrixState(this._client);
  final Client _client;
  @override
  Client get client => _client;
}

Widget _wrap(Widget child, Client client) => MaterialApp(
  locale: const Locale('ru'),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: Provider<liza_matrix.MatrixState>.value(
    value: _TestMatrixState(client),
    child: Scaffold(body: child),
  ),
);

void main() {
  late Client client;
  late Room room;
  final tracker = UploadProgressTracker.instance;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    room = Room(id: '!album:example.invalid', client: client);
    FailedMediaResender.resetForTest();
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await client.dispose(closeDatabase: true);
  });

  Event member(int i, EventStatus status, {int n = 3}) => Event(
    type: EventTypes.Message,
    eventId: status.isSent ? '\$v$i:example.invalid' : 'txn-album-$i',
    senderId: client.userID!,
    originServerTs: DateTime(2026, 9, 25, 15, 10, i),
    room: room,
    status: status,
    content: {
      'msgtype': MessageTypes.Video,
      'body': 'IMG_70$i.mov',
      'info': {'mimetype': 'video/mp4', 'duration': 31000},
      'com.liza.gallery': {'id': 'album-1', 'i': i, 'n': n},
    },
    unsigned: status.isSent ? null : {'transaction_id': 'txn-album-$i'},
  );

  Future<void> pumpAlbum(WidgetTester tester, List<Event> members) async {
    final anchor = members.first;
    final timeline = Timeline(
      room: room,
      chunk: TimelineChunk(events: members.reversed.toList()),
    );
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        _wrap(
          ListView(
            controller: scrollController,
            children: [
              Message(
                anchor,
                timeline: timeline,
                scrollController: scrollController,
                colors: const [Colors.grey, Colors.blue],
                onSelect: (_) {},
                onInfoTab: (_) {},
                scrollToEventId: (_) {},
                onSwipe: () {},
                onMention: () {},
                onEdit: () {},
                enterThread: null,
              ),
            ],
          ),
          client,
        ),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
  }

  MessageTime albumTime(WidgetTester tester) =>
      tester.widget<MessageTime>(find.byType(MessageTime).first);

  testWidgets(
    'AC:RL-album-send-partial-failure/7 — упавшая плитка альбома показывает ↻ '
    'с подписью; AC:RL-album-send-partial-failure/10 — у альбома «!», не «✓✓»',
    (tester) async {
      await pumpAlbum(tester, [
        member(0, EventStatus.synced),
        member(1, EventStatus.error),
        member(2, EventStatus.synced),
      ]);

      expect(
        find.byKey(const ValueKey('upload-retry-txn-album-1')),
        findsOneWidget,
        reason: 'значок повтора есть ровно на упавшей плитке',
      );
      expect(
        find.byKey(const ValueKey('upload-retry-txn-album-0')),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel('Попробуйте отправить ещё раз'),
        findsWidgets,
      );

      final time = albumTime(tester);
      expect(time.isError, isTrue, reason: 'статус альбома — по всем членам');
      expect(find.byKey(const ValueKey('album-unsent-status')), findsOneWidget);
    },
  );

  testWidgets(
    'AC:RL-album-send-partial-failure/10 — якорь отправлен, остальные идут '
    '(кейс скрина): часы, а не «✓✓»; AC:RL-album-send-partial-failure/9 — '
    'идущая плитка показывает прогресс',
    (tester) async {
      tracker.register('txn-album-1');
      tracker.register('txn-album-2');
      addTearDown(() {
        tracker.unregister('txn-album-1');
        tracker.unregister('txn-album-2');
      });
      await pumpAlbum(tester, [
        member(0, EventStatus.synced),
        member(1, EventStatus.sending),
        member(2, EventStatus.sending),
      ]);

      final time = albumTime(tester);
      expect(time.isSending, isTrue);
      expect(time.isError, isFalse);
      // Кольцо прогресса на каждой идущей плитке.
      expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(2));
    },
  );

  testWidgets(
    'AC:RL-album-send-partial-failure/6 — упавший член идущей серии: вместо ↻ '
    '«Ожидание сети», альбом — часы',
    (tester) async {
      tracker.register('txn-album-1');
      tracker.reportPhase('txn-album-1', UploadPhase.waitingNetwork);
      tracker.claimForSeries(['txn-album-1']);
      addTearDown(() {
        tracker.releaseFromSeries(['txn-album-1']);
        tracker.unregister('txn-album-1');
      });
      await pumpAlbum(tester, [
        member(0, EventStatus.synced),
        member(1, EventStatus.error),
      ]);

      expect(
        find.byKey(const ValueKey('upload-retry-txn-album-1')),
        findsNothing,
      );
      expect(find.text('Ожидание сети'), findsOneWidget);
      expect(albumTime(tester).isSending, isTrue);
      expect(albumTime(tester).isError, isFalse);
    },
  );

  testWidgets(
    'AC:RL-album-send-partial-failure/8 — ↻ без байтов в памяти (перезапуск): '
    'тост, сообщение НЕ удалено',
    (tester) async {
      final failed = member(1, EventStatus.error);
      await pumpAlbum(tester, [member(0, EventStatus.synced), failed]);
      expect(room.sendingFilePlaceholders[failed.eventId], isNull);

      await tester.tap(find.byKey(const ValueKey('upload-retry-txn-album-1')));
      await tester.pump();

      expect(
        find.text('Файл больше недоступен — отправить повторно нельзя'),
        findsOneWidget,
      );
      expect(FailedMediaResender.isInFlight(failed.eventId), isFalse);
      expect(
        find.byKey(const ValueKey('upload-retry-txn-album-1')),
        findsOneWidget,
        reason: 'плитка на месте',
      );
    },
  );

  testWidgets(
    'AC:RL-album-send-partial-failure/7 — ↻ плитки идёт через единую точку '
    'повтора: второй тап при повторе в полёте ничего не запускает',
    (tester) async {
      final failed = member(1, EventStatus.error);
      room.sendingFilePlaceholders[failed.eventId] = MatrixVideoFile(
        bytes: Uint8List.fromList([0, 0, 0, 1]),
        name: 'IMG_701.mov',
      );
      await pumpAlbum(tester, [member(0, EventStatus.synced), failed]);
      // Первый тап уже запустил повтор (сама заливка в host-тесте не
      // гоняется — SDK крутил бы свой цикл повторов на фейковых часах).
      FailedMediaResender.markInFlightForTest(failed.eventId);

      await tester.tap(find.byKey(const ValueKey('upload-retry-txn-album-1')));
      await tester.pump();

      expect(FailedMediaResender.isInFlight(failed.eventId), isTrue);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        room.sendingFilePlaceholders[failed.eventId],
        isNotNull,
        reason: 'байты для повтора не тронуты',
      );
    },
  );

  testWidgets(
    'AC:RL-album-send-partial-failure/11 — тап по «!» альбома открывает меню '
    '«Повторить / Удалить неотправленные (K)»',
    (tester) async {
      await pumpAlbum(tester, [
        member(0, EventStatus.synced),
        member(1, EventStatus.error),
        member(2, EventStatus.error),
      ]);

      await tester.tap(find.byKey(const ValueKey('album-unsent-status')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Повторить неотправленные (2)'), findsOneWidget);
      expect(find.text('Удалить неотправленные (2)'), findsOneWidget);
      expect(find.text('Не отправлены 2 файла из 3.'), findsWidgets);
    },
  );
}
