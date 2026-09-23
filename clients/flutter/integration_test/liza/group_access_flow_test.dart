// Device-flow страж (Ярус C, живой прогон на iOS+Android) тумблера
// «Тип группы» (Публичная/Частная) и пути создания группы.
// ledger:RL-group-access-settings-layout
// ledger:RL-group-permissions-enforcement
//
// Воспроизводим ДЕЙСТВИЯ пользователя на реальном бинаре против локального
// стека (APP_ENV=local), измеряя USER-VISIBLE эффект (не внутренний флаг):
//   1. Создать группу через UI («+» → «Создать группу» → имя → создать) —
//      это исполняет реальный _createGroup с groupPowerLevelOverride() (invite:50).
//   2. Дойти до «Доступность и видимость» новой (приватной) группы.
//   3. Блок «Тип группы» присутствует, выбран сегмент «Частная».
//   4. Тап «Публичная» → сегмент реально переключается на «Публичная»
//      (наблюдаемый эффект на прод-виджете SegmentedButton, а не только флаг).
//   5. Видимость истории редактируема в публичном режиме (radio enabled) —
//      защита от переезда read-only-гейта канала на группу.
// Гоняется .claude/tools/prove-ui/run.sh на iOS И Android.

import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_app_bar_title.dart';
import 'package:liza/pages/chat_list/chat_list_body.dart';

import 'liza_flows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('создание группы → «Тип группы» Частная→Публичная живьём',
      (tester) async {
    app.main();
    await tester.ensureLizaHome();

    final groupName = 'Группа Доступ ${DateTime.now().millisecondsSinceEpoch}';

    // 1. «+» → «Создать группу».
    final plus = find.byIcon(Icons.add_outlined);
    await tester.waitUntil(plus);
    await tester.tap(plus.first);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.waitUntil(find.text('Создать группу'));
    await tester.tap(find.text('Создать группу').last);
    await tester.pump(const Duration(milliseconds: 700));

    // 2. Имя + создать (исполняет _createGroup с invite:50).
    final nameField = find.byType(TextField);
    await tester.waitUntil(nameField);
    await tester.enterText(nameField.first, groupName);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.waitUntil(find.text('Создать и начать приглашать'));
    await tester.tap(find.text('Создать и начать приглашать').last);
    await tester.pump(const Duration(milliseconds: 1500));

    // 3. Подтверждаем, что создание прошло — открылся экран приглашения
    //    («Пригласить» + список кандидатов). Комната уже в sync.
    await tester.waitUntil(find.text('Пригласить'),
        timeout: const Duration(seconds: 25));
    await tester.pump(const Duration(milliseconds: 800));

    // 4. Возвращаемся из экрана приглашения в СПИСОК чатов (может понадобиться
    //    несколько «назад»), затем открываем группу по имени (прокручивая).
    final chatList = find.byType(ChatListViewBody);
    for (var attempt = 0; attempt < 6 && chatList.evaluate().isEmpty; attempt++) {
      final back = find.byType(BackButton);
      if (back.evaluate().isNotEmpty) {
        await tester.tap(back.first, warnIfMissed: false);
      }
      await tester.pump(const Duration(milliseconds: 1000));
    }
    await tester.waitUntil(chatList, timeout: const Duration(seconds: 20));

    final groupTile = find.text(groupName);
    final findEnd = DateTime.now().add(const Duration(seconds: 30));
    while (groupTile.evaluate().isEmpty && DateTime.now().isBefore(findEnd)) {
      final scrollable = find.byType(Scrollable);
      if (scrollable.evaluate().isNotEmpty) {
        await tester.drag(scrollable.first, const Offset(0, -260));
      }
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.waitUntil(groupTile, timeout: const Duration(seconds: 10));
    await tester.tap(groupTile.last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 1200));

    // На экране чата — тап по заголовку открывает детали.
    final appBarTitle = find.byType(ChatAppBarTitle);
    await tester.waitUntil(appBarTitle, timeout: const Duration(seconds: 20));
    await tester.tap(appBarTitle.first);
    await tester.pump(const Duration(milliseconds: 900));

    // 4. «Доступность и видимость».
    await tester.waitUntil(find.text('Доступность и видимость'),
        timeout: const Duration(seconds: 20));
    await tester.tap(find.text('Доступность и видимость').last);
    await tester.pump(const Duration(milliseconds: 900));

    // 5. Блок «Тип группы» присутствует, выбрана «Частная».
    await tester.waitUntil(find.text('Тип группы'),
        timeout: const Duration(seconds: 20));
    expect(find.text('Тип группы'), findsOneWidget,
        reason: 'Блок «Тип группы» не отрисован для новой группы');

    SegmentedButton<bool> segment() => tester.widget<SegmentedButton<bool>>(
          find.byType(SegmentedButton<bool>),
        );
    expect(segment().selected, equals({false}),
        reason: 'Новая группа приватна → сегмент «Частная»');

    // 6. Тап «Публичная» → наблюдаемое переключение сегмента.
    await tester.tap(find.text('Публичная').last);
    // setGroupPublic пишет join_rules, UI обновится по /sync-эху onRoomState.
    final end = DateTime.now().add(const Duration(seconds: 25));
    while (segment().selected.first != true && DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(segment().selected, equals({true}),
        reason: 'После тапа «Публичная» сегмент обязан показать «Публичная» '
            '(наблюдаемый эффект, не только внутренний флаг)');

    // 7. История редактируема и в публичном режиме (не read-only, как у канала).
    final historyTiles = tester
        .widgetList<RadioListTile<HistoryVisibility>>(
          find.byType(RadioListTile<HistoryVisibility>),
        )
        .toList();
    expect(historyTiles.isNotEmpty, isTrue,
        reason: 'Раздел видимости истории должен присутствовать у группы');
    for (final tile in historyTiles) {
      expect(tile.enabled, isTrue,
          reason: 'Видимость истории публичной ГРУППЫ должна быть редактируема '
              '(read-only — только у публичного канала)');
    }

    expect(tester.takeException(), isNull);
  });
}
