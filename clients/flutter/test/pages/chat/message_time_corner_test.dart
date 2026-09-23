import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat/events/message_content.dart';

// Страж реестра регрессии: ledger:RL-message-time-corner (см. tests/registry/).
//
// Инвариант: время ОБЫЧНОГО текстового сообщения показывается строкой в правом
// НИЖНЕМ углу пузыря (единообразно с голосовыми/файлами), а сам пузырь держит
// ширину по СОДЕРЖИМОМУ. Ключевой риск — короткое сообщение («ок») НЕ должно
// раздуваться на всю доступную ширину: `Align(centerRight)` в колонке без
// `IntrinsicWidth` растягивается на весь max — это и был баг «Перемудрили».
//
// Рендерим РЕАЛЬНЫЙ виджет [CornerTimeLayout] (примитивы вместо Event → без
// Matrix Client, который вешает пул в testWidgets), как у AudioWaveform.

const _timeKey = Key('time');
const _contentKey = Key('content');

// Доступная (максимальная) ширина, в которую вложен пузырь.
const double _available = 600.0;

Widget _time() => Row(
  key: _timeKey,
  mainAxisSize: MainAxisSize.min,
  children: const [Text('12:09'), SizedBox(width: 3), Icon(Icons.done_all, size: 14)],
);

// Пузырь получает СВОБОДНЫЕ (loose) констрейнты по ширине — как в реальной
// вёрстке (Container с maxWidth + Column mainAxisSize.min). SizedBox задаёт
// доступный максимум, Align передаёт ребёнку loose-констрейнты, чтобы
// IntrinsicWidth мог сжаться по контенту.
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
    'короткий текст не раздувается, время в правом нижнем углу — ledger:RL-message-time-corner',
    (tester) async {
      await tester.pumpWidget(
        _host(
          CornerTimeLayout(
            content: const Text('ок', key: _contentKey),
            time: _time(),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      final layout = tester.getRect(find.byType(CornerTimeLayout));
      // Ширина по содержимому, а НЕ вся доступная (_available) — компактный пузырь.
      expect(
        layout.width,
        lessThan(200),
        reason: 'короткое сообщение не должно занимать всю ширину пузыря',
      );
      // Но не уже строки времени (IntrinsicWidth поднимает минимум до неё).
      final timeRect = tester.getRect(find.byKey(_timeKey));
      expect(layout.width, greaterThanOrEqualTo(timeRect.width));

      // Время — НИЖЕ текста и прижато вправо.
      final contentBottom = tester.getRect(find.byKey(_contentKey)).bottom;
      expect(timeRect.top, greaterThanOrEqualTo(contentBottom));
      expect(
        layout.right - timeRect.right,
        lessThan(20),
        reason: 'время прижато к правому краю пузыря',
      );
    },
  );

  // Доказательство, что страж ЛОВИТ регресс: та же раскладка БЕЗ IntrinsicWidth
  // (голый Column + Align) на короткий текст растягивается на всю доступную
  // ширину. Удаление IntrinsicWidth из [CornerTimeLayout] уронит тест выше.
  testWidgets('контроль: без IntrinsicWidth короткий пузырь раздувается на всю ширину', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Column(
          key: const Key('ctrlCol'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('ок'),
            Align(alignment: Alignment.centerRight, child: _time()),
          ],
        ),
      ),
    );
    final colW = tester.getSize(find.byKey(const Key('ctrlCol'))).width;
    expect(
      colW,
      closeTo(_available, 1),
      reason:
          'без IntrinsicWidth Align растягивает колонку на всю ширину — это и '
          'есть баг «Перемудрили», который чинит IntrinsicWidth',
    );
  });
}
