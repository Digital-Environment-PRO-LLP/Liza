import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Типы инлайнового форматирования, которые пользователь применяет ЯВНО
/// (выделение + хоткей/пункт меню). Набор ограничен тем, что рендер уже умеет
/// показывать (`html_message.dart`) и что выразимо как инлайновый span.
///
/// v1 намеренно НЕ включает Link (модалка URL) и Quote (блочный `<blockquote>`) —
/// см. `docs/superpowers/specs/2026-08-28-message-formatting-explicit-spans-design.md`.
enum MessageFormat { bold, italic, underline, strikethrough, monospace, spoiler }

/// Один диапазон явного форматирования: `[start, end)` в code units строки
/// (те же единицы, что `TextSelection`/`TextEditingValue`).
class FormatSpan {
  int start;
  int end; // exclusive
  final MessageFormat format;

  FormatSpan(this.start, this.end, this.format)
    : assert(start >= 0),
      assert(end >= start);

  bool get isEmpty => end <= start;

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    'format': format.name,
  };

  static FormatSpan? fromJson(Map<String, dynamic> json) {
    final start = json['start'];
    final end = json['end'];
    final formatName = json['format'];
    if (start is! int || end is! int || formatName is! String) return null;
    final format = MessageFormat.values
        .where((f) => f.name == formatName)
        .firstOrNull;
    if (format == null || end <= start || start < 0) return null;
    return FormatSpan(start, end, format);
  }
}

/// `TextEditingController`, который держит БОКОВОЙ КАНАЛ явного форматирования
/// (`List<FormatSpan>`) рядом с плоской строкой. Это ядро кандидата A из
/// брейншторма: различить «применил кнопкой» и «набрал вручную `*`» в плоской
/// строке невозможно — нужен отдельный список диапазонов.
///
/// Инварианты:
/// - символы форматирования (`*`, `_`, `~`) в `text` НЕ вставляются — `text`
///   всегда сырой пользовательский (INV-3: `body` уходит сырым);
/// - при любой правке текста (ввод/удаление/paste/автоподстановка `@`/prefill)
///   оффсеты спанов сдвигаются диффом old/new (INV-5);
/// - `buildTextSpan` рисует форматирование в поле (WYSIWYG-lite).
class FormattingTextEditingController extends TextEditingController {
  FormattingTextEditingController({super.text});

  final List<FormatSpan> _spans = [];

  /// Копия спанов (для сериализации черновика/тестов). Мутировать нельзя.
  List<FormatSpan> get spans =>
      _spans.map((s) => FormatSpan(s.start, s.end, s.format)).toList();

  bool get hasFormatting => _spans.isNotEmpty;

  @override
  set value(TextEditingValue newValue) {
    _shiftSpansForTextChange(super.value.text, newValue.text);
    super.value = newValue;
  }

  @override
  void clear() {
    _spans.clear();
    super.clear();
  }

  /// Сбросить всё форматирование (после отправки — вместе с очисткой текста).
  void clearFormatting() {
    if (_spans.isEmpty) return;
    _spans.clear();
    notifyListeners();
  }

  // --- Дифф-сдвиг оффсетов (INV-5) ---------------------------------------

  void _shiftSpansForTextChange(String oldText, String newText) {
    if (identical(oldText, newText) || oldText == newText) return;

    // Общий префикс.
    final minLen = math.min(oldText.length, newText.length);
    var prefix = 0;
    while (prefix < minLen &&
        oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }
    // Общий суффикс (не перекрывая префикс).
    var suffix = 0;
    while (suffix < (minLen - prefix) &&
        oldText.codeUnitAt(oldText.length - 1 - suffix) ==
            newText.codeUnitAt(newText.length - 1 - suffix)) {
      suffix++;
    }

    final removedStart = prefix;
    final removedEnd = oldText.length - suffix; // exclusive в старом тексте
    final insertedLen = newText.length - suffix - prefix;
    final delta = insertedLen - (removedEnd - removedStart);

    if (removedStart == removedEnd && delta == 0) return;

    for (final span in _spans) {
      span.start =
          _mapOffset(span.start, removedStart, removedEnd, delta, isStart: true);
      span.end =
          _mapOffset(span.end, removedStart, removedEnd, delta, isStart: false);
    }
    _spans.removeWhere((s) => s.isEmpty);
    _mergeSpans();
  }

  /// Отображение одного оффсета при замене `[removedStart, removedEnd)` на
  /// `insertedLen` символов (`delta = insertedLen - (removedEnd-removedStart)`).
  ///
  /// Смещение start/end на границе вставки различается (stickiness): текст,
  /// вставленный РОВНО на левой границе спана, НЕ включается в формат (start
  /// уезжает вправо), а вставленный внутри/на правой границе — включается только
  /// если строго внутри. Это поведение Liza: печатать перед жирным словом →
  /// новый символ не жирный; печатать внутри → жирный.
  int _mapOffset(
    int o,
    int removedStart,
    int removedEnd,
    int delta, {
    required bool isStart,
  }) {
    if (isStart) {
      if (o < removedStart) return o;
      if (o >= removedEnd) return o + delta;
    } else {
      if (o <= removedStart) return o;
      if (o > removedEnd) return o + delta;
    }
    // Оффсет внутри заменённого куска — коллапсируем к его началу.
    return removedStart;
  }

  // --- Тоггл формата на выделении (INV-8: selection не теряем) ------------

  /// Есть ли формат [format] на всём выделении (для «снять/применить»).
  bool isFormatActiveForSelection(MessageFormat format) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return false;
    final start = sel.start;
    final end = sel.end;
    return _isRangeFullyCovered(start, end, format);
  }

  bool _isRangeFullyCovered(int start, int end, MessageFormat format) {
    if (end <= start) return false;
    // Каждая позиция [start, end) должна быть покрыта каким-то спаном формата.
    var covered = start;
    final relevant =
        _spans.where((s) => s.format == format && s.end > start && s.start < end)
            .toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    for (final s in relevant) {
      if (s.start > covered) return false; // дыра
      covered = math.max(covered, s.end);
      if (covered >= end) return true;
    }
    return covered >= end;
  }

  /// Применить/снять формат на текущем выделении. Если весь диапазон уже покрыт
  /// — снимаем; иначе добавляем. Выделение сохраняется.
  void toggleFormat(MessageFormat format) {
    final sel = selection;
    if (!sel.isValid || sel.isCollapsed) return;
    final start = sel.start;
    final end = sel.end;
    if (end <= start) return;

    if (_isRangeFullyCovered(start, end, format)) {
      _removeFormat(start, end, format);
    } else {
      _addFormat(start, end, format);
    }
    _mergeSpans();
    // Явно уведомляем (selection не трогали — курсор/выделение на месте).
    notifyListeners();
  }

  void _addFormat(int start, int end, MessageFormat format) {
    _spans.add(FormatSpan(start, end, format));
  }

  void _removeFormat(int start, int end, MessageFormat format) {
    final result = <FormatSpan>[];
    for (final s in _spans) {
      if (s.format != format || s.end <= start || s.start >= end) {
        result.add(s);
        continue;
      }
      // Левый хвост.
      if (s.start < start) result.add(FormatSpan(s.start, start, format));
      // Правый хвост.
      if (s.end > end) result.add(FormatSpan(end, s.end, format));
    }
    _spans
      ..clear()
      ..addAll(result)
      ..removeWhere((s) => s.isEmpty);
  }

  /// Слить пересекающиеся/смежные спаны одного формата — детерминированный вид.
  void _mergeSpans() {
    if (_spans.length < 2) return;
    final merged = mergeFormatSpans(_spans);
    _spans
      ..clear()
      ..addAll(merged);
  }

  // --- Отрисовка форматирования в поле (WYSIWYG-lite) ---------------------

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final baseText = text;
    if (_spans.isEmpty || baseText.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final boundaries = _segmentBoundaries(baseText.length);
    final children = <TextSpan>[];
    for (var i = 0; i < boundaries.length - 1; i++) {
      final segStart = boundaries[i];
      final segEnd = boundaries[i + 1];
      if (segEnd <= segStart) continue;
      final formats = _formatsAt(segStart);
      children.add(
        TextSpan(
          text: baseText.substring(segStart, segEnd),
          style: _styleFor(formats, style),
        ),
      );
    }
    return TextSpan(style: style, children: children);
  }

  List<int> _segmentBoundaries(int length) {
    final set = <int>{0, length};
    for (final s in _spans) {
      if (s.start >= 0 && s.start <= length) set.add(s.start);
      if (s.end >= 0 && s.end <= length) set.add(s.end);
    }
    final list = set.toList()..sort();
    return list;
  }

  Set<MessageFormat> _formatsAt(int offset) {
    final result = <MessageFormat>{};
    for (final s in _spans) {
      if (s.start <= offset && offset < s.end) result.add(s.format);
    }
    return result;
  }

  TextStyle _styleFor(Set<MessageFormat> formats, TextStyle? base) {
    var style = base ?? const TextStyle();
    if (formats.contains(MessageFormat.bold)) {
      style = style.copyWith(fontWeight: FontWeight.bold);
    }
    if (formats.contains(MessageFormat.italic)) {
      style = style.copyWith(fontStyle: FontStyle.italic);
    }
    final decorations = <TextDecoration>[];
    if (formats.contains(MessageFormat.underline)) {
      decorations.add(TextDecoration.underline);
    }
    if (formats.contains(MessageFormat.strikethrough)) {
      decorations.add(TextDecoration.lineThrough);
    }
    if (decorations.isNotEmpty) {
      style = style.copyWith(
        decoration: TextDecoration.combine(decorations),
      );
    }
    if (formats.contains(MessageFormat.monospace)) {
      style = style.copyWith(fontFamily: 'monospace');
    }
    if (formats.contains(MessageFormat.spoiler)) {
      // Спойлер в композере показываем серым фоном (текст виден — это ввод).
      style = style.copyWith(
        backgroundColor: const Color(0x33808080),
      );
    }
    return style;
  }

  // --- Черновик: сериализация спанов -------------------------------------

  String? serializeSpans() {
    if (_spans.isEmpty) return null;
    return jsonEncode(_spans.map((s) => s.toJson()).toList());
  }

  void restoreSpans(String? serialized, int textLength) {
    if (serialized == null || serialized.isEmpty) {
      setSpans(const [], textLength);
      return;
    }
    try {
      final decoded = jsonDecode(serialized);
      if (decoded is! List) {
        setSpans(const [], textLength);
        return;
      }
      setSpans(
        decoded
            .whereType<Map<String, dynamic>>()
            .map(FormatSpan.fromJson)
            .nonNulls
            .toList(),
        textLength,
      );
    } catch (_) {
      setSpans(const [], textLength);
    }
  }

  /// Поставить готовый список спанов на УЖЕ установленный текст длиной
  /// [textLength] (порядок «текст → спаны» обязателен: `set value` диффует
  /// старые спаны на новый текст, поэтому спаны ставим последними).
  ///
  /// Пустой список = сброс форматирования. Используется восстановлением
  /// черновика, префилом правки (`resolveEditPrefill`) и возвратом отложенного
  /// черновика после отмены/сохранения правки.
  void setSpans(List<FormatSpan> spans, int textLength) {
    _spans.clear();
    for (final span in spans) {
      // Защита от рассинхрона с установленным текстом.
      final end = span.end > textLength ? textLength : span.end;
      if (span.start >= end) continue;
      _spans.add(FormatSpan(span.start, end, span.format));
    }
    _mergeSpans();
    notifyListeners();
  }
}

/// Канонизировать список спанов: выбросить пустые, слить пересекающиеся и
/// смежные спаны ОДНОГО формата, отсортировать детерминированно.
///
/// Нужна на обоих концах: контроллеру — после тоггла/сдвига оффсетов, обратному
/// парсу (`formattedHtmlToSpans`) — потому что эмиттер режет спан по границам
/// ВЛОЖЕННОГО формата (`bold(0,7)` ⊃ `italic(4,7)` уходит двумя `<strong>`), и
/// без склейки round-trip не был бы тождественным.
List<FormatSpan> mergeFormatSpans(List<FormatSpan> spans) {
  final sorted =
      spans.where((s) => !s.isEmpty).map((s) => FormatSpan(s.start, s.end, s.format)).toList()
        ..sort((a, b) {
          final byFormat = a.format.index.compareTo(b.format.index);
          if (byFormat != 0) return byFormat;
          return a.start.compareTo(b.start);
        });
  final merged = <FormatSpan>[];
  for (final s in sorted) {
    if (merged.isNotEmpty &&
        merged.last.format == s.format &&
        s.start <= merged.last.end) {
      merged.last.end = math.max(merged.last.end, s.end);
    } else {
      merged.add(s);
    }
  }
  return merged;
}

/// Построить Matrix custom-HTML `formatted_body` из сырого текста и спанов.
/// Возвращает `null`, если форматирования нет (тогда сообщение уходит plain —
/// AC-3: набранные вручную символы остаются буквальными).
///
/// ИНВАРИАНТ INV-1: НЕ эмитим `<ul>/<ol>/<li>` — только инлайн-теги, иначе
/// `isForcedListArtifact` погасит рендер у получателя.
String? spansToFormattedHtml(String text, List<FormatSpan> spans) {
  final active = spans.where((s) => !s.isEmpty && s.start < text.length).toList();
  if (active.isEmpty || text.isEmpty) return null;

  // Границы сегментов.
  final boundarySet = <int>{0, text.length};
  for (final s in active) {
    if (s.start >= 0 && s.start <= text.length) boundarySet.add(s.start);
    final end = math.min(s.end, text.length);
    if (end >= 0) boundarySet.add(end);
  }
  final boundaries = boundarySet.toList()..sort();

  final buffer = StringBuffer();
  for (var i = 0; i < boundaries.length - 1; i++) {
    final segStart = boundaries[i];
    final segEnd = boundaries[i + 1];
    if (segEnd <= segStart) continue;
    final formats = <MessageFormat>{};
    for (final s in active) {
      final end = math.min(s.end, text.length);
      if (s.start <= segStart && segStart < end) formats.add(s.format);
    }
    final chunk = _escapeHtml(text.substring(segStart, segEnd));
    buffer.write(_wrapChunk(chunk, formats));
  }

  final html = buffer.toString();
  // Если разметки не появилось (напр. спаны схлопнулись) — не шлём formatted_body.
  if (html == _escapeHtml(text)) return null;
  return html;
}

/// Канонический порядок тегов (детерминизм вложенности — INV nested/AC-2).
const List<MessageFormat> _tagOrder = [
  MessageFormat.bold,
  MessageFormat.italic,
  MessageFormat.underline,
  MessageFormat.strikethrough,
  MessageFormat.monospace,
  MessageFormat.spoiler,
];

String _wrapChunk(String escapedChunk, Set<MessageFormat> formats) {
  if (formats.isEmpty) return escapedChunk;
  final open = StringBuffer();
  final close = <String>[];
  for (final format in _tagOrder) {
    if (!formats.contains(format)) continue;
    switch (format) {
      case MessageFormat.bold:
        open.write('<strong>');
        close.add('</strong>');
      case MessageFormat.italic:
        open.write('<em>');
        close.add('</em>');
      case MessageFormat.underline:
        open.write('<u>');
        close.add('</u>');
      case MessageFormat.strikethrough:
        open.write('<del>');
        close.add('</del>');
      case MessageFormat.monospace:
        open.write('<code>');
        close.add('</code>');
      case MessageFormat.spoiler:
        open.write('<span data-mx-spoiler>');
        close.add('</span>');
    }
  }
  return '$open$escapedChunk${close.reversed.join()}';
}

String _escapeHtml(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    // Переносы строк → <br>, иначе браузерные Matrix-клиенты (Element Web) при
    // рендере formatted_body схлопывают \n в пробел (HTML whitespace collapsing).
    // Так же поступает SDK markdown()-путь.
    .replaceAll('\n', '<br>');
