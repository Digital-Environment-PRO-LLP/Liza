import 'package:flutter/material.dart';

import 'package:alchemist/alchemist.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/widgets/avatar.dart';

// Страж реестра регрессии: ledger:RL-deleted-bot-account (см. tests/registry/).
// Golden Яруса 0 на Avatar удалённого аккаунта (LABA-2242).
//
// Паттерн _drainMxcImageRetryTimers: Avatar без MatrixState / без valid uri
// запускает MxcImage._tryLoad с экспоненциальным backoff (2/4/8/16/30с).
// Без явного прокачивания тест оставляет pending-таймер и падает на
// «A Timer is still pending». Паттерн задокументирован в
// test/pages/chat_details/participant_row_tap_test.dart.
Future<void> _drainMxcImageRetryTimers(WidgetTester tester) async {
  for (final delay in const [
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 9),
    Duration(seconds: 17),
    Duration(seconds: 31),
  ]) {
    await tester.pump(delay);
  }
}
//
// AC-2: Avatar с isDeleted:true рендерит серый круг + Icon(Icons.person_off_outlined),
// НЕ букву/картинку. Правка цвета/иконки/размера в Avatar.build детерминированно
// роняет этот эталон.
//
// Рендерим РЕАЛЬНЫЙ виджет [Avatar] из lib/widgets/avatar.dart — не реплику.
// Avatar «глупый» по isDeleted: никаких Client/mxContent/localizations не нужно.

Widget _wrap(Widget child) => Padding(
      padding: const EdgeInsets.all(8),
      child: child,
    );

void main() {
  goldenTest(
    'Avatar удалённого аккаунта: серый призрак',
    fileName: 'deleted_bot_avatar',
    builder: () => GoldenTestGroup(
      columns: 2,
      children: [
        GoldenTestScenario(
          name: 'isDeleted:true (размер 44)',
          child: _wrap(
            const Avatar(isDeleted: true),
          ),
        ),
        GoldenTestScenario(
          name: 'isDeleted:true (размер 32 — шапка чата)',
          child: _wrap(
            const Avatar(isDeleted: true, size: 32),
          ),
        ),
      ],
    ),
  );

  // Структурные ассерты: иконка person_off_outlined присутствует;
  // буква/имя НЕ присутствует при isDeleted:true.
  // AC:RL-deleted-bot-account/2
  testWidgets(
    'Avatar isDeleted:true — Icon(person_off_outlined) есть, текст имени нет — ledger:RL-deleted-bot-account',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Avatar(
                isDeleted: true,
                name: 'SomeBot',
                mxContent: null,
              ),
            ),
          ),
        ),
      );

      // AC:RL-deleted-bot-account/2: иконка-призрак рендерится
      expect(
        find.byIcon(Icons.person_off_outlined),
        findsOneWidget,
        reason: 'Avatar(isDeleted:true) ОБЯЗАН рендерить Icon(person_off_outlined)',
      );

      // Буква имени НЕ должна рендериться
      expect(
        find.text('S'),
        findsNothing,
        reason: 'буква имени не показывается при isDeleted:true',
      );
    },
  );

  testWidgets(
    'Avatar isDeleted:false — обычная буква, нет person_off_outlined — ledger:RL-deleted-bot-account',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Avatar(
                isDeleted: false,
                name: 'AliveBot',
                mxContent: null,
              ),
            ),
          ),
        ),
      );
      // MxcImage при uri=null запускает retry-таймеры (см. _drainMxcImageRetryTimers).
      await _drainMxcImageRetryTimers(tester);

      // isDeleted:false → нет иконки-призрака
      expect(
        find.byIcon(Icons.person_off_outlined),
        findsNothing,
        reason: 'isDeleted:false НЕ должен рендерить person_off_outlined',
      );
    },
  );
}
