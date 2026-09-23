// Опросы Liza News: карточка в ленте (реальный Message → message_content →
// NewsPollContent), голос to-device без событий в комнате, только свой выбор,
// «Результаты» только разработчику.
// Спека: docs/superpowers/specs/2026-09-21-liza-news-polls-design.md
//
// ledger:RL-liza-news-poll-card
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/message.dart';
import 'package:liza/pages/chat/events/news_poll_content.dart';
import 'package:liza/pages/chat/news_poll_results_page.dart';
import 'package:liza/utils/news_poll.dart';
import 'package:liza/widgets/avatar.dart';
import 'package:liza/widgets/matrix.dart' as liza_matrix;

import '../../../utils/test_client.dart';

class _TestMatrixState extends liza_matrix.MatrixState {
  _TestMatrixState(this._client);

  final Client _client;

  @override
  Client get client => _client;
}

const _bot = '@liza-news:bots.liza.ru';
const _mallory = '@mallory:example.invalid';

Map<String, Object?> _card({
  bool multiple = false,
  bool closed = false,
  String text = 'Вышла Liza 3763',
}) => {
  'msgtype': newsPollMsgType,
  'body':
      'Вышла Liza 3763\n\n📊 Опрос: Как вам обновление?\n1. Отлично\n2. Плохо',
  newsPollMsgType: {
    'poll_id': 'p1',
    'text': text,
    'question': 'Как вам обновление?',
    'answers': [
      {'id': 'a1', 'text': 'Отлично'},
      {'id': 'a2', 'text': 'Нормально'},
      {'id': 'a3', 'text': 'Плохо'},
    ],
    'max_selections': multiple ? 3 : 1,
    'bot_device': 'BOTDEV',
    'closed': closed,
  },
};

void main() {
  late Client client;
  late _TestMatrixState matrix;

  Future<void> initClient(WidgetTester tester) async {
    await tester.runAsync(() async {
      client = await prepareTestClient(loggedIn: true);
    });
    matrix = _TestMatrixState(client);
    // Штатный обработчик FakeMatrixApi прогоняет PUT account_data через
    // транзакцию sqflite → в фейковом времени виджет-теста она не завершается.
    // Запись всё равно видна в calledEndpoints.
    FakeMatrixApi.currentApi!.api['PUT']!['/client/v3/user/'
        '${Uri.encodeComponent(client.userID!)}/account_data/'
        '$newsPollVotesAccountDataType'] = (_) =>
        {};
    NewsPollService.resetForTest();
    addTearDown(NewsPollService.resetForTest);
    // dispose закрывает sqflite (реальный I/O) — только вне фейкового времени.
    addTearDown(() => tester.runAsync(client.dispose));
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    String sender = _bot,
    Map<String, Object?>? content,
  }) async {
    final room = Room(
      id: '!news:bots.liza.ru',
      client: client,
      membership: Membership.join,
    );
    final event = Event(
      type: EventTypes.Message,
      eventId: '\$poll',
      senderId: sender,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
      content: content ?? _card(),
      room: room,
    );
    final timeline = Timeline(
      room: room,
      chunk: TimelineChunk(events: [event], nextBatch: ''),
    );
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ru'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Provider<liza_matrix.MatrixState>.value(
          value: matrix,
          child: Scaffold(
            body: ListView(
              controller: scrollController,
              children: [
                Message(
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
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  // Живой Client и FakeMatrixApi держат таймеры (задержки ответов, повторы
  // голоса): снимаем дерево, гасим сервис и прокручиваем время до конца.
  Future<void> drain(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    NewsPollService.resetForTest();
    await tester.pump(NewsPollService.ackTimeout * 4);
  }

  List<Map<String, dynamic>> toDeviceCalls(String type) => [
    for (final entry in FakeMatrixApi.calledEndpoints.entries)
      if (entry.key.contains('/client/v3/sendToDevice/$type/'))
        for (final body in entry.value)
          Map<String, dynamic>.from(
            (body is String ? jsonDecode(body) : body) as Map,
          ),
  ];

  bool roomSendCalled() => FakeMatrixApi.calledEndpoints.keys.any(
    (k) => k.contains('/rooms/') && k.contains('/send/'),
  );

  // AC:RL-liza-news-poll-card/3
  testWidgets(
    'опрос от @liza-news (ai): текст, вопрос, варианты; ни счётчиков, '
    'ни процентов, ни аватарок',
    (tester) async {
      await initClient(tester);
      await pumpCard(tester);
      expect(find.text('Вышла Liza 3763'), findsOneWidget);
      expect(find.text('Как вам обновление?'), findsOneWidget);
      for (final a in ['Отлично', 'Нормально', 'Плохо']) {
        expect(find.text(a), findsOneWidget);
      }
      expect(find.text('Опрос · не анонимный'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining('Голосов'), findsNothing);
      expect(find.textContaining('Проголосовали'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(NewsPollContent),
          matching: find.byType(Avatar),
        ),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('news-poll-results')), findsNothing);
      await drain(tester);
    },
  );

  // AC:RL-liza-news-poll-card/9
  testWidgets('та же карточка от постороннего — только текст body, голосовать '
      'нельзя', (tester) async {
    await initClient(tester);
    await pumpCard(tester, sender: _mallory);
    expect(find.byKey(const ValueKey('news-poll-answer-a1')), findsNothing);
    expect(
      find.textContaining('📊 Опрос: Как вам обновление?'),
      findsOneWidget,
    );
    await drain(tester);
  });

  // AC:RL-liza-news-poll-card/1
  testWidgets('голос уходит to-device на устройство бота, в комнату — ничего', (
    tester,
  ) async {
    await initClient(tester);
    await pumpCard(tester);
    FakeMatrixApi.calledEndpoints.clear();

    await tester.tap(find.byKey(const ValueKey('news-poll-answer-a2')));
    await tester.pump();
    expect(find.text('Отправляется…'), findsOneWidget);
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 50)),
    );

    final calls = toDeviceCalls(newsPollVoteType);
    expect(calls, hasLength(1));
    final vote = (calls.single['messages'] as Map)[_bot]['BOTDEV'] as Map;
    expect(vote['poll_id'], 'p1');
    expect(vote['answers'], ['a2']);
    expect(vote['seq'], isA<int>());
    expect(roomSendCalled(), isFalse);

    await drain(tester);
  });

  // AC:RL-liza-news-poll-card/5
  testWidgets('нет ack — три попытки с ОДНИМ seq, затем «Не удалось '
      'проголосовать» и откат выбора', (tester) async {
    await initClient(tester);
    await pumpCard(tester);
    FakeMatrixApi.calledEndpoints.clear();
    await tester.tap(find.byKey(const ValueKey('news-poll-answer-a1')));
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(NewsPollService.ackTimeout);
    }
    await tester.pump();
    final calls = toDeviceCalls(newsPollVoteType);
    expect(calls, hasLength(3));
    final seqs = {
      for (final c in calls)
        ((c['messages'] as Map)[_bot]['BOTDEV'] as Map)['seq'],
    };
    expect(seqs, hasLength(1));
    expect(
      find.text('Не удалось проголосовать. Попробуйте ещё раз'),
      findsOneWidget,
    );
    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('news-poll-answer-a1')),
        matching: find.byType(Icon),
      ),
    );
    expect(icon.icon, Icons.radio_button_unchecked);
    await drain(tester);
  });

  testWidgets(
    'несколько ответов: отметки копятся, голос — по «Проголосовать»',
    (tester) async {
      await initClient(tester);
      await pumpCard(tester, content: _card(multiple: true));
      FakeMatrixApi.calledEndpoints.clear();
      await tester.tap(find.byKey(const ValueKey('news-poll-answer-a1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('news-poll-answer-a3')));
      await tester.pump();
      expect(toDeviceCalls(newsPollVoteType), isEmpty);
      await tester.tap(find.text('Проголосовать'));
      await tester.pump();
      await tester.runAsync(
        () => Future.delayed(const Duration(milliseconds: 50)),
      );
      final vote =
          (toDeviceCalls(newsPollVoteType).single['messages']
                  as Map)[_bot]['BOTDEV']
              as Map;
      expect(vote['answers'], ['a1', 'a3']);
      await drain(tester);
    },
  );

  testWidgets('закрытый опрос: «Опрос закрыт», варианты неактивны', (
    tester,
  ) async {
    await initClient(tester);
    await pumpCard(tester, content: _card(closed: true));
    FakeMatrixApi.calledEndpoints.clear();
    expect(find.text('Опрос закрыт'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('news-poll-answer-a1')));
    await tester.pump();
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 30)),
    );
    expect(toDeviceCalls(newsPollVoteType), isEmpty);
    await drain(tester);
  });

  // AC:RL-liza-news-poll-card/15
  testWidgets('«Результаты» видит только разработчик', (tester) async {
    await initClient(tester);
    matrix.userRoleService.applyOwnAccountData(client.userID!, {
      'role_v2': {'code': 'developer', 'label': 'Разработчик', 'color': null},
    });
    await pumpCard(tester);
    expect(find.byKey(const ValueKey('news-poll-results')), findsOneWidget);
    await drain(tester);
  });

  testWidgets('экран результатов: кто и за что; отказ бота — понятный текст', (
    tester,
  ) async {
    await initClient(tester);
    final room = Room(id: '!news:bots.liza.ru', client: client);
    // Участники уже в состоянии комнаты — экран не дозагружает профили по сети.
    for (final (mxid, name) in [
      ('@ivan:user.liza.ru', 'Иван'),
      ('@anna:liza.cyber-agro.ru', 'Анна'),
    ]) {
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomMember,
          content: {'membership': 'join', 'displayname': name},
          senderId: mxid,
          stateKey: mxid,
        ),
      );
    }
    final poll = NewsPollData.fromContent(_card())!;

    Future<void> pumpPage(Future<NewsPollResults> Function() loader) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: NewsPollResultsPage(
            key: UniqueKey(),
            room: room,
            botMxid: _bot,
            poll: poll,
            loader: loader,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    await pumpPage(
      () async => const NewsPollResults(false, 2, [
        NewsPollOption('a1', 'Отлично', ['@ivan:user.liza.ru']),
        NewsPollOption('a2', 'Нормально', []),
        NewsPollOption('a3', 'Плохо', ['@anna:liza.cyber-agro.ru']),
      ]),
    );
    expect(find.text('Проголосовали: 2'), findsOneWidget);
    expect(find.text('@ivan:user.liza.ru'), findsOneWidget);
    expect(find.text('@anna:liza.cyber-agro.ru'), findsOneWidget);
    expect(find.text('Иван'), findsOneWidget);
    expect(find.text('Голосов: 0'), findsOneWidget);

    await pumpPage(() async => throw const NewsPollForbidden());
    expect(
      find.text('Результаты доступны разработчикам из списка редакции'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 100)),
    );
  });

  // AC:RL-liza-news-poll-card/1
  // ack и account_data — на реальном времени: в фейковом времени widget-теста
  // SDK-путь записи account_data не завершается (виснет teardown).
  test('ack бота: выбор подтверждён, записан в account_data; чужой ack и '
      'ack от не-бота не сбивают голос в полёте', () async {
    final local = await prepareTestClient(loggedIn: true);
    addTearDown(local.dispose);
    void ackLocal(Map<String, Object?> content) => local.onToDeviceEvent.add(
      ToDeviceEvent(sender: _bot, type: newsPollAckType, content: content),
    );
    NewsPollService.resetForTest();
    addTearDown(NewsPollService.resetForTest);
    final service = NewsPollService.of(local);
    final poll = NewsPollData.fromContent(_card())!;
    FakeMatrixApi.calledEndpoints.clear();

    service.vote(_bot, poll, ['a2']);
    final state = service.stateOf('p1');
    expect(state.value.status, NewsPollVoteStatus.sending);
    expect(state.value.shown, ['a2']);
    await Future.delayed(const Duration(milliseconds: 50));
    final vote =
        (toDeviceCalls(newsPollVoteType).single['messages']
                as Map)[_bot]['BOTDEV']
            as Map;

    // Подделка от постороннего и ack чужого запроса — игнорируются.
    local.onToDeviceEvent.add(
      ToDeviceEvent(
        sender: _mallory,
        type: newsPollAckType,
        content: {
          'req_id': vote['req_id'],
          'poll_id': 'p1',
          'answers': ['a3'],
        },
      ),
    );
    ackLocal({
      'req_id': 'other',
      'poll_id': 'p1',
      'answers': ['a1'],
    });
    await Future.delayed(const Duration(milliseconds: 20));
    expect(state.value.status, NewsPollVoteStatus.sending);

    ackLocal({
      'req_id': vote['req_id'],
      'poll_id': 'p1',
      'answers': ['a2'],
      'seq': vote['seq'],
      'closed': false,
    });
    await Future.delayed(const Duration(milliseconds: 200));
    expect(state.value.status, NewsPollVoteStatus.voted);
    expect(state.value.answers, ['a2']);
    expect(state.value.pending, isNull);
    // Запоздавший ответ на «мой голос» (seq старше) не откатывает свежий голос.
    ackLocal({
      'req_id': 'mine-late',
      'poll_id': 'p1',
      'answers': <String>[],
      'seq': 0,
    });
    await Future.delayed(const Duration(milliseconds: 50));
    expect(state.value.answers, ['a2']);

    final puts = FakeMatrixApi.calledEndpoints.entries
        .where(
          (e) => e.key.endsWith('/account_data/$newsPollVotesAccountDataType'),
        )
        .expand((e) => e.value)
        .toList();
    expect(puts, hasLength(1));
    expect(jsonDecode(puts.single as String), {
      'p1': {
        'answers': ['a2'],
        'closed': false,
      },
    });
    expect(
      FakeMatrixApi.calledEndpoints.keys.any(
        (k) => k.contains('/rooms/') && k.contains('/send/'),
      ),
      isFalse,
    );
  });

  // AC:RL-liza-news-poll-editor-flow/14
  testWidgets('пункт «Опрос» виден в чате с ботом и БЕЗ пометки m.direct '
      '(чат создавал бот), но не в канале и не в обычном чате', (tester) async {
    await initClient(tester);
    Room roomWith(String id, List<String> members) {
      final room = Room(id: id, client: client, membership: Membership.join);
      for (final mxid in members) {
        room.setState(
          StrippedStateEvent(
            type: EventTypes.RoomMember,
            content: {'membership': 'join'},
            senderId: mxid,
            stateKey: mxid,
          ),
        );
      }
      return room;
    }

    final me = client.userID!;
    // m.direct пуст → directChatMatrixID == null (так и было у чата с ботом).
    expect(isNewsBotDm(roomWith('!dm:bots.liza.ru', [me, _bot])), isTrue);
    expect(
      isNewsBotDm(roomWith('!news:bots.liza.ru', [me, _bot, '@a:x', '@b:x'])),
      isFalse,
    );
    expect(isNewsBotDm(roomWith('!other:x', [me, _mallory])), isFalse);
  });

  test('pruneStoredVotes: открытые остаются, закрытых — не больше 50', () {
    final votes = <String, Object?>{
      for (var i = 0; i < 60; i++)
        'c$i': {'answers': <String>[], 'closed': true},
      'open': {
        'answers': ['a1'],
        'closed': false,
      },
    };
    final pruned = pruneStoredVotes(votes);
    expect(pruned.containsKey('open'), isTrue);
    expect(pruned.keys.where((k) => k.startsWith('c')), hasLength(50));
    expect(pruned.containsKey('c0'), isFalse);
    expect(pruned.containsKey('c59'), isTrue);
  });
}
