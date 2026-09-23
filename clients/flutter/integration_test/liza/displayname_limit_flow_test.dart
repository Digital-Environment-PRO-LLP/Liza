// Device-flow страж (Ярус C, живой прогон на iOS+Android) лимита отображаемого
// имени — LABA-2549.
// ledger:RL-displayname-input-limit
//
// Host widget-тест (test/displayname_input_limit_test.dart) рендерит диалог в
// изоляции. Здесь проверяем НАБЛЮДАЕМОЕ пользователем на реальном бинаре:
// экран настроек → тап по своему имени → ввод 300 символов → окно НЕ выросло,
// поле осталось однострочным, а после «Ок» алёрта «Displayname is too long»
// не появилось.
//
// Гоняется .claude/tools/prove-ui/run.sh на iOS И Android.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:liza/main.dart' as app;

import 'liza_flows.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'настройки → «Отображаемое имя»: 300 символов не ломают окно и не уходят на сервер',
    (tester) async {
      app.main();
      await tester.ensureLizaHome();

      // Настройки живут в меню аккаунта (аватар в шапке).
      await tester.pump(const Duration(milliseconds: 300));
      final avatarMenu = find.byType(PopupMenuButton).evaluate().isNotEmpty
          ? find.byType(PopupMenuButton).first
          : find.byIcon(Icons.add_outlined).first;
      await tester.tap(avatarMenu);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.waitUntil(find.text('Настройки'));
      await tester.tap(find.text('Настройки').last);
      await tester.pump(const Duration(milliseconds: 900));

      // Имя рисуется TextButton.icon с карандашом — он и открывает диалог.
      final editName = find.byIcon(Icons.edit_outlined);
      await tester.waitUntil(editName, timeout: const Duration(seconds: 15));
      await tester.tap(editName.first);
      await tester.pump(const Duration(milliseconds: 800));

      await tester.waitUntil(find.text('Отображаемое имя'));
      final field = find.byType(EditableText);
      expect(field, findsWidgets, reason: 'поле ввода имени не отрендерилось');

      // Базовая высота окна — до длинного ввода.
      final dialog = find.ancestor(
        of: find.text('Отображаемое имя'),
        matching: find.byType(Material),
      );
      final baseHeight = tester.getSize(dialog.last).height;

      await tester.enterText(field.first, 'a' * 300);
      await tester.pump(const Duration(milliseconds: 500));

      // Наблюдаемое #1: окно не разрослось (корень LABA-2549).
      expect(
        tester.getSize(dialog.last).height,
        baseHeight,
        reason: 'диалог вырос при вводе 300 символов — вернулся maxLines: null',
      );
      expect(tester.takeException(), isNull);

      // Наблюдаемое #2: в поле осталось ровно 256 грапем.
      final controller = tester.widget<EditableText>(field.first).controller;
      expect(controller.text.characters.length, 256);

      // Наблюдаемое #3: после «Ок» серверной ошибки нет.
      await tester.tap(find.text('Ок').last);
      await tester.pump(const Duration(seconds: 3));
      expect(
        find.textContaining('too long', findRichText: true),
        findsNothing,
        reason: 'серверная ошибка «Displayname is too long» всё ещё долетает',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
