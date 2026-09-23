// ledger:RL-copy-fragment-not-whole-message
// ignore_for_file: depend_on_referenced_packages
//
// Жалоба пользователя (скрин 2026-09-08): «при копировании куска текста из Лизы
// копируется все сообщение целиком» — в буфер уезжал и весь текст, и служебный
// matrix reply-fallback («> <@роман> recording….m4a»), которого в пузыре нет.
//
// Два корня, два яруса стража:
//   1. `copyTextForEvent` звал `calcLocalizedBodyFallback` без `hideReply` —
//      буфер расходился с пузырём (тот рисует с `hideReply: true`).
//   2. Пункт меню «Скопировать текст» игнорировал выделение в живом слое
//      поповера. Теперь слой публикует фрагмент, а пункт кладёт именно его.

import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/message_context_menu.dart';
import 'package:liza/utils/channel_peek.dart';
import 'package:liza/utils/copy_media_eligibility.dart';
import 'package:liza/widgets/matrix.dart' as liza_matrix;

import '../../utils/test_client.dart';

class _TestMatrixState extends liza_matrix.MatrixState {
  _TestMatrixState(this._client);
  final Client _client;
  @override
  Client get client => _client;
}

Event _ev(Client c, Map<String, Object?> content, {String sender = '@u:x'}) =>
    Event(
      type: 'm.room.message',
      eventId: '\$e${content.hashCode}:x',
      senderId: sender,
      originServerTs: DateTime.now(),
      room: Room(id: '!r:x', client: c),
      content: content,
    );

/// Тело сообщения-ответа ровно в том виде, в каком его строит SDK
/// (`room.sendEvent` при `inReplyTo`) — с ним и пришла жалоба.
Map<String, Object?> _replyBody(String quotedSender, String quoted, String own) => {
      'msgtype': 'm.text',
      'body': '> <$quotedSender> $quoted\n\n$own',
      'm.relates_to': {
        'm.in_reply_to': {'event_id': '\$quoted:x'},
      },
    };

void main() {
  late Client client;
  late MatrixLocalizations i18n;
  setUpAll(() async {
    client = await prepareTestClient(loggedIn: true);
    i18n = const MatrixDefaultLocalizations();
  });
  tearDownAll(() => client.dispose());

  group('копия текста = то, что видно в пузыре', () {
    // AC:RL-copy-fragment-not-whole-message/1 — reply-fallback не уезжает в буфер.
    test('ответ на голосовое (кейс жалобы) → только своё тело (AC-1)', () {
      final event = _ev(
        client,
        _replyBody(
          '@roman:x',
          'recording1788888499600193.m4a',
          'Принято, лишнее будет убрано',
        ),
      );
      final copied = copyTextForEvent(event, i18n);
      expect(copied, 'Принято, лишнее будет убрано');
      expect(copied, isNot(contains('recording1788888499600193.m4a')));
      expect(copied, isNot(startsWith('>')));
    });

    test('ответ на текст → только своё тело (AC-1)', () {
      final copied = copyTextForEvent(
        _ev(client, _replyBody('@dima:x', 'исходное сообщение', 'мой ответ')),
        i18n,
      );
      expect(copied, 'мой ответ');
    });

    test('многострочная цитата (≥2 строк) снимается целиком (AC-1)', () {
      final event = _ev(client, {
        'msgtype': 'm.text',
        'body': '> <@dima:x> первая строка\n> вторая строка\n\nмой ответ',
        'm.relates_to': {
          'm.in_reply_to': {'event_id': '\$q:x'},
        },
      });
      expect(copyTextForEvent(event, i18n), 'мой ответ');
    });

    // AC:RL-copy-fragment-not-whole-message/2 — RED-PROOF: строгая SDK-регулярка
    // не трогает БУКВАЛЬНЫЙ блок-квот пользователя (в отличие от нашего мягкого
    // stripReplyFallbackBody, который его бы съел).
    test('пользовательская цитата «> …» НЕ срезается (AC-2)', () {
      final quoteOnly = _ev(client, {
        'msgtype': 'm.text',
        'body': '> он сказал так\n\nа я не согласен',
      });
      expect(
        copyTextForEvent(quoteOnly, i18n),
        '> он сказал так\n\nа я не согласен',
      );

      final noBlankLine = _ev(client, {
        'msgtype': 'm.text',
        'body': '> строка\nпродолжение',
      });
      expect(copyTextForEvent(noBlankLine, i18n), '> строка\nпродолжение');
    });

    // AC:RL-copy-fragment-not-whole-message/3 — мультивыбор: цитата снята,
    // префикс автора сохранён (иначе строки теряют, кто говорил).
    test('мультивыбор сохраняет префикс автора без цитаты (AC-3)', () {
      final copied = copyTextForEvent(
        _ev(client, _replyBody('@roman:x', 'голосовое.m4a', 'мой ответ')),
        i18n,
        withSenderNamePrefix: true,
      );
      expect(copied, endsWith('мой ответ'));
      expect(copied, isNot(contains('голосовое.m4a')));
      expect(copied, isNot(contains('> <@roman:x>')));
    });

    test('обычное сообщение без ответа не меняется (AC-1, регресс-якорь)', () {
      final event = _ev(client, {'msgtype': 'm.text', 'body': 'привет мир'});
      expect(copyTextForEvent(event, i18n), 'привет мир');
    });

    // AC:RL-copy-fragment-not-whole-message/5 — в копию НЕ прокрались флаги
    // превью (plaintextBody/removeMarkdown), иначе «+» стал бы «•»
    // (RL-forced-list-artifact).
    test('форс-список «+» остаётся «+», не «•» (AC-5)', () {
      final event = _ev(client, {
        'msgtype': 'm.text',
        'body': '+ первый\n+ второй',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<ul><li>первый</li><li>второй</li></ul>',
      });
      final copied = copyTextForEvent(event, i18n);
      expect(copied, contains('+'));
      expect(copied, isNot(contains('•')));
    });
  });

  group('живой слой публикует выделенный фрагмент', () {
    // AC:RL-copy-fragment-not-whole-message/4 — реальный SelectableTextOverlay
    // отдаёт выделение наружу (именно это значение пункт меню кладёт в буфер).
    testWidgets('выделение мышью попадает в держатель (AC-4)', (tester) async {
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
          content: {'msgtype': 'm.text', 'body': 'Принято лишнее будет убрано'},
        ),
      ], room);
      final timeline = buildPeekTimeline(room, events);
      final selection = ValueNotifier<String?>(null);
      addTearDown(selection.dispose);

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
                    selection: selection,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Тянем мышью по строке текста — ровно то, что делает пользователь.
      final textRect = tester.getRect(find.byType(SelectionArea));
      final gesture = await tester.startGesture(
        Offset(textRect.left + 4, textRect.center.dy),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(textRect.right - 4, textRect.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(
        selection.value,
        isNotNull,
        reason: 'выделение обязано публиковаться наружу — иначе пункт меню '
            'снова скопирует всё сообщение',
      );
      expect(selection.value, isNotEmpty);
    });

    // AC:RL-copy-fragment-not-whole-message/4 — пояс безопасности: сброс
    // выделения (его делает SelectableRegion при потере фокуса на тапе по
    // пункту меню) НЕ должен обнулять держатель.
    testWidgets('сброс выделения не затирает последнее непустое (AC-4)',
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
          eventId: '\$post2',
          senderId: '@author:example.invalid',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
          content: {'msgtype': 'm.text', 'body': 'будет убрано целиком'},
        ),
      ], room);
      final timeline = buildPeekTimeline(room, events);
      final selection = ValueNotifier<String?>('будет убрано');
      addTearDown(selection.dispose);

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
                    selection: selection,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Тап мимо текста — SelectableRegion чистит выделение (onSelectionChanged
      // получает null). Держатель обязан сохранить прошлое значение.
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();

      expect(selection.value, 'будет убрано');
    });
  });

  // Пункт меню живёт в приватном `_MessageContextMenu`, а `copySelectedText` —
  // метод State-контроллера: собрать их в host-окружении неподъёмно, поэтому
  // проверяем текст гейта рядом с каждой точкой (тот же паттерн, что в
  // `media_content_protection_test.dart`). Сквозной клик-путь закрывает
  // device-flow AC-9.
  group('структурные инварианты (исходник)', () {
    String compact(String path) {
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Тест должен запускаться из clients/flutter/',
      );
      return file.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
    }

    // AC:RL-copy-fragment-not-whole-message/6 — подпись пункта переключается,
    // иначе пользователь не видит, что скопируется фрагмент, а не всё.
    test('пункт меню меняет подпись при выделении (AC-6)', () {
      final source = compact('lib/pages/chat/events/message_context_menu.dart');
      expect(
        source.contains(
          'label: hasSelection ? l10n.copySelection : l10n.copyToClipboard,',
        ),
        isTrue,
        reason: 'подпись обязана отражать, что именно ляжет в буфер',
      );
      expect(
        source.contains('controller.copySelectedText(fragment)'),
        isTrue,
        reason: 'при выделении пункт обязан класть фрагмент, а не всё событие',
      );
    });

    // AC:RL-copy-fragment-not-whole-message/8 — новая точка выноса контента
    // обязана нести гейт В ТЕЛЕ метода (RL-group-content-protection, класс
    // бага 1a76d221), а не только на кнопке.
    test('copySelectedText гейтит защищённый канал в теле (AC-8)', () {
      final source = compact('lib/pages/chat/chat.dart');
      expect(
        source.contains(
          'void copySelectedText(String text) { '
          '// Гейт в самом методе, а не только на пункте меню '
          '(см. copyEventsAction): '
          '// это новая точка выноса контента наружу. '
          'if (room.isContentProtected) return;',
        ),
        isTrue,
        reason: 'без гейта в теле подписчик защищённого канала вынесет фрагмент',
      );
    });

    // AC:RL-copy-fragment-not-whole-message/7 — chrome пузыря вне выделения,
    // иначе Ctrl+C по выделенному сообщению кладёт «Привет14:32».
    test('время, «изменено», имя и цитата исключены из выделения (AC-7)', () {
      final source = compact('lib/pages/chat/events/message.dart');
      expect(
        source.contains(
          'Widget messageFooter({required bool overlay}) => '
          'SelectionContainer.disabled(',
        ),
        isTrue,
        reason: 'время+статус не должны попадать в копию выделения',
      );
      expect(
        'SelectionContainer.disabled'.allMatches(source).length,
        greaterThanOrEqualTo(4),
        reason: 'ожидаются обёртки: время, «изменено», reply-цитата, имя автора',
      );
    });

    // Ленту НЕ трогаем: правый клик обязан оставаться за поповером/меню ссылки
    // (RL-link-context-menu AC-1/AC-6), а гейт приватности — дословным
    // (его сканирует media_content_protection_test.dart).
    test('выделение в ленте по-прежнему гейтится и без своего тулбара', () {
      final source = compact('lib/pages/chat/chat_event_list.dart');
      expect(
        source.contains(
          'selectable: !PlatformInfos.isMobile && '
          '!event.room.isContentProtected,',
        ),
        isTrue,
      );
      expect(
        source.contains('contextMenuBuilder: (context, selectableRegionState) '
            '=> const SizedBox.shrink(),'),
        isTrue,
        reason: 'свой тулбар в ленте столкнулся бы с поповером на том же жесте',
      );
    });
  });
}
