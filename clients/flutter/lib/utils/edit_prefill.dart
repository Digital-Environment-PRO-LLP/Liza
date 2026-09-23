import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;

import 'package:liza/utils/forced_list_artifact.dart';
import 'package:liza/utils/formatting_text_controller.dart';

/// Что положить в композер при входе в режим правки: текст и явное
/// форматирование (спаны), восстановленное из `formatted_body`.
///
/// Зеркало эмиттера [spansToFormattedHtml]. Снимает known-limit INV-11 спеки
/// `docs/superpowers/specs/2026-08-28-message-formatting-explicit-spans-design.md`
/// («v1 не включает обратный парс HTML→spans при редактировании»); дизайн —
/// `docs/superpowers/specs/2026-09-04-edit-preserves-formatting-design.md`.
class EditPrefill {
  final String text;
  final List<FormatSpan> spans;

  const EditPrefill(this.text, this.spans);
}

/// Решение «что показать в композере» для правки события.
///
/// INV-E2 (fail-closed): спаны принимаются, ТОЛЬКО если разобранный из
/// `formatted_body` текст посимвольно равен [plainFallback]. При любом
/// расхождении отбрасываются ОБА — и текст, и спаны, — и поведение остаётся
/// сегодняшним (плоский текст). Частичное восстановление запрещено: тихо
/// потерять при сохранении ссылку/список чужого клиента хуже, чем потерять
/// форматирование.
///
/// Расхождение — не редкость, а штатная ветка: у сообщения с упоминанием `body`
/// хранит пилюлю `@[Полное имя]` (`resolvedText`), а `formatted_body` строится
/// из СЫРОГО текста (`@Имя`). Такие сообщения формат при правке теряют, как и
/// раньше (INV-E10: пилюля обязана дожить до `buildMentions`, иначе счётчик
/// упоминания станет синим).
EditPrefill resolveEditPrefill({
  required String plainFallback,
  String? format,
  String? formattedBody,
  bool isMedia = false,
}) {
  // INV-E6: на медиа-ветке `send()` безусловно сносит formatted_body/format —
  // показать формат в поле значило бы соврать пользователю.
  if (isMedia) return EditPrefill(plainFallback, const []);
  if (format != 'org.matrix.custom.html') {
    return EditPrefill(plainFallback, const []);
  }
  if (formattedBody == null || formattedBody.isEmpty) {
    return EditPrefill(plainFallback, const []);
  }
  final parsed = formattedHtmlToSpans(formattedBody);
  if (parsed == null || parsed.text != plainFallback) {
    return EditPrefill(plainFallback, const []);
  }
  return EditPrefill(plainFallback, parsed.spans);
}

/// Разобрать Matrix custom-HTML в пару «сырой текст + спаны» за ОДИН обход DOM
/// (INV-E1: второго источника координат нет — иначе оффсеты разъезжаются).
///
/// Возвращает `null`, если встретился тег вне набора, который умеет эмитить
/// [spansToFormattedHtml] (INV-E11: whitelist парсера ⊆ whitelist эмиттера).
/// Синонимы других клиентов (`b`, `i`, `s`, `strike`, `ins`) нормализуются к
/// нашим форматам здесь же — при пересохранении уйдёт канонический тег.
///
/// Оффсеты — в code units (как `TextSelection` и весь [FormatSpan]);
/// `characters`/`runes` сломали бы спаны на суррогатных парах.
({String text, List<FormatSpan> spans})? formattedHtmlToSpans(String html) {
  final stripped = stripReplyFallbackFormatted(html) ?? '';
  final buffer = StringBuffer();
  final spans = <FormatSpan>[];
  final ok = _collect(
    parser.parseFragment(stripped).nodes,
    buffer,
    spans,
    0,
  );
  if (!ok) return null;
  // Канонизация обязательна: эмиттер режет спан по границам ВЛОЖЕННОГО формата,
  // поэтому `bold(0,7)` ⊃ `italic(4,7)` приходит двумя смежными `<strong>`.
  return (text: buffer.toString(), spans: mergeFormatSpans(spans));
}

/// Глубина вложенности, дальше которой чужой HTML не разбираем (образец —
/// `html_message.dart`: 100-уровневая вложенность иначе кладёт обход стеком).
const int _maxDepth = 100;

bool _collect(
  List<dom.Node> nodes,
  StringBuffer buffer,
  List<FormatSpan> spans,
  int depth,
) {
  if (depth >= _maxDepth) return false;
  for (final node in nodes) {
    if (node is dom.Text) {
      // Сущности (`&amp;`/`&lt;`/`&gt;`) пакет `html` разворачивает сам —
      // симметрично `_escapeHtml` эмиттера (INV-E4).
      buffer.write(node.data);
      continue;
    }
    if (node is! dom.Element) {
      // Комментарии и прочие не-контентные узлы текста не дают — пропускаем.
      continue;
    }
    // INV-E3: `<br>` — единственный способ эмиттера записать перенос строки.
    // У него нет текстового узла, поэтому обход по `.text` съел бы ВСЕ переносы
    // (и сдвинул бы каждый спан правее переноса).
    if (node.localName == 'br') {
      buffer.write('\n');
      continue;
    }
    final format = _formatOf(node);
    if (format == null) return false;
    final start = buffer.length;
    if (!_collect(node.nodes, buffer, spans, depth + 1)) return false;
    spans.add(FormatSpan(start, buffer.length, format));
  }
  return true;
}

MessageFormat? _formatOf(dom.Element node) => switch (node.localName) {
  'strong' || 'b' => MessageFormat.bold,
  'em' || 'i' => MessageFormat.italic,
  'u' || 'ins' => MessageFormat.underline,
  'del' || 's' || 'strike' => MessageFormat.strikethrough,
  'code' => MessageFormat.monospace,
  // Только спойлер: `<span>` с цветом/фоном от чужого клиента выразить спаном
  // нельзя — отказываемся от разбора целиком, а не теряем оформление молча.
  'span' when node.attributes.containsKey('data-mx-spoiler') =>
    MessageFormat.spoiler,
  _ => null,
};
