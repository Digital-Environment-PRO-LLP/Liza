// ledger:RL-forwarded-attribution
// LABA-1991: пересланное сообщение несёт плашку «Переслано [от X]» над телом.
// Страж РЕАЛЬНОГО виджета Message (не реплики): плашка ForwardedContent видна для
// ЛЮБОГО msgtype (текст/картинка/голос/файл), потому что вставлена ЕДИНОЙ точкой
// над всеми ветками пузыря; подавляется в relay-комнате; отсутствует у обычного
// сообщения. Плюс AC-2/AC-3 на самой плашке (имя есть → «от X», нет → «Переслано»).
//
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/forwarded_content.dart';
import 'package:liza/pages/chat/events/message.dart';
import 'package:liza/widgets/matrix.dart' as liza_matrix;

import '../../utils/test_client.dart';

// Message тянет клиента через Matrix.of(context) — подменяем только геттер client
// (полноценный Matrix-виджет неоправданно тяжёл), как channel_peek_message_render.
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

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await client.dispose(closeDatabase: true);
  });

  Room buildRoom({List<Event> Function(Room)? create}) =>
      Room(id: '!room:example.invalid', client: client);

  Event ev(Room room, Map<String, Object?> content) => Event(
        type: EventTypes.Message,
        eventId: '\$e${content.hashCode}:example.invalid',
        senderId: '@author:example.invalid',
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        room: room,
        content: content,
      );

  Future<void> pumpMessage(WidgetTester tester, Event event) async {
    final timeline = Timeline(
      room: event.room,
      chunk: TimelineChunk(events: [event]),
    );
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final tree = _wrap(
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
    );
    // Прокачка внутри runAsync: медиа-виджеты (MxcImage) заводят реальные
    // retry-таймеры, которые к концу теста висят и роняют fake-планировщик на
    // `!timersPending`. В runAsync таймеры настоящие и планировщиком не считаются.
    await tester.runAsync(() async {
      await tester.pumpWidget(tree);
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });
    // НЕ пампим после runAsync в fake-зоне: пересборка MxcImage там планирует
    // fake-таймер (1мс), который повисает и роняет `!timersPending`. Дерево уже
    // отрендерено внутри runAsync — find работает по последнему кадру.
  }

  Map<String, Object?> forwarded(
    Map<String, Object?> base, {
    String? fromName,
  }) =>
      {
        ...base,
        'com.liza.forwarded': <String, Object?>{
          if (fromName != null) 'from_name': fromName,
        },
      };

  const text = {'msgtype': 'm.text', 'body': 'привет'};
  const image = {
    'msgtype': 'm.image',
    'body': 'pic.jpg',
    'url': 'mxc://example.invalid/pic',
    'info': {'mimetype': 'image/jpeg', 'w': 10, 'h': 10, 'size': 100},
  };
  const audio = {
    'msgtype': 'm.audio',
    'body': 'voice.ogg',
    'url': 'mxc://example.invalid/voice',
    'info': {'mimetype': 'audio/ogg', 'size': 100, 'duration': 3000},
  };
  const file = {
    'msgtype': 'm.file',
    'body': 'doc.pdf',
    'url': 'mxc://example.invalid/doc',
    'info': {'mimetype': 'application/pdf', 'size': 100},
  };

  // AC:RL-forwarded-attribution/1
  // AC-1: плашка появляется для ЛЮБОГО msgtype (единая точка вставки над всеми
  // ветками пузыря). Квантор «любое пересланное» → мультикейс, не один пример.
  for (final entry in <String, Map<String, Object?>>{
    'текст': text,
    'картинка': image,
    'голос': audio,
    'файл': file,
  }.entries) {
    testWidgets('AC-1 пересланный ${entry.key} несёт плашку ForwardedContent', (
      tester,
    ) async {
      final room = buildRoom();
      await pumpMessage(
        tester,
        ev(room, forwarded(entry.value, fromName: 'Иван Петров')),
      );
      expect(
        find.byType(ForwardedContent),
        findsOneWidget,
        reason: 'плашка должна быть над телом любого msgtype (${entry.key})',
      );
    });
  }

  // AC:RL-forwarded-attribution/2
  // AC-2: имя доступно → «Переслано от <Имя>».
  testWidgets('AC-2 имя есть → «Переслано от Иван Петров»', (tester) async {
    final room = buildRoom();
    await pumpMessage(tester, ev(room, forwarded(text, fromName: 'Иван Петров')));
    expect(find.textContaining('Переслано от Иван Петров'), findsOneWidget);
  });

  // AC:RL-forwarded-attribution/3
  // AC-3: имя недоступно (маркер без from_name) → голое «Переслано», НЕ localpart.
  testWidgets('AC-3 имени нет → «Переслано» без «от» и без localpart', (
    tester,
  ) async {
    final room = buildRoom();
    await pumpMessage(tester, ev(room, forwarded(text)));
    expect(find.text('Переслано'), findsOneWidget);
    expect(find.textContaining('Переслано от'), findsNothing);
    expect(find.textContaining('author'), findsNothing);
  });

  // Обычное (не пересланное) сообщение плашки НЕ несёт.
  testWidgets('обычное сообщение — без плашки', (tester) async {
    final room = buildRoom();
    await pumpMessage(tester, ev(room, Map<String, Object?>.from(text)));
    expect(find.byType(ForwardedContent), findsNothing);
  });

  // AC:RL-forwarded-attribution/4
  // AC-4: в relay-комнате «Входящие» (сообщение несёт com.liza.relay) плашка
  // подавлена — автора уже атрибутирует relay, две метки путали бы.
  testWidgets('AC-4 relay-сообщение → плашка подавлена', (tester) async {
    final room = buildRoom();
    final content = forwarded(text, fromName: 'Иван Петров');
    content['com.liza.relay'] = <String, Object?>{'name': 'Клиент Пётр'};
    await pumpMessage(tester, ev(room, content));
    expect(find.byType(ForwardedContent), findsNothing);
  });
}
