// ledger:RL-message-trim-whitespace
// LABA-2623: пробелы по краям исходящего сообщения и причины удаления не
// обрезались — причина «воавоо⏎⏎⏎…» растягивала пузырь удалённого сообщения на
// весь экран. Страж: чистые функции отправки (trimOutgoing,
// normalizeRedactionReason) + РЕАЛЬНЫЙ RedactionWidget на уже записанной причине.
//
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/message_content.dart';
import 'package:liza/utils/edit_prefill.dart';
import 'package:liza/utils/formatting_text_controller.dart';

import 'test_client.dart';

List<(int, int, MessageFormat)> _tuples(List<FormatSpan> spans) =>
    [for (final s in spans) (s.start, s.end, s.format)];

void main() {
  group('trimOutgoing', () {
    test('AC:RL-message-trim-whitespace/1 края обрезаются, середина цела', () {
      for (final raw in [
        '  ab ',
        '\n\nab\n\n\n',
        '\tab\t',
        ' ab ',
        ' \n\t ab \n ',
      ]) {
        expect(trimOutgoing(raw, const []).text, 'ab', reason: raw);
      }
      expect(
        trimOutgoing('  строка 1\n\n  строка 2  \n', const []).text,
        'строка 1\n\n  строка 2',
      );
      expect(trimOutgoing('x', const []).text, 'x');
      expect(trimOutgoing('😀 ', const []).text, '😀');
    });

    test('AC:RL-message-trim-whitespace/2 спаны сдвигаются и зажимаются', () {
      // bold на слове после ведущих пробелов.
      var r = trimOutgoing('  hello world', [
        FormatSpan(2, 7, MessageFormat.bold),
      ]);
      expect(r.text, 'hello world');
      expect(_tuples(r.spans), [(0, 5, MessageFormat.bold)]);

      // bold на всю строку вместе с пробелами по краям.
      r = trimOutgoing('  hi  ', [FormatSpan(0, 6, MessageFormat.bold)]);
      expect(_tuples(r.spans), [(0, 2, MessageFormat.bold)]);

      // эмодзи (суррогатная пара) под спаном.
      r = trimOutgoing(' 😀a ', [FormatSpan(1, 3, MessageFormat.italic)]);
      expect(r.text, '😀a');
      expect(_tuples(r.spans), [(0, 2, MessageFormat.italic)]);

      // спан целиком в пробелах выкидывается.
      r = trimOutgoing('  ab  ', [
        FormatSpan(0, 2, MessageFormat.bold),
        FormatSpan(4, 6, MessageFormat.italic),
      ]);
      expect(r.spans, isEmpty);
    });

    test('AC:RL-message-trim-whitespace/3 пробельный текст — пустой', () {
      for (final raw in ['   ', '\n\n\n', ' \t\n  ']) {
        expect(trimOutgoing(raw, const []).text, isEmpty);
      }
    });

    test('AC:RL-message-trim-whitespace/4 body и formatted_body согласованы', () {
      final r = trimOutgoing('\n  жирный и обычный  \n', [
        FormatSpan(3, 9, MessageFormat.bold),
      ]);
      final html = spansToFormattedHtml(r.text, r.spans);
      expect(html, '<strong>жирный</strong> и обычный');
      final prefill = resolveEditPrefill(
        plainFallback: r.text,
        format: 'org.matrix.custom.html',
        formattedBody: html,
      );
      expect(_tuples(prefill.spans), _tuples(r.spans));
    });

    test('исходные спаны контроллера не мутируются', () {
      final spans = [FormatSpan(2, 5, MessageFormat.bold)];
      trimOutgoing('  abc', spans);
      expect(_tuples(spans), [(2, 5, MessageFormat.bold)]);
    });
  });

  group('normalizeRedactionReason', () {
    test('AC:RL-message-trim-whitespace/8 пробельная причина — причины нет', () {
      expect(normalizeRedactionReason(null), isNull);
      expect(normalizeRedactionReason(''), isNull);
      expect(normalizeRedactionReason('  \n '), isNull);
      expect(normalizeRedactionReason('воавоо\n\n\n\n'), 'воавоо');
      expect(normalizeRedactionReason('  спам\n\nи  флуд '), 'спам и флуд');
    });
  });

  group('RedactionWidget', () {
    late Client client;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
    });

    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await client.dispose(closeDatabase: true);
    });

    Event redacted(Room room, String? reason) => Event(
      type: EventTypes.Message,
      eventId: '\$msg:example.invalid',
      senderId: '@author:example.invalid',
      originServerTs: DateTime(2026, 9, 21),
      content: const {},
      room: room,
      unsigned: {
        'redacted_because': {
          'type': EventTypes.Redaction,
          'event_id': '\$red:example.invalid',
          'sender': '@author:example.invalid',
          'origin_server_ts': 0,
          'redacts': '\$msg:example.invalid',
          'content': {if (reason != null) 'reason': reason},
        },
      },
    );

    Future<Text> pump(WidgetTester tester, String? reason) async {
      final room = Room(id: '!room:example.invalid', client: client);
      // RU-делегат L10n грузится асинхронно — прокачка на реальном времени.
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ru'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 300,
                child: RedactionWidget(
                  event: redacted(room, reason),
                  buttonTextColor: Colors.black,
                  onInfoTab: (_) {},
                  fontSize: 14,
                ),
              ),
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      });
      return tester.widget<Text>(
        find.descendant(
          of: find.byType(RedactionWidget),
          matching: find.byType(Text),
        ),
      );
    }

    testWidgets(
      'AC:RL-message-trim-whitespace/9 причина с переносами — одна строка, ≤2 строк',
      (tester) async {
        final withTail = await pump(tester, 'воавоо\n\n\n\n\n\n\n\n');
        expect(withTail.data, endsWith('Причина: "воавоо"'));
        expect(withTail.maxLines, 2);
        expect(withTail.overflow, TextOverflow.ellipsis);

        final blank = await pump(tester, ' \n\n ');
        expect(blank.data, isNot(contains('Причина')));
        expect(blank.data, contains('удалил сообщение'));

        final none = await pump(tester, null);
        expect(none.data, isNot(contains('Причина')));
      },
    );
  });
}
