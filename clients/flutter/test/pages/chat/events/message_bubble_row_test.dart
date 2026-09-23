import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat/events/message_bubble_row.dart';

// Геометрия раскладки строки сообщения. Стоит на страже бага «галочка прочтения
// висела над пузырём у первого сообщения в группе»: проверяет ИМЕННО взаимное
// положение жёлоба (галочка/аватар) и пузыря, чего golden на изолированных
// иконках и интеграционные find.byType-тесты не ловят.

const _gutterKey = Key('gutter-content');
const _bubbleKey = Key('bubble');

Widget _gutter() => const SizedBox(
  width: 44,
  height: 16,
  child: ColoredBox(key: _gutterKey, color: Color(0xFF000000)),
);

Widget _bubble() => const SizedBox(
  key: _bubbleKey,
  width: 120,
  height: 40,
  child: ColoredBox(color: Color(0xFFCCCCCC)),
);

Future<void> _pump(
  WidgetTester tester, {
  required bool alignGutterToBubble,
  Widget? header,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: MessageBubbleRow(
            mainAxisAlignment: MainAxisAlignment.start,
            alignGutterToBubble: alignGutterToBubble,
            header: header,
            gutter: _gutter(),
            bubble: [_bubble()],
          ),
        ),
      ),
    ),
  );
}

double _top(WidgetTester tester, Key key) =>
    tester.getRect(find.byKey(key)).top;

void main() {
  group('MessageBubbleRow — выравнивание жёлоба и пузыря', () {
    testWidgets('своё первое-в-группе: верх галочки на верхней линии пузыря', (
      tester,
    ) async {
      await _pump(
        tester,
        alignGutterToBubble: true,
        header: const SizedBox(height: 16), // спейсер своего сообщения
      );
      expect(
        _top(tester, _gutterKey),
        moreOrLessEquals(_top(tester, _bubbleKey), epsilon: 0.5),
        reason: 'галочка должна сесть на верх пузыря, не висеть над ним',
      );
    });

    testWidgets(
      'робастность: выравнивание держится при ЛЮБОЙ высоте шапки (без зашитого числа)',
      (tester) async {
        // Старый фикс c хардкодом top:16 здесь бы упал (пузырь уехал на 30).
        await _pump(
          tester,
          alignGutterToBubble: true,
          header: const SizedBox(height: 30),
        );
        expect(
          _top(tester, _gutterKey),
          moreOrLessEquals(_top(tester, _bubbleKey), epsilon: 0.5),
        );
      },
    );

    testWidgets(
      'без шапки (сгруппированное): жёлоб и пузырь и так на одной линии',
      (tester) async {
        await _pump(tester, alignGutterToBubble: true, header: null);
        expect(
          _top(tester, _gutterKey),
          moreOrLessEquals(_top(tester, _bubbleKey), epsilon: 0.5),
        );
      },
    );

    testWidgets(
      'собеседник (alignGutterToBubble=false): аватар остаётся у ВЕРХА, выше пузыря',
      (tester) async {
        await _pump(
          tester,
          alignGutterToBubble: false,
          header: const SizedBox(height: 16),
        );
        // Аватар прибит к верху строки, пузырь сдвинут шапкой вниз → аватар выше.
        expect(
          _top(tester, _gutterKey),
          lessThan(_top(tester, _bubbleKey) - 1),
          reason: 'для собеседников аватар не опускается к пузырю (выбор UX)',
        );
      },
    );
  });
}
