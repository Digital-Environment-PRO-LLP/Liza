// ledger:RL-message-select-copy-in-popover
// ignore_for_file: depend_on_referenced_packages
//
// LABA-1964: в поповере сообщения вернули выделение ЧАСТИ текста и копирование
// фрагмента (Liza 1:1). Механизм — прозрачный живой [SelectableTextOverlay]
// поверх снимка пузыря: вёрстка идентична снимку, значит подсветка выделения
// ложится на глифы снимка, а «Копировать» кладёт выделенный фрагмент.
//
// Страж проверяет ДВА яруса:
//   1. ЧИСТЫЙ гейт `canSelectTextInPopover`/`rendersAsPlainText` — что слой
//      включается ТОЛЬКО для обычного текста, в натуральном размере, вне
//      защищённого канала (AC-3/AC-4).
//   2. РЕАЛЬНЫЙ рендер `SelectableTextOverlay` — что текст обёрнут в
//      [SelectionArea] (выделяем) и несёт настоящий текст события (AC-1/AC-2).
//   Живое перетаскивание ручек + буфер обмена — ручной девайс-чек (AC-6).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/message_content.dart';
import 'package:liza/pages/chat/events/message_context_menu.dart';
import 'package:liza/pages/chat/events/xl_buttons_content.dart';
import 'package:liza/utils/channel_peek.dart';
import 'package:liza/utils/stories/story_model.dart';
import 'package:liza/widgets/matrix.dart' as liza_matrix;

import '../../../utils/test_client.dart';

class _TestMatrixState extends liza_matrix.MatrixState {
  _TestMatrixState(this._client);
  final Client _client;
  @override
  Client get client => _client;
}

Event _ev(Client c, Map<String, Object?> content) => Event(
      type: 'm.room.message',
      eventId: '\$e${content.hashCode}:x',
      senderId: '@u:x',
      originServerTs: DateTime.now(),
      room: Room(id: '!r:x', client: c),
      content: content,
    );

void main() {
  late Client client;
  setUpAll(() async => client = await prepareTestClient(loggedIn: true));
  tearDownAll(() => client.dispose());

  group('гейт rendersAsPlainText (какие сообщения выделяемы)', () {
    test('обычный m.text — да', () {
      expect(
        rendersAsPlainText(_ev(client, {'msgtype': 'm.text', 'body': 'привет'})),
        isTrue,
      );
    });

    test('форматированный текст (HTML) — да', () {
      expect(
        rendersAsPlainText(_ev(client, {
          'msgtype': 'm.text',
          'body': 'жирный',
          'format': 'org.matrix.custom.html',
          'formatted_body': '<b>жирный</b>',
        })),
        isTrue,
      );
    });

    // AC:RL-message-select-copy-in-popover/5 — только текст выделяем, не медиа/карточки.
    test('картинка/видео/стикер/аудио/файл/гео — нет', () {
      for (final mt in [
        MessageTypes.Image,
        MessageTypes.Video,
        MessageTypes.Sticker,
        MessageTypes.Audio,
        MessageTypes.File,
        MessageTypes.Location,
        MessageTypes.BadEncrypted,
      ]) {
        expect(
          rendersAsPlainText(_ev(client, {'msgtype': mt, 'body': 'x'})),
          isFalse,
          reason: '$mt не обычный текст',
        );
      }
    });

    test('мини-апп-карточки — нет', () {
      for (final mt in [
        'com.liza.miniapp.launch',
        'com.liza.miniapp.choice',
        'com.liza.miniapp.list',
        'com.liza.miniapp.data',
      ]) {
        expect(
          rendersAsPlainText(_ev(client, {'msgtype': mt, 'body': 'x'})),
          isFalse,
          reason: '$mt — карточка, не текст',
        );
      }
    });

    test('XL-кнопки и story-ref (карточки поверх текста) — нет', () {
      expect(
        rendersAsPlainText(_ev(client, {
          'msgtype': 'm.text',
          'body': 'меню',
          XlButtonsContent.contentKey: {'buttons': []},
        })),
        isFalse,
      );
      expect(
        rendersAsPlainText(_ev(client, {
          'msgtype': 'm.text',
          'body': 'сториз',
          storyRefKey: {'event_id': '\$s'},
        })),
        isFalse,
      );
    });

    test('не-Message тип (состояние комнаты) — нет', () {
      final stateEvent = Event(
        type: EventTypes.RoomMember,
        eventId: '\$m:x',
        senderId: '@u:x',
        stateKey: '@u:x',
        originServerTs: DateTime.now(),
        room: Room(id: '!r:x', client: client),
        content: {'membership': 'join'},
      );
      expect(rendersAsPlainText(stateEvent), isFalse);
    });
  });

  group('гейт canSelectTextInPopover (условия включения слоя)', () {
    Event textEvent() => _ev(client, {'msgtype': 'm.text', 'body': 'привет'});

    test('обычный текст + натуральный размер + без защиты → да', () {
      expect(
        canSelectTextInPopover(
          event: textEvent(),
          contentProtected: false,
          bubbleFullSize: true,
        ),
        isTrue,
      );
    });

    // AC:RL-message-select-copy-in-popover/4 — защищённый канал не выделяем.
    test('защищённый канал → нет (AC-4: не открываем путь выноса)', () {
      expect(
        canSelectTextInPopover(
          event: textEvent(),
          contentProtected: true,
          bubbleFullSize: true,
        ),
        isFalse,
      );
    });

    // AC:RL-message-select-copy-in-popover/3 — длинный/масштабированный пузырь не выделяем.
    test('отмасштабированный/длинный пузырь (не натуральный) → нет (AC-3)', () {
      expect(
        canSelectTextInPopover(
          event: textEvent(),
          contentProtected: false,
          bubbleFullSize: false,
        ),
        isFalse,
      );
    });

    test('медиа даже при натуральном размере → нет', () {
      expect(
        canSelectTextInPopover(
          event: _ev(client, {'msgtype': MessageTypes.Image, 'body': 'x'}),
          contentProtected: false,
          bubbleFullSize: true,
        ),
        isFalse,
      );
    });
  });

  group('реальный рендер SelectableTextOverlay (AC-1/AC-2)', () {
    testWidgets('текст обёрнут в SelectionArea и несёт настоящий текст',
        (tester) async {
      late final Client c;
      await tester.runAsync(() async {
        c = await prepareTestClient(loggedIn: true);
      });
      addTearDown(c.dispose);

      final room = buildPeekRoom(c, '!channel:example.invalid');
      final events = peekEventsToTimeline([
        MatrixEvent(
          type: EventTypes.Message,
          eventId: '\$post',
          senderId: '@author:example.invalid',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
          content: {'msgtype': 'm.text', 'body': 'скопируй эти слова'},
        ),
      ], room);
      final timeline = buildPeekTimeline(room, events);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Provider<liza_matrix.MatrixState>.value(
            value: _TestMatrixState(c),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: SelectableTextOverlay(
                    event: timeline.events.first,
                    timeline: timeline,
                    ownMessage: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // AC:RL-message-select-copy-in-popover/1 — текст живёт внутри SelectionArea
      // (значит выделяем ручками/двойным тапом на девайсе).
      expect(find.byType(SelectionArea), findsOneWidget);
      // AC:RL-message-select-copy-in-popover/2 — слой рендерит РЕАЛЬНЫЙ
      // MessageContent с текстом события: копия положит в буфер именно эти слова.
      expect(find.byType(MessageContent), findsOneWidget);
      expect(find.textContaining('скопируй эти слова'), findsOneWidget);
    });
  });
}
