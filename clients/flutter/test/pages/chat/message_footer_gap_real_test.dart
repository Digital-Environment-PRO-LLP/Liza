// ledger:RL-message-footer-row
// Страж РЕАЛЬНОГО виджета Message (не реплики `_bubbleBody`): у отредактированного
// текста метка правки («✎ HH:MM», левый угол) и время отправки (правый угол)
// разделены минимальным зазором — в том числе у КОРОТКОГО текста.
//
// Баг 2026-09-24 (Александр Новокшонов, macOS): «Принято» после правки рисовалось
// «✎ 10:3410:34». Футер — Row(spaceBetween) под общим IntrinsicWidth пузыря; если
// текст уже футера, ширина пузыря = сумма ширин меток и spaceBetween делит 0 px.
// От версии ОС не зависит — только от длины текста (у длинного зазор есть).
//
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/message.dart';
import 'package:liza/pages/chat/events/message_time.dart';
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

const _minGap = 8.0;

void main() {
  late Client client;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await client.dispose(closeDatabase: true);
  });

  Room buildRoom() => Room(id: '!room:example.invalid', client: client);

  Event original(Room room, String body) => Event(
    type: EventTypes.Message,
    eventId: '\$orig:example.invalid',
    senderId: '@author:example.invalid',
    originServerTs: DateTime(2026, 9, 24, 10, 34),
    room: room,
    content: {'msgtype': 'm.text', 'body': body},
  );

  Event edit(Room room, String newBody) => Event(
    type: EventTypes.Message,
    eventId: '\$edit:example.invalid',
    senderId: '@author:example.invalid',
    originServerTs: DateTime(2026, 9, 24, 10, 34, 30),
    room: room,
    content: {
      'msgtype': 'm.text',
      'body': '* $newBody',
      'm.new_content': {'msgtype': 'm.text', 'body': newBody},
      'm.relates_to': {
        'rel_type': RelationshipTypes.edit,
        'event_id': '\$orig:example.invalid',
      },
    },
  );

  // Timeline сам агрегирует m.replace из чанка → hasAggregatedEvents(edit)=true.
  Future<void> pumpMessage(
    WidgetTester tester,
    Event event, {
    List<Event> extra = const [],
  }) async {
    final timeline = Timeline(
      room: event.room,
      chunk: TimelineChunk(events: [...extra, event]),
    );
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.runAsync(() async {
      await tester.pumpWidget(
        _wrap(
          ListView.builder(
            reverse: true,
            controller: scrollController,
            itemCount: 1,
            itemBuilder: (context, i) => Message(
              event,
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
          ),
          client,
        ),
      );
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    });
  }

  // Правый край метки правки = правый край её Text рядом с карандашом.
  Rect editLabelRect(WidgetTester tester) {
    final row = find
        .ancestor(
          of: find.byIcon(Icons.edit_outlined),
          matching: find.byType(Row),
        )
        .first;
    return tester.getRect(
      find.descendant(of: row, matching: find.byType(Text)).first,
    );
  }

  // Квантор «оба времени всегда разведены» → мультикейс по длине текста.
  for (final body in ['Принято', 'ок', 'пишу предложение для исправления']) {
    testWidgets(
      'AC-6 отредактированное «$body»: метка правки и время отправки '
      'разделены ≥ $_minGap px и на одном уровне — '
      'AC:RL-message-footer-row/6',
      (tester) async {
        final room = buildRoom();
        await pumpMessage(
          tester,
          original(room, body),
          extra: [edit(room, body)],
        );
        expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

        final editRect = editLabelRect(tester);
        final timeRect = tester.getRect(find.byType(MessageTime));
        expect(
          timeRect.left - editRect.right,
          greaterThanOrEqualTo(_minGap),
          reason: 'время правки и время отправки слиплись («10:3410:34»)',
        );
        expect(
          (editRect.center.dy - timeRect.center.dy).abs(),
          lessThan(2),
          reason: 'оба времени на одном уровне AC:RL-message-footer-row/1',
        );
      },
    );
  }

  testWidgets('AC-6 неотредактированное «ок»: пузырь не расширяется зазором '
      '— AC:RL-message-footer-row/6', (tester) async {
    final room = buildRoom();
    await pumpMessage(tester, original(room, 'ок'));
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    final bubble = tester.getRect(
      find
          .ancestor(
            of: find.byType(MessageTime),
            matching: find.byType(IntrinsicWidth),
          )
          .first,
    );
    final timeRect = tester.getRect(find.byType(MessageTime));
    // Футер = padding(16 слева, 12 справа) + время; зазор при isEdited=false
    // не добавляется, иначе «ок» раздуется на 8 px.
    expect(bubble.width, moreOrLessEquals(16 + timeRect.width + 12, epsilon: 1));
  });
}
