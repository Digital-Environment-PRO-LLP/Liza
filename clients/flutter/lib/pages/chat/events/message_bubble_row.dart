import 'package:flutter/material.dart';

/// Раскладка строки сообщения в ленте чата: слева — 44-px «жёлоб» (аватар
/// собеседника / галочка прочтения своего сообщения / чекбокс выделения),
/// справа — колонка из необязательной шапки (имя+роль или спейсер) и пузыря.
///
/// Зачем отдельный виджет: выравнивание жёлоба и пузыря — частый источник
/// визуальных регрессий (галочка «висела» над пузырём у первого сообщения в
/// группе), а внутри `Message.build` это не протестировать без подъёма Matrix.
/// Здесь логика изолирована и покрыта `test/pages/chat/events/
/// message_bubble_row_test.dart` (геометрия + golden).
///
/// Инвариант: при [alignGutterToBubble] верх жёлоба совпадает с верхом пузыря
/// независимо от высоты шапки — жёлоб опускается ровно на высоту [header]
/// (невидимая копия, занимающая место), без магических чисел.
class MessageBubbleRow extends StatelessWidget {
  /// Опустить жёлоб к верхней линии пузыря (для своих сообщений — галочка
  /// прочтения). Для собеседников `false`: аватар остаётся у верха, рядом с
  /// именем. Ожидает узкую [header] (спейсер), иначе жёлоб расширится.
  final bool alignGutterToBubble;

  final MainAxisAlignment mainAxisAlignment;

  /// Шапка над пузырём (имя+роль / спейсер). `null` — если сообщение не первое
  /// в группе (шапки нет).
  final Widget? header;

  /// Содержимое 44-px жёлоба: аватар, галочка или чекбокс выделения.
  final Widget gutter;

  /// Содержимое справа под шапкой: основной пузырь и (опционально) подпись-бабл
  /// медиа. Список, т.к. это несколько детей одной колонки.
  final List<Widget> bubble;

  const MessageBubbleRow({
    required this.mainAxisAlignment,
    required this.gutter,
    required this.bubble,
    this.header,
    this.alignGutterToBubble = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final header = this.header;
    final gutter = alignGutterToBubble && header != null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Невидимая копия шапки занимает её высоту и сдвигает жёлоб вниз
              // ровно на столько же — галочка садится на верхнюю линию пузыря.
              // Высота шапки может меняться (шрифт имени, бейдж роли), но
              // выравнивание остаётся верным: число нигде не зашито.
              Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: header,
              ),
              this.gutter,
            ],
          )
        : this.gutter;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: mainAxisAlignment,
      children: [
        gutter,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [if (header != null) header, ...bubble],
          ),
        ),
      ],
    );
  }
}
