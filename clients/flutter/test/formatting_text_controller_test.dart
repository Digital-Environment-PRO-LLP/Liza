// Стражи фичи «явное форматирование как в Liza» (кандидат A брейншторма
// 2026-08-28). Реестр: RL-explicit-formatting-emit.
//
// ledger:RL-explicit-formatting-emit
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/forced_list_artifact.dart';
import 'package:liza/utils/formatting_text_controller.dart';

void main() {
  group('spansToFormattedHtml — эмиттер formatted_body', () {
    // AC:RL-explicit-formatting-emit/1 — выделение + Bold → сырой body + <strong>.
    test('AC-1: Bold над «X» → <strong>X</strong>', () {
      final html = spansToFormattedHtml('X', [
        FormatSpan(0, 1, MessageFormat.bold),
      ]);
      expect(html, '<strong>X</strong>');
    });

    // AC:RL-explicit-formatting-emit/2 — каждый тип → правильный тег.
    test('AC-2: каждый формат → свой тег (все 6 типов)', () {
      const text = 'слово';
      final cases = <MessageFormat, String>{
        MessageFormat.bold: '<strong>слово</strong>',
        MessageFormat.italic: '<em>слово</em>',
        MessageFormat.underline: '<u>слово</u>',
        MessageFormat.strikethrough: '<del>слово</del>',
        MessageFormat.monospace: '<code>слово</code>',
        MessageFormat.spoiler: '<span data-mx-spoiler>слово</span>',
      };
      cases.forEach((format, expected) {
        expect(
          spansToFormattedHtml(text, [FormatSpan(0, text.length, format)]),
          expected,
          reason: 'формат $format',
        );
      });
    });

    // AC:RL-explicit-formatting-emit/3 — ЦЕНТРАЛЬНЫЙ СТРАЖ (квантор ∀).
    // Набранные ВРУЧНУЮ символы БЕЗ явного форматирования → formatted_body НЕ
    // создаётся (null). Red-proof: если эмиттер начнёт парсить markdown из
    // текста, любой из этих кейсов вернёт не-null.
    test('AC-3: typed-literal ∀ — без спанов formatted_body == null', () {
      const typed = [
        '2*3',
        'some_file_name',
        'payment_report_final',
        'a_b_c',
        '**нежирный**',
        '~x~',
        'a*b*c',
        'C:\\path\\to',
        '# заголовок',
        '> цитата',
        '- пункт',
        '+ пункт',
      ];
      for (final t in typed) {
        expect(
          spansToFormattedHtml(t, const []),
          isNull,
          reason: 'набранное вручную «$t» не должно форматироваться',
        );
      }
    });

    // AC:RL-explicit-formatting-emit/4 — смешанное: форматируется ТОЛЬКО
    // выделенный диапазон; typed `_` в остальном тексте буквальны.
    test('AC-4: формат только на выделении, typed символы вне — буквальны', () {
      // «bold_word plain_text», Bold на первых 9 символах («bold_word»).
      const text = 'bold_word plain_text';
      final html = spansToFormattedHtml(text, [
        FormatSpan(0, 9, MessageFormat.bold),
      ]);
      expect(html, '<strong>bold_word</strong> plain_text');
      // Подчёркивания НИГДЕ не стали курсивом/эмфазисом.
      expect(html, isNot(contains('<em>')));
      expect(html, contains('plain_text'));
    });

    // AC:RL-explicit-formatting-emit/10 — многострочное → <br> (federation).
    test('AC-10: перенос строки в formatted_body становится <br>', () {
      final html = spansToFormattedHtml('строка1\nстрока2', [
        FormatSpan(0, 7, MessageFormat.bold),
      ]);
      expect(html, '<strong>строка1</strong><br>строка2');
      // Многострочный жирный: <br> внутри форматированного диапазона тоже.
      final html2 = spansToFormattedHtml('a\nb', [
        FormatSpan(0, 3, MessageFormat.bold),
      ]);
      expect(html2, '<strong>a<br>b</strong>');
    });

    test('AC-3 (доп): HTML-спецсимволы экранируются, а не форматируются', () {
      // «a<b>c» без спанов → null (не формат), но проверяем экранирование, когда
      // формат ЕСТЬ на части.
      final html = spansToFormattedHtml('a<b & c', [
        FormatSpan(0, 1, MessageFormat.bold),
      ]);
      expect(html, '<strong>a</strong>&lt;b &amp; c');
    });

    test('вложенные форматы → детерминированный порядок тегов', () {
      final html = spansToFormattedHtml('ab', [
        FormatSpan(0, 2, MessageFormat.bold),
        FormatSpan(0, 2, MessageFormat.italic),
      ]);
      // Канонический порядок: italic внутри bold.
      expect(html, '<strong><em>ab</em></strong>');
    });
  });

  group('FormattingTextEditingController — тоггл и сдвиг оффсетов', () {
    FormattingTextEditingController makeController(String text) {
      final c = FormattingTextEditingController(text: text);
      c.selection = TextSelection(baseOffset: 0, extentOffset: text.length);
      return c;
    }

    test('toggleFormat добавляет и снимает формат на выделении', () {
      final c = makeController('hello');
      c.toggleFormat(MessageFormat.bold);
      expect(c.hasFormatting, isTrue);
      expect(c.isFormatActiveForSelection(MessageFormat.bold), isTrue);
      c.toggleFormat(MessageFormat.bold);
      expect(c.hasFormatting, isFalse);
    });

    test('collapsed-выделение не создаёт формат', () {
      final c = FormattingTextEditingController(text: 'hello');
      c.selection = const TextSelection.collapsed(offset: 2);
      c.toggleFormat(MessageFormat.bold);
      expect(c.hasFormatting, isFalse);
    });

    // AC:RL-explicit-formatting-emit/5 (span-offset, INV-5) — вставка в начало.
    test('INV-5: вставка текста в начало сдвигает спан', () {
      final c = makeController('hello');
      c.toggleFormat(MessageFormat.bold);
      c.value = const TextEditingValue(
        text: 'XXhello',
        selection: TextSelection.collapsed(offset: 7),
      );
      final html = spansToFormattedHtml(c.text, c.spans);
      expect(html, 'XX<strong>hello</strong>');
    });

    test('INV-5: удаление символа перед спаном сдвигает спан', () {
      final c = makeController('hello');
      c.toggleFormat(MessageFormat.bold); // bold [0,5]
      // Сдвинем спан вправо через вставку, затем удалим первый символ.
      c.value = const TextEditingValue(text: 'Zhello');
      // спан теперь [1,6]; удалим 'Z'.
      c.value = const TextEditingValue(text: 'hello');
      final html = spansToFormattedHtml(c.text, c.spans);
      expect(html, '<strong>hello</strong>');
    });

    test('INV-5: emoji-суррогат (4 code unit) в начале сдвигает на 4', () {
      final c = makeController('hi');
      c.toggleFormat(MessageFormat.bold); // bold [0,2]
      const flag = '🏳️‍🌈'; // 7 code units
      c.value = TextEditingValue(text: '$flag' 'hi');
      final html = spansToFormattedHtml(c.text, c.spans);
      expect(html, '${_esc(flag)}<strong>hi</strong>');
    });

    test('очистка текста снимает спаны', () {
      final c = makeController('hello');
      c.toggleFormat(MessageFormat.bold);
      c.value = const TextEditingValue(text: '');
      expect(c.hasFormatting, isFalse);
    });

    // AC:RL-explicit-formatting-emit/9 — форматированный черновик переживает
    // выход/возврат в чат (serializeSpans → restoreSpans).
    test('AC-9: сериализация/восстановление спанов черновика', () {
      final c = makeController('hello world');
      c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
      c.toggleFormat(MessageFormat.bold);
      final serialized = c.serializeSpans();
      expect(serialized, isNotNull);

      final restored = FormattingTextEditingController(text: 'hello world');
      restored.restoreSpans(serialized, 'hello world'.length);
      expect(
        spansToFormattedHtml(restored.text, restored.spans),
        '<strong>hello</strong> world',
      );
    });
  });

  group('Совместимость с forced-list-artifact (дополнение RL)', () {
    // Наш инлайн formatted_body (без <ul>/<li>) НЕ должен глушиться.
    test('INV-1: <strong> без списочных тегов не считается forced-list', () {
      final html = spansToFormattedHtml('важно', [
        FormatSpan(0, 5, MessageFormat.bold),
      ]);
      expect(isForcedListArtifact('важно', html), isFalse);
    });
  });
}

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
