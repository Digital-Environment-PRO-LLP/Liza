// Стражи фичи «правка сообщения сохраняет форматирование» (снятие INV-11,
// брейншторм 2026-09-04). Реестр: RL-edit-preserves-formatting.
//
// ledger:RL-edit-preserves-formatting
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/edit_prefill.dart';
import 'package:liza/utils/formatting_text_controller.dart';

/// Компактная сверка спанов: `(start, end, format)`.
List<(int, int, MessageFormat)> _t(List<FormatSpan> spans) =>
    (spans.map((s) => (s.start, s.end, s.format)).toList()
      ..sort((a, b) => a.$1 == b.$1 ? a.$3.index - b.$3.index : a.$1 - b.$1));

/// Round-trip: текст+спаны → HTML эмиттером → обратно парсером.
({String text, List<FormatSpan> spans})? _roundTrip(
  String text,
  List<FormatSpan> spans,
) {
  final html = spansToFormattedHtml(text, spans);
  if (html == null) return null;
  return formattedHtmlToSpans(html);
}

void main() {
  group('formattedHtmlToSpans — обратный парс formatted_body', () {
    // AC:RL-edit-preserves-formatting/1
    test('AC-1: <strong>X</strong> → текст «X» + bold(0,1)', () {
      final parsed = formattedHtmlToSpans('<strong>X</strong>');
      expect(parsed?.text, 'X');
      expect(_t(parsed!.spans), [(0, 1, MessageFormat.bold)]);
    });

    // AC:RL-edit-preserves-formatting/2 — ∀ инлайн-6 (зеркало эмиттера).
    test('AC-2: ∀ 6 форматов — round-trip тождественен', () {
      for (final format in MessageFormat.values) {
        final parsed = _roundTrip('раз два три', [FormatSpan(4, 7, format)]);
        expect(parsed?.text, 'раз два три', reason: '$format: текст');
        expect(_t(parsed!.spans), [(4, 7, format)], reason: '$format: спан');
      }
    });

    // AC:RL-edit-preserves-formatting/3 — синонимы чужих клиентов.
    test('AC-3: ∀ синонимы b/i/s/strike/ins нормализуются', () {
      const cases = {
        '<b>X</b>': MessageFormat.bold,
        '<i>X</i>': MessageFormat.italic,
        '<ins>X</ins>': MessageFormat.underline,
        '<s>X</s>': MessageFormat.strikethrough,
        '<strike>X</strike>': MessageFormat.strikethrough,
      };
      for (final entry in cases.entries) {
        final parsed = formattedHtmlToSpans(entry.key);
        expect(parsed?.text, 'X', reason: entry.key);
        expect(
          _t(parsed!.spans),
          [(0, 1, entry.value)],
          reason: entry.key,
        );
      }
    });

    // AC:RL-edit-preserves-formatting/4 — ЦЕНТРАЛЬНЫЙ, квантор ∀ по мультистроке.
    // Red-proof: парсер, идущий по `element.text`, `<br>` не видит — текст
    // склеивается, длины расходятся, КАЖДЫЙ спан правее переноса съезжает.
    test('AC-4: ∀ мультистрочные кейсы — <br> ↔ \\n и оффсеты сходятся', () {
      // Список, а НЕ карта: кейсы «спан в первой строке» и «спан через перенос»
      // делят один и тот же текст, и в карте второй затёр бы первый.
      final cases = <(String, List<FormatSpan>)>[
        // две строки, спан в первой
        ('раз\nдва', [FormatSpan(0, 3, MessageFormat.bold)]),
        // три строки, спан во ВТОРОЙ (проверяет сдвиг после переноса)
        ('раз\nдва\nтри', [FormatSpan(4, 7, MessageFormat.italic)]),
        // пустая строка посередине
        ('раз\n\nтри', [FormatSpan(5, 8, MessageFormat.bold)]),
        // спан ЧЕРЕЗ перенос
        ('раз\nдва', [FormatSpan(0, 7, MessageFormat.underline)]),
        // спан в самом конце последней строки
        ('а\nб\nвгд', [FormatSpan(4, 7, MessageFormat.monospace)]),
      ];
      for (final (text, spans) in cases) {
        final parsed = _roundTrip(text, spans);
        expect(parsed?.text, text, reason: 'текст: $text');
        expect(_t(parsed!.spans), _t(spans), reason: 'спаны: $text');
      }
    });

    test('AC-4: <br/> и <br /> тоже дают ровно один перенос', () {
      expect(formattedHtmlToSpans('раз<br/>два')?.text, 'раз\nдва');
      expect(formattedHtmlToSpans('раз<br />два')?.text, 'раз\nдва');
    });

    // AC:RL-edit-preserves-formatting/5
    test('AC-5: HTML-энтити декодируются, оффсеты по декодированному тексту', () {
      final parsed = _roundTrip('a & b < c > d', [
        FormatSpan(0, 5, MessageFormat.bold),
      ]);
      expect(parsed?.text, 'a & b < c > d');
      expect(_t(parsed!.spans), [(0, 5, MessageFormat.bold)]);
    });

    test('AC-5: спан считается по декодированному, а не по сырому HTML', () {
      // `a<b` → `a&lt;b` (6 code units в HTML, 3 в тексте).
      final parsed = formattedHtmlToSpans('<strong>a&lt;b</strong>');
      expect(parsed?.text, 'a<b');
      expect(_t(parsed!.spans), [(0, 3, MessageFormat.bold)]);
    });

    test('emoji/суррогатные пары: оффсеты в code units', () {
      const text = '👍 привет мир';
      final spans = [FormatSpan(text.indexOf('мир'), text.length,
          MessageFormat.bold)];
      final parsed = _roundTrip(text, spans);
      expect(parsed?.text, text);
      expect(_t(parsed!.spans), _t(spans));
    });

    test('вложенные и смежные спаны переживают round-trip', () {
      // Вложенные bold ⊃ italic.
      final nested = _roundTrip('раз два', [
        FormatSpan(0, 7, MessageFormat.bold),
        FormatSpan(4, 7, MessageFormat.italic),
      ]);
      expect(nested?.text, 'раз два');
      expect(_t(nested!.spans), [
        (0, 7, MessageFormat.bold),
        (4, 7, MessageFormat.italic),
      ]);
      // Смежные одного формата канонизируются в один спан — иначе round-trip
      // выше не был бы тождественным (эмиттер режет bold по границе italic).
      final adjacent = formattedHtmlToSpans('<strong>аб</strong><strong>вг</strong>');
      expect(adjacent?.text, 'абвг');
      expect(_t(adjacent!.spans), [(0, 4, MessageFormat.bold)]);
    });

    // AC:RL-edit-preserves-formatting/6 — ∀ неподдержанные конструкции → отказ.
    test('AC-6: ∀ тег вне инлайн-6 → парс отменён (null), а не частичный', () {
      const refused = [
        '<a href="https://x">ссылка</a>',
        '<blockquote>цитата</blockquote>',
        '<ul><li>раз</li><li>два</li></ul>',
        '<ol><li>раз</li></ol>',
        '<pre><code>код</code></pre>',
        '<h1>заголовок</h1>',
        '<p>абзац</p>',
        '<img src="mxc://x"/>',
        '<span data-mx-color="#f00">цвет</span>',
        '<strong>жир</strong> и <a href="https://x">ссылка</a>',
      ];
      for (final html in refused) {
        expect(formattedHtmlToSpans(html), isNull, reason: html);
      }
    });

    test('глубокая вложенность отсекается, а не кладёт стек', () {
      final deep = '${'<strong>' * 200}x${'</strong>' * 200}';
      expect(formattedHtmlToSpans(deep), isNull);
    });

    // AC:RL-edit-preserves-formatting/7
    test('AC-7: <mx-reply> срезан, оффсеты без сдвига на длину цитаты', () {
      const html =
          '<mx-reply><blockquote><a href="https://matrix.to/#/!r/\$e">In reply'
          ' to</a> оригинал</blockquote></mx-reply><strong>ответ</strong>';
      final parsed = formattedHtmlToSpans(html);
      expect(parsed?.text, 'ответ');
      expect(_t(parsed!.spans), [(0, 5, MessageFormat.bold)]);
    });
  });

  group('resolveEditPrefill — решение «что показать в композере»', () {
    // AC:RL-edit-preserves-formatting/1
    test('AC-1: совпадение текста → спаны восстановлены', () {
      final prefill = resolveEditPrefill(
        plainFallback: 'раз два',
        format: 'org.matrix.custom.html',
        formattedBody: 'раз <strong>два</strong>',
      );
      expect(prefill.text, 'раз два');
      expect(_t(prefill.spans), [(4, 7, MessageFormat.bold)]);
    });

    // AC:RL-edit-preserves-formatting/6 — guard fail-closed.
    test('AC-6: расхождение текста → НОЛЬ спанов и сегодняшний текст', () {
      // Упоминание: body хранит пилюлю, formatted_body — сырой @токен.
      final mention = resolveEditPrefill(
        plainFallback: 'привет @[Дмитрий Луба], это важно',
        format: 'org.matrix.custom.html',
        formattedBody: 'привет @Дмитрий, это <strong>важно</strong>',
      );
      expect(mention.text, 'привет @[Дмитрий Луба], это важно');
      expect(mention.spans, isEmpty);

      // Чужой markdown-клиент: body с литеральными звёздочками.
      final foreign = resolveEditPrefill(
        plainFallback: '**жир**',
        format: 'org.matrix.custom.html',
        formattedBody: '<strong>жир</strong>',
      );
      expect(foreign.text, '**жир**');
      expect(foreign.spans, isEmpty);

      // Форс-списочный артефакт «+».
      final forcedList = resolveEditPrefill(
        plainFallback: '+',
        format: 'org.matrix.custom.html',
        formattedBody: '<ul><li></li></ul>',
      );
      expect(forcedList.text, '+');
      expect(forcedList.spans, isEmpty);
    });

    // AC:RL-edit-preserves-formatting/8
    test('AC-8: медиа-подпись → спаны не восстанавливаются никогда', () {
      final prefill = resolveEditPrefill(
        plainFallback: 'подпись',
        format: 'org.matrix.custom.html',
        formattedBody: '<strong>подпись</strong>',
        isMedia: true,
      );
      expect(prefill.text, 'подпись');
      expect(prefill.spans, isEmpty);
    });

    // AC:RL-edit-preserves-formatting/9 — правка неформатированного ничего не
    // «оживляет» (зеркало AC-3 эмиттера: typed-символы остаются буквальными).
    test('AC-9: ∀ typed-кейсы без formatted_body → спанов ноль', () {
      const typed = [
        '2*3',
        'some_file_name',
        '**нежирный**',
        '~x~',
        '- пункт',
        '> цитата',
        r'C:\path',
      ];
      for (final text in typed) {
        final prefill = resolveEditPrefill(plainFallback: text);
        expect(prefill.text, text, reason: text);
        expect(prefill.spans, isEmpty, reason: text);
      }
    });

    test('нет format/formatted_body или битый HTML → сегодняшнее поведение', () {
      for (final prefill in [
        resolveEditPrefill(plainFallback: 'X', formattedBody: '<strong>X</strong>'),
        resolveEditPrefill(
          plainFallback: 'X',
          format: 'org.matrix.custom.html',
          formattedBody: '',
        ),
        resolveEditPrefill(
          plainFallback: '<<<>>>',
          format: 'org.matrix.custom.html',
          formattedBody: '<<<>>>',
        ),
      ]) {
        expect(prefill.text, isNotNull);
        expect(prefill.spans, isEmpty);
      }
    });
  });

  group('FormattingTextEditingController.setSpans', () {
    // AC:RL-edit-preserves-formatting/10 — черновик не наследуется правкой.
    // Red-proof: на коде до фикса (`sendController.text = …` без setSpans) спаны
    // черновика диффовались на текст правки и выживали.
    test('AC-10: вход в правку сбрасывает спаны черновика', () {
      final controller = FormattingTextEditingController();
      controller.text = 'привет всем';
      controller.selection = const TextSelection(baseOffset: 0, extentOffset: 6);
      controller.toggleFormat(MessageFormat.bold);
      expect(controller.hasFormatting, isTrue);

      // Префил правки: текст, затем ПУСТЫЕ спаны (отказная ветка guard).
      const editText = 'привет мир';
      controller.text = editText;
      controller.setSpans(const [], editText.length);

      expect(controller.text, editText);
      expect(controller.hasFormatting, isFalse);
      expect(spansToFormattedHtml(controller.text, controller.spans), isNull);
      controller.dispose();
    });

    test('AC-10: отложенный черновик возвращается СО СВОИМ форматом', () {
      final controller = FormattingTextEditingController();
      const draft = 'привет всем';
      final draftSpans = [FormatSpan(0, 6, MessageFormat.bold)];

      controller.text = 'правка';
      controller.setSpans(const [], 'правка'.length);
      // Отмена правки: возврат текста и парных спанов.
      controller.text = draft;
      controller.setSpans(draftSpans, draft.length);

      expect(controller.text, draft);
      expect(_t(controller.spans), [(0, 6, MessageFormat.bold)]);
      controller.dispose();
    });

    test('спаны клампятся по длине текста (защита от рассинхрона)', () {
      final controller = FormattingTextEditingController();
      controller.text = 'abc';
      controller.setSpans([FormatSpan(1, 99, MessageFormat.italic)], 3);
      expect(_t(controller.spans), [(1, 3, MessageFormat.italic)]);
      controller.dispose();
    });
  });
}
