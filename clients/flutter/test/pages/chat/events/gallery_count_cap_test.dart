// Страж инварианта grace-кап фантомных спиннеров галереи (RL-gallery-count-cap-defensive).
//
// GalleryBubble.build вычисляет expectedCount по двум ветвям:
//   (а) СВЕЖИЙ якорь (anchorAgeMs < 60с) + n задан + членов меньше n + нет
//       redacted → держим спиннеры пока соседи едут (expectedCount = n);
//   (б) СТАРЫЙ якорь (age >= grace) → фактическое число, 0 спиннеров.
//
// Без кап-логики легаси-битый форвард (якорь с n=3, но 1 реальный член, ts
// несколько дней назад) рисовал 2 вечных CircularProgressIndicator.
//
// Тест рендерит РЕАЛЬНЫЙ GalleryBubble (не реплику — инцидент 3704).
//
// ledger:RL-gallery-count-cap-defensive

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/gallery.dart';

import '../../../utils/test_client.dart';

// ---------------------------------------------------------------------------
// Вспомогательные построители событий
// ---------------------------------------------------------------------------

const _gid = 'test-gallery-cap';

/// Член альбома: m.image с полем com.liza.gallery.
///
/// Намеренно БЕЗ поля `url` — MxcImage без URL бросает исключение СРАЗУ
/// (синхронно в isAttachmentInLocalStore → null mxcUrl → throw), избегая
/// pending timer(20s) network timeout. Таймеры только retry backoff (2/4/8/16/30s),
/// которые дрейнятся через _drainMxcTimers.
Event _img(
  Room room, {
  required String id,
  required int i,
  required int n,
  required DateTime ts,
  String? gid,
}) =>
    Event(
      type: 'm.room.message',
      eventId: id,
      senderId: '@alice:example.invalid',
      originServerTs: ts,
      content: {
        'msgtype': 'm.image',
        'body': 'photo_$i',
        // Без 'url': MxcImage.isAttachmentInLocalStore бросает синхронно ->
        // retry backoff only, без timeout(20s) pending timer.
        galleryContentKey: {
          'id': gid ?? _gid,
          'i': i,
          'n': n,
        },
      },
      room: room,
    );

/// Строит Timeline из списка событий.
Timeline _timeline(Room room, List<Event> events) =>
    Timeline(room: room, chunk: TimelineChunk(events: events));

// ---------------------------------------------------------------------------
// Обёртка для рендера
// ---------------------------------------------------------------------------

/// Рендерит GalleryBubble в MaterialApp с локалями.
///
/// MxcImage.isThumbnail=true → networkTimeout=20s → надо дрейнить этот таймер.
/// Retry backoff: 2/4/8/16/30s. Дрейним в _drainMxcTimers.
Future<void> _pumpGallery(
  WidgetTester tester, {
  required Event anchor,
  required Timeline timeline,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: GalleryBubble(anchor, timeline: timeline),
        ),
      ),
    ),
  );
  // Первый кадр — синхронные анимации.
  await tester.pump();
}

/// Дрейнирует pending retry-backoff таймеры MxcImage.
///
/// События создаются БЕЗ mxc URL — isAttachmentInLocalStore бросает синхронно
/// (null mxcUrl) -> нет timeout(20s) pending timer, только retry backoff.
/// Retry delays: 2/4/8/16/30s (retryDuration=2s x 2^attempt, capped 30s).
/// Паттерн с запасом: 3/5/9/17/31s (из deleted_bot_avatar_golden_test.dart).
Future<void> _drainMxcTimers(WidgetTester tester) async {
  for (final delay in const [
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 9),
    Duration(seconds: 17),
    Duration(seconds: 31),
  ]) {
    await tester.pump(delay);
  }
}

// ---------------------------------------------------------------------------
// Тесты
// ---------------------------------------------------------------------------

void main() {
  late Client client;
  late Room room;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    room = Room(id: '!gallery-cap:example.invalid', client: client);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await client.dispose(closeDatabase: true);
  });

  // AC-1 (RED-PROOF): легаси-битый форвард — якорь СТАРЫЙ (2 мин назад),
  // 1 реальный член, n=3. Grace-кап применяется: expectedCount=1 -> 0 спиннеров.
  //
  // До фикса (expectedCount=n=3 всегда): было бы 3 ячейки и 2 спиннера.
  // Тег: AC:RL-gallery-count-cap-defensive/1
  testWidgets(
    'AC:RL-gallery-count-cap-defensive/1 — легаси-форвард (старый ts): '
    '1 ячейка, 0 спиннеров [ledger:RL-gallery-count-cap-defensive]',
    (tester) async {
      // Старый якорь: 2 минуты назад -> age >> 60с grace.
      final oldTs = DateTime.now().subtract(const Duration(minutes: 2));
      final anchor = _img(room, id: r'$anchor-old', i: 0, n: 3, ts: oldTs);
      final tl = _timeline(room, [anchor]);

      await _pumpGallery(tester, anchor: anchor, timeline: tl);
      await _drainMxcTimers(tester);

      // РЕАЛЬНЫЙ виджет отрендерился.
      expect(find.byType(GalleryBubble), findsOneWidget);

      // Grace-кап: expectedCount = members.length = 1 -> 0 спиннеров.
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'AC-1: легаси-битый форвард не должен рисовать фантомные '
            'спиннеры (старый якорь -> кап по факту)',
      );
    },
  );

  // AC-2: свежий грузящийся альбом — 1 реальный член из 3, якорь СВЕЖИЙ (now-1с).
  // expectedCount=n=3 -> 3 ячейки, 2 спиннера держатся.
  // Тег: AC:RL-gallery-count-cap-defensive/2
  testWidgets(
    'AC:RL-gallery-count-cap-defensive/2 — свежий альбом (1 из 3 пришёл): '
    '2 спиннера держатся',
    (tester) async {
      // Свежий якорь: 1 секунда назад -> age << 60с grace.
      final freshTs = DateTime.now().subtract(const Duration(seconds: 1));
      final anchor = _img(room, id: r'$anchor-fresh', i: 0, n: 3, ts: freshTs);
      final tl = _timeline(room, [anchor]);

      await _pumpGallery(tester, anchor: anchor, timeline: tl);
      await _drainMxcTimers(tester);

      expect(find.byType(GalleryBubble), findsOneWidget);

      // expectedCount = n = 3 -> 3 ячейки, 2 спиннера (i=1 и i=2).
      expect(
        find.byType(CircularProgressIndicator),
        findsNWidgets(2),
        reason: 'AC-2: свежий альбом должен держать 2 спиннера пока соседи едут',
      );
    },
  );

  // AC-3: мультикейс различителя — «свежий держит», «старый капит».
  // Параметризованный прогон обоих случаев: старый anchor -> 0 спиннеров,
  // свежий anchor -> 2 спиннера.
  // Тег: AC:RL-gallery-count-cap-defensive/3
  testWidgets(
    'AC:RL-gallery-count-cap-defensive/3 — мультикейс: '
    'старый anchor -> 0 спиннеров; свежий -> 2 спиннера',
    (tester) async {
      // Кейс A: anchor старше grace (5 минут назад).
      final oldTs = DateTime.now().subtract(const Duration(minutes: 5));
      final anchorOld = _img(
        room,
        id: r'$mc-old',
        i: 0,
        n: 3,
        ts: oldTs,
        gid: 'gal-old',
      );
      final tlOld = _timeline(room, [anchorOld]);

      await _pumpGallery(tester, anchor: anchorOld, timeline: tlOld);
      await _drainMxcTimers(tester);

      expect(find.byType(GalleryBubble), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'AC-3 кейс A (старый anchor): кап по факту -> 0 спиннеров',
      );

      // Кейс B: anchor моложе grace (10 секунд назад).
      final freshTs = DateTime.now().subtract(const Duration(seconds: 10));
      final anchorFresh = _img(
        room,
        id: r'$mc-fresh',
        i: 0,
        n: 3,
        ts: freshTs,
        gid: 'gal-fresh',
      );
      final tlFresh = _timeline(room, [anchorFresh]);

      await _pumpGallery(tester, anchor: anchorFresh, timeline: tlFresh);
      await _drainMxcTimers(tester);

      expect(find.byType(GalleryBubble), findsOneWidget);
      expect(
        find.byType(CircularProgressIndicator),
        findsNWidgets(2),
        reason: 'AC-3 кейс B (свежий anchor): держим спиннеры -> 2 спиннера',
      );
    },
  );

  // AC-4: redaction-ветка — hasRedacted=true при свежем якоре.
  //
  // GalleryBubble.hasRedacted смотрит: e.galleryId == gid && e.redacted.
  // При SDK-redaction content очищается -> galleryId=null -> hasRedacted=false.
  // Поэтому создаём m.image-событие с galleryId В content (как до удаления),
  // но помечаем его redacted через unsigned.redacted_because.
  // В результате: e.redacted=true, e.galleryId=_gid -> hasRedacted=true ->
  // expectedCount=members.length независимо от age якоря.
  //
  // Тег: AC:RL-gallery-count-cap-defensive/4
  testWidgets(
    'AC:RL-gallery-count-cap-defensive/4 — redacted-событие с galleryId: '
    'hasRedacted=true -> expectedCount=members.length (0 лишних спиннеров)',
    (tester) async {
      // Свежий якорь: без кап-логики по age дал бы expectedCount=n=3.
      // Но есть redacted-член с galleryId -> hasRedacted=true -> expectedCount=1.
      final freshTs = DateTime.now().subtract(const Duration(seconds: 1));
      final anchor = _img(
        room,
        id: r'$redact-anchor',
        i: 0,
        n: 3,
        ts: freshTs,
      );
      // Redacted-событие: content СОДЕРЖИТ galleryId (как исходное медиа),
      // но помечено как redacted через unsigned. SDK смотрит unsigned, content
      // остаётся в памяти в нашем Event-конструкторе.
      // Без url — MxcImage не создаётся для redacted ячейки (она отфильтровывается
      // _members() по e.redacted=true), поэтому url не нужен.
      final redactedMember = Event(
        type: 'm.room.message',
        eventId: r'$redact-member',
        senderId: '@alice:example.invalid',
        originServerTs: freshTs.subtract(const Duration(milliseconds: 50)),
        content: {
          'msgtype': 'm.image',
          'body': 'photo_1',
          galleryContentKey: {
            'id': _gid,
            'i': 1,
            'n': 3,
          },
        },
        room: room,
        unsigned: {
          'redacted_because': {
            'event_id': r'$redact-event',
            'sender': '@alice:example.invalid',
            'origin_server_ts': 3000,
            'type': 'm.room.redaction',
            'redacts': r'$redact-member',
            'content': <String, dynamic>{},
          },
        },
      );

      final tl = _timeline(room, [anchor, redactedMember]);

      await _pumpGallery(tester, anchor: anchor, timeline: tl);
      await _drainMxcTimers(tester);

      expect(find.byType(GalleryBubble), findsOneWidget);

      // hasRedacted=true (redactedMember.redacted=true, galleryId=_gid).
      // _members() отфильтровывает redactedMember (e.redacted=true).
      // -> members=[anchor], members.length=1.
      // -> expectedCount=members.length=1 -> 0 спиннеров.
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'AC-4: при hasRedacted=true expectedCount=members.length=1, '
            '0 спиннеров независимо от свежего якоря',
      );
    },
  );
}
