import 'package:flutter/material.dart';

import 'package:alchemist/alchemist.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat/events/message_time.dart';

// Страж реестра регрессии: ledger:RL-receipts-indicators (см. tests/registry/).
// Golden Яруса 0 на индикаторы прочтения сообщения (см. tests/e2e.md §4а).
// Это поверхность, которая ломалась 4 раза при рерайте квитанций (см. §9 —
// «баги пятницы»): галочки done/done_all и иконка отправки.
//
// ВАЖНО (урок комиссии 2026-06-16): рендерим РЕАЛЬНЫЙ виджет
// [MessageReadIndicator] из message_time.dart, а не его копию. Цвета приходят из
// `colorScheme` темы (Alchemist оборачивает в Material), не из литералов —
// поэтому правка иконки/размера/маппинга цвета в проде детерминированно роняет
// этот тест. (Раньше тест рендерил изолированные Icon с захардкоженными
// цветами → ложно-зелёный: прод можно было сломать, эталон не падал.)

Widget _scenario({required bool isSending, required bool isRead}) => Padding(
  padding: const EdgeInsets.all(8),
  child: MessageReadIndicator(isSending: isSending, isRead: isRead),
);

void main() {
  goldenTest(
    'индикаторы прочтения: sending / sent / read',
    fileName: 'receipts_indicators',
    builder: () => GoldenTestGroup(
      columns: 3,
      children: [
        GoldenTestScenario(
          name: 'sending',
          child: _scenario(isSending: true, isRead: false),
        ),
        GoldenTestScenario(
          name: 'sent',
          child: _scenario(isSending: false, isRead: false),
        ),
        GoldenTestScenario(
          name: 'read',
          child: _scenario(isSending: false, isRead: true),
        ),
      ],
    ),
  );

  // Geometry-ассерт: иконка статуса — фиксированный размер 14 (выравнивание
  // относительно пузыря). Структурная проверка без магических чисел вёрстки,
  // дополняет пиксельный эталон (см. feedback_golden_layout_real_widget).
  testWidgets('индикатор прочтения: размер иконки 14 — ledger:RL-receipts-indicators', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: MessageReadIndicator(isSending: false, isRead: true)),
        ),
      ),
    );
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon, Icons.done_all_rounded);
    expect(icon.size, 14);
  });
}
