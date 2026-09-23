import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

// Страж реестра регрессии: ledger:RL-message-footer-row (см. tests/registry/).
//
// Инвариант: у ТЕКСТОВОГО сообщения футер занимает ширину пузыря и разводит две
// метки по краям НА ОДНОМ УРОВНЕ: «изменено» (карандаш + время правки) — в ЛЕВОМ
// нижнем углу, время отправки (HH:MM + галочки статуса своих) — в ПРАВОМ. Оба
// времени ВСЕГДА на одной строке (одна вертикаль). Пузырь держит ширину по
// содержимому (короткое «ок» не раздувается), футер выравнивается по правому
// краю ВСЕГО пузыря даже при широкой reply-цитате (а не по краю узкого текста).
//
// Раньше время текста жило внутри CornerTimeLayout.IntrinsicWidth (обнимал только
// текст), reply-цитата была сиблингом снаружи → при широкой цитате время уезжало
// «в середину»; метка «изменено» была отдельным Row без Align → на своей строке
// слева. Фикс (message.dart): reply + текст + футер под ОДНИМ IntrinsicWidth;
// футер = Row(spaceBetween) — «изменено» слева, время справа, один уровень.
//
// Тест воспроизводит РЕАЛЬНУЮ форму футера на примитивах (без Matrix Client,
// который вешает пул в testWidgets). reply мимикрирует ReplyContent (Row с
// Flexible) — заодно доказывает, что Flexible-в-Row под IntrinsicWidth НЕ бросает.

const double _available = 600.0;

const _editKey = Key('edit');
const _timeKey = Key('time');
const _replyKey = Key('reply');

// Мимикрия ReplyContent: Row(min) с Container-полоской + Flexible(Column[Text,
// Text]) — та же ФОРМА (Flexible вокруг Column из текстов), что у реального
// ReplyContent, попадающая под IntrinsicWidth после фикса. Ширину набираем
// длинным именем/строкой, чтобы цитата была ШИРЕ короткого «ок».
Widget _replyMock({required double textWidth}) => Row(
  key: _replyKey,
  mainAxisSize: MainAxisSize.min,
  children: [
    Container(width: 5, height: 32, color: Colors.blue),
    const SizedBox(width: 6),
    Flexible(
      child: SizedBox(
        width: textWidth,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Автор цитаты:', maxLines: 1),
            Text('цитата длинного исходного сообщения', maxLines: 1),
          ],
        ),
      ),
    ),
  ],
);

// «Изменено» — левая часть футера (карандаш + время правки).
Widget _editIndicator() => Row(
  key: _editKey,
  mainAxisSize: MainAxisSize.min,
  children: const [
    Icon(Icons.edit_outlined, size: 14),
    SizedBox(width: 3),
    Text('17:55'),
  ],
);

// Время отправки + статус — правая часть футера.
Widget _sendTime() => Row(
  key: _timeKey,
  mainAxisSize: MainAxisSize.min,
  children: const [
    Text('12:09'),
    SizedBox(width: 3),
    Icon(Icons.done_all, size: 14),
  ],
);

// Тело пузыря как после фикса: всё под ОДНИМ IntrinsicWidth; футер — Row во всю
// ширину пузыря со spaceBetween (edited слева, время справа).
Widget _bubbleBody({
  Widget? reply,
  required String text,
  bool edited = false,
}) => IntrinsicWidth(
  child: Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (reply != null) reply,
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
        child: Text(text, key: const Key('content')),
      ),
      Padding(
        padding: const EdgeInsets.only(left: 16, right: 12, top: 2, bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (edited) _editIndicator() else const SizedBox.shrink(),
            _sendTime(),
          ],
        ),
      ),
    ],
  ),
);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      width: _available,
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

void main() {
  testWidgets(
    'широкая reply-цитата: время справа у края ПУЗЫРЯ, «изменено» слева — на '
    'одном уровне — ledger:RL-message-footer-row',
    (tester) async {
      await tester.pumpWidget(
        _host(
          _bubbleBody(
            reply: _replyMock(textWidth: 260),
            text: 'ок',
            edited: true,
          ),
        ),
      );
      // Flexible-в-Row под IntrinsicWidth не бросает.
      expect(tester.takeException(), isNull);

      final bubble = tester.getRect(find.byType(IntrinsicWidth));
      final replyRect = tester.getRect(find.byKey(_replyKey));
      final editRect = tester.getRect(find.byKey(_editKey));
      final timeRect = tester.getRect(find.byKey(_timeKey));

      // Пузырь обнял ШИРОКУЮ цитату (короткий текст «ок» не сжал пузырь).
      expect(
        bubble.width,
        greaterThan(200),
        reason: 'пузырь держит ширину по широкому сиблингу (reply)',
      );
      expect(bubble.width, lessThan(_available));
      expect(replyRect.width, greaterThan(200));

      // КЛЮЧЕВОЕ: время отправки прижато к ПРАВОМУ краю пузыря, «изменено» — к
      // ЛЕВОМУ, оба на одном уровне.
      expect(
        bubble.right - timeRect.right,
        lessThan(20),
        reason: 'время отправки в правом нижнем углу пузыря, не «в середину» '
            'AC:RL-message-footer-row/3',
      );
      expect(
        editRect.left - bubble.left,
        lessThan(24),
        reason: '«изменено» прижато к левому нижнему углу пузыря '
            'AC:RL-message-footer-row/2',
      );
      expect(editRect.right, lessThan(timeRect.left));
      expect(
        (editRect.center.dy - timeRect.center.dy).abs(),
        lessThan(2),
        reason: '«изменено» и время отправки — на одном уровне',
      );
    },
  );

  testWidgets('без reply короткое «ок» не раздувается, время справа '
      '— ledger:RL-message-footer-row', (tester) async {
    await tester.pumpWidget(_host(_bubbleBody(text: 'ок')));
    expect(tester.takeException(), isNull);

    final bubble = tester.getRect(find.byType(IntrinsicWidth));
    final timeRect = tester.getRect(find.byKey(_timeKey));

    // Пузырь компактный — не на всю доступную ширину (инвариант «Перемудрили»).
    expect(
      bubble.width,
      lessThan(_available - 100),
      reason: 'короткое сообщение без сиблинга не раздувается '
          'AC:RL-message-footer-row/4',
    );
    // Без правки «изменено» нет, время прижато вправо.
    expect(find.byKey(_editKey), findsNothing);
    expect(bubble.right - timeRect.right, lessThan(20));
  });

  testWidgets('отредактированное: «изменено» слева, время справа, один уровень '
      '— ledger:RL-message-footer-row', (tester) async {
    await tester.pumpWidget(
      _host(_bubbleBody(text: 'редактирую и проверяю', edited: true)),
    );
    final editRect = tester.getRect(find.byKey(_editKey));
    final timeRect = tester.getRect(find.byKey(_timeKey));
    final bubble = tester.getRect(find.byType(IntrinsicWidth));

    // Один уровень (одна вертикаль).
    expect(
      (editRect.center.dy - timeRect.center.dy).abs(),
      lessThan(2),
      reason: '«изменено» и время — на одной строке',
    );
    // «изменено» слева, время справа, разведены по краям пузыря.
    expect(editRect.left, lessThan(timeRect.left));
    expect(editRect.left - bubble.left, lessThan(24));
    expect(bubble.right - timeRect.right, lessThan(20));
  });
}
