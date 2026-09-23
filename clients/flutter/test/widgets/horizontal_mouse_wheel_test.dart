import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/widgets/horizontal_mouse_wheel.dart';

// Страж реестра регрессии: ledger:RL-horizontal-mouse-wheel (см. tests/registry/).
// LABA-2240: на Windows обычная мышь (только вертикальное колесо, dy) не крутит
// горизонтальные ряды — горизонтальный Scrollable во Flutter берёт дельту из dx.
// HorizontalMouseWheel переводит dy в горизонтальную прокрутку, регистрируясь в
// pointerSignalResolver (иначе родительский вертикальный список поехал бы вниз
// одновременно — двойное движение). Тест гоняет РЕАЛЬНЫЙ виджет внутри
// вертикального CustomScrollView.
void main() {
  late ScrollController horizontal;
  late ScrollController vertical;

  setUp(() {
    horizontal = ScrollController();
    vertical = ScrollController();
  });

  tearDown(() {
    horizontal.dispose();
    vertical.dispose();
  });

  Widget harness() => MaterialApp(
    home: Scaffold(
      body: CustomScrollView(
        controller: vertical,
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: 80,
              child: HorizontalMouseWheel(
                controller: horizontal,
                child: ListView.builder(
                  controller: horizontal,
                  scrollDirection: Axis.horizontal,
                  itemCount: 40,
                  itemBuilder: (_, i) =>
                      SizedBox(width: 120, child: Center(child: Text('$i'))),
                ),
              ),
            ),
          ),
          // Высокий филлер, чтобы вертикальный список МОГ прокрутиться —
          // иначе проверка «родитель докрутил на краю» ничего не покажет.
          const SliverToBoxAdapter(child: SizedBox(height: 2000)),
        ],
      ),
    ),
  );

  Future<void> wheel(
    WidgetTester tester,
    double dy, {
    PointerDeviceKind kind = PointerDeviceKind.mouse,
  }) async {
    final pointer = TestPointer(1, kind);
    final center = tester.getCenter(find.byType(HorizontalMouseWheel));
    pointer.hover(center);
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
  }

  testWidgets(
    'колесо мыши вниз крутит ряд вправо, вверх — влево — '
    'ledger:RL-horizontal-mouse-wheel AC:RL-horizontal-mouse-wheel/1',
    (tester) async {
      await tester.pumpWidget(harness());
      expect(horizontal.offset, 0);

      await wheel(tester, 120);
      expect(horizontal.offset, greaterThan(0), reason: 'dy>0 → вправо');

      final afterDown = horizontal.offset;
      await wheel(tester, -60);
      expect(horizontal.offset, lessThan(afterDown), reason: 'dy<0 → влево');
    },
  );

  testWidgets(
    'вертикальная позиция родителя НЕ меняется (анти-задвоение F-1) — '
    'ledger:RL-horizontal-mouse-wheel AC:RL-horizontal-mouse-wheel/2',
    (tester) async {
      await tester.pumpWidget(harness());
      expect(vertical.offset, 0);

      await wheel(tester, 120);

      expect(horizontal.offset, greaterThan(0));
      expect(
        vertical.offset,
        0,
        reason: 'обёртка выиграла резолвер → родитель не поехал вниз',
      );
    },
  );

  testWidgets(
    'ряд у края → событие отдаётся родителю, вертикаль докручивается (F-2) — '
    'ledger:RL-horizontal-mouse-wheel AC:RL-horizontal-mouse-wheel/3',
    (tester) async {
      await tester.pumpWidget(harness());
      // Прокручиваем ряд до конца — двигаться вправо больше некуда.
      horizontal.jumpTo(horizontal.position.maxScrollExtent);
      await tester.pump();
      final atEnd = horizontal.offset;
      expect(vertical.offset, 0);

      await wheel(tester, 120);

      expect(horizontal.offset, atEnd, reason: 'ряд остался у края');
      expect(
        vertical.offset,
        greaterThan(0),
        reason: 'на краю обёртка не перехватывает → родитель докрутил',
      );
    },
  );

  testWidgets(
    'трекпад (kind != mouse) обёртка не перехватывает — '
    'ledger:RL-horizontal-mouse-wheel AC:RL-horizontal-mouse-wheel/4',
    (tester) async {
      await tester.pumpWidget(harness());

      await wheel(tester, 120, kind: PointerDeviceKind.trackpad);

      expect(
        horizontal.offset,
        0,
        reason: 'у трекпада обе оси работают нативно — не вмешиваемся',
      );
    },
  );
}
