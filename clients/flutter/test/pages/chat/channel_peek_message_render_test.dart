// ledger:RL-channel-peek-live-feed
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/message.dart';
import 'package:liza/utils/channel_peek.dart';
import 'package:liza/widgets/matrix.dart' as liza_matrix;

import '../../utils/test_client.dart';

// Message тянет клиента через Matrix.of(context) (аватар автора, MxcImage).
// Полноценный Matrix-виджет в юнит-тесте неоправданно тяжёл (пуши, VoIP,
// connectivity) — подменяем только геттер client, как в
// widgets/access_admin_panel_test.dart.
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
  testWidgets('пост peek-ленты рисуется настоящим Message, а не ListTile',
      (tester) async {
    // runAsync — sqflite ffi внутри prepareTestClient делает реальный I/O и
    // виснет в fake-async зоне testWidgets (см. channel_subscribe_bar_test).
    late final Client client;
    await tester.runAsync(() async {
      client = await prepareTestClient(loggedIn: true);
    });
    addTearDown(client.dispose);

    final room = buildPeekRoom(client, '!channel:example.invalid');
    final events = peekEventsToTimeline([
      MatrixEvent(
        type: EventTypes.Message,
        eventId: '\$post',
        senderId: '@author:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        content: {'msgtype': 'm.text', 'body': 'текст поста канала'},
      ),
    ], room);
    final timeline = buildPeekTimeline(room, events);
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      _wrap(
        ListView.builder(
          reverse: true,
          controller: scrollController,
          itemCount: timeline.events.length,
          itemBuilder: (context, i) => Message(
            timeline.events[i],
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
    // pumpAndSettle не сходится: живой Client крутит фоновые таймеры.
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('текст поста канала'), findsOneWidget);
    expect(
      find.byType(ListTile),
      findsNothing,
      reason: 'примитивный рендер заменён полноценным пузырём поста',
    );
  });
}
