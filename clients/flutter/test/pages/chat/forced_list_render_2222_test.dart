// LABA-2222 (жалоба Нади, сборка 3699): проверяем РЕАЛЬНЫЙ рендер виджетов на
// точных структурах события, а не только чистую функцию. Цель — найти, есть ли
// разрыв между «isForcedListArtifact=true» и тем, что рисует пузырь/цитата.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/html_message.dart';
import 'package:liza/pages/chat/events/reply_content.dart';

import '../../utils/test_client.dart';

Event _ev(Client c, Map<String, Object?> content) => Event(
      type: 'm.room.message',
      eventId: '\$e${content.hashCode}:x',
      senderId: '@nadya:x',
      originServerTs: DateTime.now(),
      room: Room(id: '!r:x', client: c),
      content: content,
    );

// Что message_content выбрал бы для пузыря: formattedText, если это НЕ артефакт;
// иначе плейн-body (escaped). Точная копия ветки из message_content.dart.
String _bubbleHtml(Event e) {
  final isHtml = e.content['format'] == 'org.matrix.custom.html' &&
      e.formattedText.isNotEmpty &&
      !isForcedListArtifact(e.body, e.formattedText);
  return isHtml
      ? e.formattedText
      : e.calcUnlocalizedBody(hideReply: true).replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

Future<void> _pump(WidgetTester t, Widget w) async {
  await t.pumpWidget(MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: const [
      L10n.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(body: w),
  ));
  await t.pumpAndSettle();
}

void main() {
  late Client client;
  setUpAll(() async => client = await prepareTestClient(loggedIn: true));

  Widget bubble(Event e) => HtmlMessage(
        html: _bubbleHtml(e),
        room: e.room,
        fontSize: 14,
        linkStyle: const TextStyle(),
        onOpen: (_) {},
      );

  group('ПУЗЫРЬ (message_content) — списки «+/-»', () {
    test('чистый многострочный «+ п1 / + п2»', () async {
      final e = _ev(client, {
        'msgtype': 'm.text',
        'body': '+ пункт 1\n+ пункт 2',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<ul><li>пункт 1</li><li>пункт 2</li></ul>',
      });
      expect(isForcedListArtifact(e.body, e.formattedText), isTrue);
    });

    // ГИПОТЕЗА ДЫРЫ: список + пояснительная строка в ОДНОМ сообщении.
    test('СМЕШАННЫЙ «+ п1 / + п2 / Это два плюса»', () async {
      final e = _ev(client, {
        'msgtype': 'm.text',
        'body': '+ пункт 1\n+ пункт 2\nЭто два плюса',
        'format': 'org.matrix.custom.html',
        'formatted_body':
            '<ul><li>пункт 1</li><li>пункт 2</li></ul>\n<p>Это два плюса</p>',
      });
      // если false — вот она дыра (последняя строка не маркер)
      expect(isForcedListArtifact(e.body, e.formattedText), isTrue,
          reason: 'смешанный список+текст должен подавляться');
    });

    testWidgets('чистый список рисуется БЕЗ «•»', (t) async {
      final e = _ev(client, {
        'msgtype': 'm.text',
        'body': '+ пункт 1\n+ пункт 2',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<ul><li>пункт 1</li><li>пункт 2</li></ul>',
      });
      await _pump(t, bubble(e));
      expect(find.textContaining('•'), findsNothing);
      expect(find.textContaining('пункт 1'), findsOneWidget);
    });

    testWidgets('СМЕШАННЫЙ рисуется БЕЗ «•»', (t) async {
      final e = _ev(client, {
        'msgtype': 'm.text',
        'body': '+ пункт 1\n+ пункт 2\nЭто два плюса',
        'format': 'org.matrix.custom.html',
        'formatted_body':
            '<ul><li>пункт 1</li><li>пункт 2</li></ul>\n<p>Это два плюса</p>',
      });
      await _pump(t, bubble(e));
      expect(find.textContaining('•'), findsNothing);
      expect(find.textContaining('Это два плюса'), findsOneWidget);
    });
  });

  group('ЦИТАТА ОТВЕТА (ReplyContent)', () {
    testWidgets('цитата «+ это плюс» → литерал, без «•»', (t) async {
      final quoted = _ev(client, {
        'msgtype': 'm.text',
        'body': '+ это плюс',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<ul><li>это плюс</li></ul>',
      });
      await _pump(t, ReplyContent(quoted));
      expect(find.textContaining('•'), findsNothing);
    });

    testWidgets('цитата одиночного «+» → «+», без «•»', (t) async {
      final quoted = _ev(client, {
        'msgtype': 'm.text',
        'body': '+',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<ul>\n<li></li>\n</ul>\n',
      });
      await _pump(t, ReplyContent(quoted));
      expect(find.textContaining('•'), findsNothing);
    });
  });
}
