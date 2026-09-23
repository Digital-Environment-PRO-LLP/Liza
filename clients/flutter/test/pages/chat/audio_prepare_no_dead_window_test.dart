// Страж инварианта «у подготовки аудио нет мёртвого окна»
// (RL-audio-prepare-no-dead-window).
//
// Рендерит РЕАЛЬНЫЙ `AudioPlayerWidget` (не реплику): проверяемая величина —
// что нарисовано В СЛОТЕ КНОПКИ конкретного пузыря и нажимается ли оно. Финдеры
// строго `find.descendant` от слота: в том же ряду контролов живёт спиннер
// транскрибации 20×20, и глобальный `find.byType(CircularProgressIndicator)`
// был бы ложно-зелёным.
//
// Red-proof на коде ДО фикса:
//  - AC-1/AC-2 — `preparingAudio` не существовал, спиннер рисовался только по
//    локальному `status`, поэтому пузырь авто-перехода показывал play;
//  - AC-4 — `isAtEndPosition` при `duration == null` возвращал `true`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/pages/chat/events/audio_player.dart';
import 'package:liza/widgets/matrix.dart';

import '../../utils/test_client.dart';

// Страж реестра регрессии: ledger:RL-audio-prepare-no-dead-window
void main() {
  late Client client;
  late Room room;
  late SharedPreferences store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // loggedIn обязателен: `room.isContentProtected` читает `ownPowerLevel`,
    // который разыменовывает `client.userID!`.
    client = await prepareTestClient(loggedIn: true);
    // Иначе sync-петля остаётся pending после dispose дерева виджетов.
    client.backgroundSync = false;
    // `Matrix.initState` уходит в ФОНОВЫЙ прогрев профилей DM-героев по всем
    // комнатам из sync'а; его таймеры FakeMatrixApi переживают dispose дерева и
    // роняют тест на «A Timer is still pending». Плееру комнаты из sync'а не
    // нужны — он рендерит переданный ему Event.
    client.rooms.clear();
    room = Room(id: '!prep:example.invalid', client: client);
    store = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  Event voice(String id) => Event(
    eventId: id,
    senderId: '@a:example.invalid',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(2000),
    type: EventTypes.Message,
    content: {
      'msgtype': MessageTypes.Audio,
      'body': 'voice',
      'url': 'mxc://x/$id',
      'org.matrix.msc3245.voice': <String, dynamic>{},
      'info': {'duration': 50000, 'size': 479259, 'mimetype': 'audio/ogg'},
    },
    room: room,
    status: EventStatus.synced,
  );

  /// Ключ, по которому находим ИМЕННО слот кнопки воспроизведения (36×36),
  /// а не любой прогресс-индикатор в ряду контролов.
  Finder buttonSlot(Finder bubble) => find.descendant(
    of: bubble,
    matching: find.byWidgetPredicate(
      (w) => w is SizedBox && w.width == 36 && w.height == 36,
    ),
  );

  /// Догоняет отложенные таймеры harness'а (прогрев DM-профилей идёт по
  /// комнатам ПОСЛЕДОВАТЕЛЬНО, поэтому одного-двух pump'ов не хватает).
  Future<void> drain(WidgetTester tester) async {
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<MatrixState> pumpBubble(WidgetTester tester, Event event) async {
    late MatrixState matrix;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [],
        home: Matrix(
          clients: [client],
          store: store,
          child: Builder(
            builder: (context) {
              matrix = Matrix.of(context);
              return Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 320,
                    child: AudioPlayerWidget(
                      event,
                      color: Colors.black,
                      linkColor: Colors.blue,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    // `Matrix.initState` уходит в сеть за профилями DM-героев через
    // FakeMatrixApi — её таймеры надо дать доиграть, иначе тест падает на
    // «A Timer is still pending even after the widget tree was disposed».
    await tester.pump();
    await drain(tester);
    return matrix;
  }

  testWidgets(
    'AC-1: пока идёт подготовка ЭТОГО трека, в слоте кнопки — индикатор, '
    'а не кнопка play — AC:RL-audio-prepare-no-dead-window/1',
    (tester) async {
      final e1 = voice('\$e1');
      final matrix = await pumpBubble(tester, e1);
      final bubble = find.byType(AudioPlayerWidget);

      // Контроль-негатив: без подготовки в слоте именно кнопка play.
      expect(
        find.descendant(
          of: buttonSlot(bubble),
          matching: find.byIcon(Icons.play_arrow_outlined),
        ),
        findsOneWidget,
        reason: 'до подготовки в слоте обязана быть кнопка play',
      );

      matrix.preparingAudio.value = (eventId: e1.eventId, progress: null);
      await tester.pump();

      expect(
        find.descendant(
          of: buttonSlot(bubble),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
        reason: 'фаза подготовки обязана быть видна индикатором в слоте кнопки',
      );
      expect(
        find.descendant(
          of: buttonSlot(bubble),
          matching: find.byIcon(Icons.play_arrow_outlined),
        ),
        findsNothing,
        reason: 'во время подготовки в слоте не должно оставаться кнопки play',
      );
      await drain(tester);
    },
  );

  testWidgets(
    'AC-2: подготовка ЧУЖОГО трека не превращает наш пузырь в спиннер '
    '— AC:RL-audio-prepare-no-dead-window/2',
    (tester) async {
      final e1 = voice('\$e1');
      final matrix = await pumpBubble(tester, e1);
      final bubble = find.byType(AudioPlayerWidget);

      matrix.preparingAudio.value = (eventId: '\$other', progress: null);
      await tester.pump();

      expect(
        find.descendant(
          of: buttonSlot(bubble),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
        reason: 'спиннер обязан появляться только у ГОТОВЯЩЕГОСЯ пузыря',
      );
      expect(
        find.descendant(
          of: buttonSlot(bubble),
          matching: find.byIcon(Icons.play_arrow_outlined),
        ),
        findsOneWidget,
      );
      await drain(tester);
    },
  );

  testWidgets(
    'AC-3: тап по индикатору отменяет подготовку — кнопка возвращается '
    'и НЕ игнорируется — AC:RL-audio-prepare-no-dead-window/3',
    (tester) async {
      final e1 = voice('\$e1');
      final matrix = await pumpBubble(tester, e1);
      final bubble = find.byType(AudioPlayerWidget);

      matrix.preparingAudio.value = (eventId: e1.eventId, progress: null);
      await tester.pump();

      await tester.tap(
        find.descendant(
          of: buttonSlot(bubble),
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        matrix.preparingAudio.value,
        isNull,
        reason: 'тап во время подготовки обязан её ОТМЕНЯТЬ, а не быть no-op',
      );
      expect(
        find.descendant(
          of: buttonSlot(bubble),
          matching: find.byIcon(Icons.play_arrow_outlined),
        ),
        findsOneWidget,
        reason: 'после отмены пузырь обязан вернуться в тапабельное состояние',
      );
      expect(
        matrix.audioPlayer,
        isNull,
        reason: 'отмена не должна заводить плеер',
      );
      expect(tester.takeException(), isNull);
      await drain(tester);
    },
  );

  testWidgets(
    'AC-5: прогресс подготовки прокидывается в индикатор '
    '— AC:RL-audio-prepare-no-dead-window/5',
    (tester) async {
      final e1 = voice('\$e1');
      final matrix = await pumpBubble(tester, e1);
      final bubble = find.byType(AudioPlayerWidget);

      matrix.preparingAudio.value = (eventId: e1.eventId, progress: 0.42);
      await tester.pump();

      final indicator = tester.widget<CircularProgressIndicator>(
        find.descendant(
          of: buttonSlot(bubble),
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      expect(indicator.value, closeTo(0.42, 0.001));
      await drain(tester);
    },
  );
}
