import 'package:flutter/material.dart';

import 'package:alchemist/alchemist.dart';

import 'package:liza/pages/chat/events/message_content.dart';

// Страж реестра регрессии: ledger:RL-message-time-corner (см. tests/registry/).
//
// Golden Яруса A на РЕАЛЬНЫЙ виджет [CornerTimeLayout] (время текста в правом
// нижнем углу пузыря). Дополняет структурный `message_time_corner_test.dart`
// пиксельным эталоном: правка `Align`/паддинга/удаление `IntrinsicWidth` внутри
// CornerTimeLayout детерминированно роняет эталон. Golden `message_time`
// рендерит другой виджет (MessageTime в изоляции) и этого не ловит.
//
// Loose-констрейнты (SizedBox доступной ширины + Align) — как в реальном пузыре,
// чтобы IntrinsicWidth сжимал короткое сообщение по контенту.

Widget _time() => Row(
  mainAxisSize: MainAxisSize.min,
  children: const [
    Text('12:09', style: TextStyle(fontSize: 11, color: Colors.white)),
    SizedBox(width: 3),
    Icon(Icons.done_all, size: 14, color: Colors.white),
  ],
);

Widget _bubble(String text) => SizedBox(
  width: 320,
  child: Align(
    alignment: Alignment.topLeft,
    child: Material(
      color: const Color(0xFF4C4B7A),
      borderRadius: BorderRadius.circular(16),
      child: CornerTimeLayout(
        content: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Text(
            text,
            style: const TextStyle(fontSize: 16, color: Colors.white),
          ),
        ),
        time: _time(),
      ),
    ),
  ),
);

void main() {
  goldenTest(
    'время текста в правом нижнем углу: короткое (компактный пузырь) vs длинное',
    fileName: 'message_corner_time',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'короткое «ок» — компактный пузырь, время под текстом справа',
          child: _bubble('ок'),
        ),
        GoldenTestScenario(
          name: 'длинное многострочное — время в правом нижнем углу',
          child: _bubble(
            'до ждфыо адфоы адофыд аождфыоа джфы аджфофыждао фдыжво аждфыо '
            'аждлофываджфыоа дфы аджфы жд',
          ),
        ),
      ],
    ),
  );
}
