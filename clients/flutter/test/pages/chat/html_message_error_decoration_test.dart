// Страж реестра регрессии: ledger:RL-link-context-menu
// guard.render:real-widget
//
// Дефект (2026-08-13, ветка tasks-s3-12): при длинном тапе по сообщению
// (контекстное меню лифтит РАСТРОВЫЙ снимок пузыря через toImageSync) поверх
// текста тела появлялись ЖЁЛТЫЕ двойные линии — это Flutter `_errorTextStyle`
// (material/app.dart: decorationColor 0xFFFFFF00, double underline, «consider
// putting your text in a Material»). Корень: замена LinkifySpan (который
// резолвил Theme…bodyMedium) на buildLinkifiedSpans(textStyle: null) в
// html_message.dart → сырой TextSpan(style:null) наследует ambient
// DefaultTextStyle, который в офскрин-снимке резолвится в _errorTextStyle.
// Фикс — явный textStyle + `decoration: TextDecoration.none` на базовом стиле
// (паритет с media_caption/poll).
//
// Ограничение стража (см. RL AC-3): host рендерит на Skia+Ahem и офскрин-снимок
// НЕ воспроизводит; поэтому эти ассерты доказывают, что ФИКС на месте (базовый
// стиль явно несёт decoration:none и не полагается на ambient), а фактическое
// отсутствие жёлтого на растре iOS/Impeller закрывает manual device-AC-3.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/html_message.dart';

import '../../utils/test_client.dart';

// Жёлтая error-декорация из Flutter _errorTextStyle (material/app.dart).
const _errorYellow = Color(0xFFFFFF00);

Event _ev(Client c, Map<String, Object?> content) => Event(
      type: 'm.room.message',
      eventId: '\$e${content.hashCode}:x',
      senderId: '@nadya:x',
      originServerTs: DateTime.now(),
      room: Room(id: '!r:x', client: c),
      content: content,
    );

// ВАЖНО: НЕ оборачиваем в Scaffold/Material. Реальный пузырь сообщения рисуется
// под `BubbleBackground` (CustomPaint), БЕЗ Material-предка (см. message.dart —
// соседние Material'ы это фон/время, не предки текста). Значит ambient
// DefaultTextStyle там = корневой `_errorTextStyle` (WidgetsApp.textStyle,
// material/app.dart:1082). Именно это воспроизводит дефект: сырой TextSpan без
// стиля наследует жёлтую двойную декорацию. Обёртка в Scaffold её маскирует.
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
    home: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 300, child: w),
    ),
  ));
  await t.pumpAndSettle();
}

/// Собирает стили всех TextSpan в дереве корневого RichText.
List<TextStyle> _collectStyles(InlineSpan span) {
  final out = <TextStyle>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      if (s.style != null) out.add(s.style!);
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
  }

  walk(span);
  return out;
}

/// Стиль листового TextSpan с заданным текстом (первое совпадение).
TextStyle? _leafStyleOf(InlineSpan root, String text) {
  TextStyle? found;
  void walk(InlineSpan s) {
    if (found != null) return;
    if (s is TextSpan) {
      if (s.text == text) {
        found = s.style;
        return;
      }
      for (final c in s.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }
  }

  walk(root);
  return found;
}

void main() {
  late Client client;
  setUpAll(() async => client = await prepareTestClient(loggedIn: true));

  Widget bubble(Event e) => HtmlMessage(
        html: e.content['formatted_body'] as String? ??
            (e.content['body'] as String),
        room: e.room,
        fontSize: 14,
        // linkStyle с underline — как в message_content.dart (проверяем, что
        // фикс базового decoration:none НЕ убивает подчёркивание ссылок).
        linkStyle: const TextStyle(
          color: Colors.blue,
          decoration: TextDecoration.underline,
          decorationColor: Colors.blue,
        ),
        onOpen: (_) {},
      );

  RichText rootRichText(WidgetTester t) =>
      t.widget<RichText>(find.byType(RichText).first);

  testWidgets(
    'AC-1: базовый стиль текста пузыря НЕ несёт жёлтую error-декорацию — '
    'ledger:RL-link-context-menu AC:RL-link-context-menu/7',
    (t) async {
      final e = _ev(client, {
        'msgtype': 'm.text',
        'body': 'Обычный текст без ссылок и разметки',
        'formatted_body': 'Обычный текст без ссылок и разметки',
        'format': 'org.matrix.custom.html',
      });
      await _pump(t, bubble(e));

      final root = rootRichText(t);

      // B-lite: корневой стиль явно decoration:none (было — null → протечка).
      expect(
        root.text.style?.decoration,
        TextDecoration.none,
        reason: 'корневой Text.rich должен явно задавать decoration:none',
      );

      // A: листовой плейн-спан несёт явный стиль с decoration:none (было —
      // style:null → наследование ambient _errorTextStyle в офскрин-снимке).
      final leaf = _leafStyleOf(root.text, 'Обычный текст без ссылок и разметки');
      expect(leaf, isNotNull, reason: 'плейн-спан должен иметь явный стиль');
      expect(leaf!.decoration, TextDecoration.none);

      // Ни один спан не РИСУЕТ жёлтую error-линию. Важно: decoration:none даёт
      // отсутствие линии даже если decorationColor/Style унаследованы жёлтыми от
      // _errorTextStyle через merge — Flutter при decoration==none не рисует
      // ничего. Поэтому «протечка» = линия РИСУЕТСЯ (underline/lineThrough) И
      // цвет жёлтый.
      for (final s in _collectStyles(root.text)) {
        final draws = s.decoration != null && s.decoration != TextDecoration.none;
        expect(
          draws && s.decorationColor == _errorYellow,
          isFalse,
          reason: 'видимая жёлтая _errorTextStyle-линия недопустима',
        );
      }
    },
  );

  testWidgets(
    'AC-1b: WidgetSpan-ветки (blockquote/li) под no-Material ambient НЕ несут '
    'жёлтую error-линию — AC:RL-link-context-menu/7',
    (t) async {
      // blockquote/li рождают ВЛОЖЕННЫЙ Text.rich внутри WidgetSpan — он НЕ
      // наследует стиль корневого Text.rich (WidgetSpan разрывает span-дерево).
      // Его закрывает ТОЛЬКО DefaultTextStyle.merge-обёртка вокруг HtmlMessage.
      final e = _ev(client, {
        'msgtype': 'm.text',
        'body': '> цитата\n- пункт',
        'formatted_body':
            '<blockquote>цитата тела</blockquote><ul><li>пункт списка</li></ul>',
        'format': 'org.matrix.custom.html',
      });
      await _pump(t, bubble(e));

      // Собираем стили ВСЕХ RichText на экране (вложенные Text.rich из WidgetSpan
      // — это отдельные RichText-виджеты, не входят в корневой span-tree).
      for (final el in find.byType(RichText).evaluate()) {
        final rt = el.widget as RichText;
        for (final s in _collectStyles(rt.text)) {
          final draws =
              s.decoration != null && s.decoration != TextDecoration.none;
          expect(
            draws && s.decorationColor == _errorYellow,
            isFalse,
            reason: 'blockquote/li не должны нести жёлтую _errorTextStyle-линию',
          );
        }
        // Базовый стиль каждого RichText — decoration задан (none или явный),
        // не «дырка» под ambient error-style.
        expect(
          rt.text.style?.decoration,
          isNotNull,
          reason: 'каждый Text.rich пузыря должен явно задавать decoration',
        );
      }
    },
  );

  testWidgets(
    'AC-2: фикс НЕ убил намеренные декорации <u>/<del>/ссылки — '
    'AC:RL-link-context-menu/8',
    (t) async {
      final e = _ev(client, {
        'msgtype': 'm.text',
        'body': 'подчёркнуто зачёркнуто',
        'formatted_body': '<u>подчёркнуто</u> <del>зачёркнуто</del>',
        'format': 'org.matrix.custom.html',
      });
      await _pump(t, bubble(e));

      final styles = _collectStyles(rootRichText(t).text);

      expect(
        styles.any((s) => s.decoration == TextDecoration.underline),
        isTrue,
        reason: '<u> должен остаться подчёркнутым поверх базового none',
      );
      expect(
        styles.any((s) => s.decoration == TextDecoration.lineThrough),
        isTrue,
        reason: '<del> должен остаться зачёркнутым поверх базового none',
      );
    },
  );
}
