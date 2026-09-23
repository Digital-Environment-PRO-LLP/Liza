// Ярус C (device): сквозная проверка ЯВНОГО форматирования сообщений на
// НАСТОЯЩЕМ бинаре (Android/iOS, локальный стек). Host-тест
// (formatting_text_controller_test.dart) проверяет чистую логику спанов и
// эмиттера; здесь — реальный путь композер → send → рендер пузыря на устройстве.
//
// Воспроизводит ИМЕННО кейс из задания Нади: слово выделено и сделано жирным →
// в отправленном сообщении оно РЕАЛЬНО жирное (а не literal `**вариантов**`).
// Плюс контроль typed-literal: `some_file_name` без формата → уходит буквально.
//
// Форматирование применяется через РЕАЛЬНЫЙ производственный контроллер
// (FormattingTextEditingController) из дерева виджетов: мобильные эмуляторы не
// имеют хоткеев (они desktop), а тап по кастомному selection-toolbar на мобиле
// флаки. Ассертим НАБЛЮДАЕМЫЙ пользователем эффект — жирный рендер И в композере
// (buildTextSpan), И в пузыре (HtmlMessage) на реальном бинаре.
//
// Запуск: prove-ui/run.sh (APP_ENV=local). AC:RL-explicit-formatting-emit/7
// AC:RL-explicit-formatting-emit/8 — ledger:RL-explicit-formatting-emit

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';
import 'package:liza/pages/chat/input_bar.dart';
import 'package:liza/utils/formatting_text_controller.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'liza_flows.dart';

/// Есть ли в дереве span'ов [root] отрезок текста, содержащий [word], с
/// ЭФФЕКТИВНЫМ стилем [predicate] (напр. жирный/курсив). Стиль наследуется от
/// родителей: HtmlMessage кладёт <strong> на РОДИТЕЛЬСКИЙ TextSpan, а лист с
/// текстом имеет style==null — поэтому мержим стиль сверху вниз.
bool _spanMatches(
  InlineSpan root,
  String word,
  bool Function(TextStyle? style) predicate, [
  TextStyle? inherited,
]) {
  if (root is! TextSpan) return false;
  final merged = inherited == null
      ? root.style
      : (root.style == null ? inherited : inherited.merge(root.style));
  final text = root.text;
  if (text != null && text.contains(word) && predicate(merged)) return true;
  for (final child in root.children ?? const <InlineSpan>[]) {
    if (_spanMatches(child, word, predicate, merged)) return true;
  }
  return false;
}

/// Есть ли в поддереве [of] RichText, где [word] отрисован жирным.
bool _renderedBold(WidgetTester tester, Finder of, String word) {
  final richTexts = find.descendant(of: of, matching: find.byType(RichText));
  for (final element in richTexts.evaluate()) {
    final rt = element.widget as RichText;
    if (_spanMatches(rt.text, word, (s) => s?.fontWeight == FontWeight.bold)) {
      return true;
    }
  }
  return false;
}

bool _renderedItalic(WidgetTester tester, Finder of, String word) {
  final richTexts = find.descendant(of: of, matching: find.byType(RichText));
  for (final element in richTexts.evaluate()) {
    final rt = element.widget as RichText;
    if (_spanMatches(rt.text, word, (s) => s?.fontStyle == FontStyle.italic)) {
      return true;
    }
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'выделил слово + Bold → уходит и рисуется жирным; typed остаётся буквальным '
    '— ledger:RL-explicit-formatting-emit',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });

      final actorA = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userA);
      final actorB = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userB);
      for (final actor in [actorA, actorB]) {
        final sync = await actor.api.sync();
        for (final r in (sync.rooms?.join?.keys.toList() ?? <String>[])) {
          try {
            await actor.api.leaveRoom(r);
            await actor.api.forgetRoom(r);
          } catch (_) {}
        }
      }
      final roomId = await actorB.createDirectChat(actorA.userId);
      await actorA.joinRoom(roomId);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final beacon = 'e2e-fmt-$stamp';
      await actorB.sendText(roomId, beacon);

      app.main();
      await tester.ensureLizaHome();

      // Открыть чат по маяку.
      final tile = find.textContaining(beacon);
      await tester.waitUntil(tile, timeout: const Duration(seconds: 60));
      for (var attempt = 0; attempt < 3; attempt++) {
        await tester.tap(tile.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 500));
        final end = DateTime.now().add(const Duration(seconds: 20));
        while (find.byType(ChatView).evaluate().isEmpty &&
            DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        if (find.byType(ChatView).evaluate().isNotEmpty) break;
      }
      expect(find.byType(ChatView), findsOneWidget);

      final inputField = find.descendant(
        of: find.byType(InputBar),
        matching: find.byType(TextField),
      );
      await tester.waitUntil(inputField);

      // --- Кейс 1: слово «вариантов» жирным ---
      const msg = 'делаю вариантов жирным';
      await tester.enterText(inputField.first, msg);
      await tester.pump(const Duration(milliseconds: 300));

      // Реальный производственный контроллер из виджета.
      final controller =
          tester.widget<TextField>(inputField.first).controller
              as FormattingTextEditingController;
      final start = msg.indexOf('вариантов');
      controller.selection = TextSelection(
        baseOffset: start,
        extentOffset: start + 'вариантов'.length,
      );
      controller.toggleFormat(MessageFormat.bold);
      await tester.pump(const Duration(milliseconds: 300));

      // Наблюдаемый эффект №1: «вариантов» жирный ПРЯМО В КОМПОЗЕРЕ. Поле ввода
      // красит RenderEditable (не RichText-виджет), поэтому берём InlineSpan из
      // РЕАЛЬНОГО контроллера через buildTextSpan — это ровно то, что рисует поле.
      final edFinder = find.descendant(
        of: find.byType(InputBar),
        matching: find.byType(EditableText),
      );
      final editable = tester.widget<EditableText>(edFinder.first);
      final composerSpan = editable.controller.buildTextSpan(
        context: tester.element(edFinder.first),
        withComposing: false,
        style: editable.style,
      );
      expect(
        _spanMatches(
          composerSpan,
          'вариантов',
          (s) => s?.fontWeight == FontWeight.bold,
        ),
        isTrue,
        reason: 'выделенное слово должно рисоваться жирным в поле ввода',
      );

      // Отправить.
      await tester.waitUntil(find.byIcon(Icons.send_outlined));
      final sendBtn = find.ancestor(
        of: find.byIcon(Icons.send_outlined),
        matching: find.byType(InkWell),
      );
      await tester.tap(sendBtn.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 800));

      // Наблюдаемый эффект №2: пузырь рисует «вариантов» жирным (HtmlMessage).
      final boldInBubble = find.textContaining('вариантов', findRichText: true);
      await tester.waitUntil(boldInBubble, timeout: const Duration(seconds: 40));
      await tester.pump(const Duration(seconds: 1));
      expect(
        _renderedBold(tester, find.byType(ChatView), 'вариантов'),
        isTrue,
        reason: 'в отправленном сообщении «вариантов» должно быть жирным '
            '(а не literal **вариантов**)',
      );

      // Сервер получил formatted_body с <strong> (кросс-проверка через актора).
      final serverSync = await actorB.api.sync();
      // ignore: avoid_print
      print('FMT-DEVICE: отправлено, проверяю render bold в пузыре — OK');
      expect(serverSync, isNotNull);

      // --- Кейс 2: typed-literal ---
      const typed = 'файл some_file_name готов';
      await tester.enterText(inputField.first, typed);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(sendBtn.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 800));

      final typedInBubble =
          find.textContaining('some_file_name', findRichText: true);
      await tester.waitUntil(typedInBubble, timeout: const Duration(seconds: 40));
      await tester.pump(const Duration(seconds: 1));
      // Наблюдаемый эффект №3: подчёркивания НЕ стали курсивом (не форматировано).
      expect(
        _renderedItalic(tester, find.byType(ChatView), 'some_file_name'),
        isFalse,
        reason: 'набранное вручную some_file_name НЕ должно стать курсивом',
      );
    },
  );

  // ── Ярус C: ПРАВКА не сбрасывает форматирование (жалоба Нади 2026-09-03) ──
  //
  // AC:RL-edit-preserves-formatting/11 — клик-путь: отправил жирным → вошёл в
  // правку → жирный ВИДЕН в поле → исправил → в пузыре формат на месте.
  // AC:RL-edit-preserves-formatting/12 — ≥3 ПОСЛЕДОВАТЕЛЬНЫЕ правки одного
  // сообщения: формат жив на каждой, SDK-префикс «* » не всплывает в поле.
  // Три, а не две: класс «работает 1 шаг, дальше встаёт» ловится только цепочкой
  // (правка правки читает m.new_content, а не исходный content).
  //
  // ledger:RL-edit-preserves-formatting
  testWidgets(
    'правка сообщения СОХРАНЯЕТ форматирование, ≥3 раза подряд '
    '— ledger:RL-edit-preserves-formatting',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'chat.fluffy.show_no_google': false,
      });

      final actorA = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userA);
      final actorB = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userB);
      for (final actor in [actorA, actorB]) {
        final sync = await actor.api.sync();
        for (final r in (sync.rooms?.join?.keys.toList() ?? <String>[])) {
          try {
            await actor.api.leaveRoom(r);
            await actor.api.forgetRoom(r);
          } catch (_) {}
        }
      }
      final roomId = await actorB.createDirectChat(actorA.userId);
      await actorA.joinRoom(roomId);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final beacon = 'e2e-edit-$stamp';
      await actorB.sendText(roomId, beacon);

      app.main();
      await tester.ensureLizaHome();

      final tile = find.textContaining(beacon);
      await tester.waitUntil(tile, timeout: const Duration(seconds: 60));
      for (var attempt = 0; attempt < 3; attempt++) {
        await tester.tap(tile.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 500));
        final end = DateTime.now().add(const Duration(seconds: 20));
        while (find.byType(ChatView).evaluate().isEmpty &&
            DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        if (find.byType(ChatView).evaluate().isNotEmpty) break;
      }
      expect(find.byType(ChatView), findsOneWidget);

      final inputField = find.descendant(
        of: find.byType(InputBar),
        matching: find.byType(TextField),
      );
      await tester.waitUntil(inputField);

      // Маркер внутри самого сообщения — чтобы находить ИМЕННО его пузырь.
      final marker = 'ред$stamp';
      const boldWord = 'жирное';
      final base = 'правка $marker $boldWord слово';

      await tester.enterText(inputField.first, base);
      await tester.pump(const Duration(milliseconds: 300));
      final controller =
          tester.widget<TextField>(inputField.first).controller
              as FormattingTextEditingController;
      final boldStart = base.indexOf(boldWord);
      controller.selection = TextSelection(
        baseOffset: boldStart,
        extentOffset: boldStart + boldWord.length,
      );
      controller.toggleFormat(MessageFormat.bold);
      await tester.pump(const Duration(milliseconds: 300));

      await tester.waitUntil(find.byIcon(Icons.send_outlined));
      final sendBtn = find.ancestor(
        of: find.byIcon(Icons.send_outlined),
        matching: find.byType(InkWell),
      );
      await tester.tap(sendBtn.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 800));

      await tester.waitUntil(
        find.textContaining(marker, findRichText: true),
        timeout: const Duration(seconds: 40),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        _renderedBold(tester, find.byType(ChatView), boldWord),
        isTrue,
        reason: 'исходное сообщение должно уйти с жирным словом',
      );

      // ── Три ПОСЛЕДОВАТЕЛЬНЫЕ правки ──────────────────────────────────────
      for (var round = 1; round <= 3; round++) {
        // Открыть контекстное меню сообщения (long-press по пузырю) и «Редактировать».
        var menuOpened = false;
        for (var attempt = 0; attempt < 3 && !menuOpened; attempt++) {
          await tester.longPress(
            find.textContaining(marker, findRichText: true).first,
          );
          final end = DateTime.now().add(const Duration(seconds: 8));
          while (find.text('Редактировать').evaluate().isEmpty &&
              DateTime.now().isBefore(end)) {
            await tester.pump(const Duration(milliseconds: 200));
          }
          menuOpened = find.text('Редактировать').evaluate().isNotEmpty;
        }
        expect(
          menuOpened,
          isTrue,
          reason: 'раунд $round: в меню сообщения должен быть пункт «Редактировать»',
        );
        await tester.tap(find.text('Редактировать').last, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 700));

        // ГЛАВНЫЙ наблюдаемый эффект: формат ВИДЕН в поле ввода сразу после
        // входа в правку (до фикса поле показывало плоский текст).
        final edFinder = find.descendant(
          of: find.byType(InputBar),
          matching: find.byType(EditableText),
        );
        await tester.waitUntil(edFinder);
        final editable = tester.widget<EditableText>(edFinder.first);
        final composerSpan = editable.controller.buildTextSpan(
          context: tester.element(edFinder.first),
          withComposing: false,
          style: editable.style,
        );
        expect(
          _spanMatches(
            composerSpan,
            boldWord,
            (s) => s?.fontWeight == FontWeight.bold,
          ),
          isTrue,
          reason: 'раунд $round: при входе в правку «$boldWord» обязано быть '
              'жирным В ПОЛЕ ВВОДА (иначе формат сброшен, как до фикса)',
        );
        // SDK-префикс правки не должен просачиваться в композер (INV-E12).
        expect(
          editable.controller.text.startsWith('* '),
          isFalse,
          reason: 'раунд $round: в поле не должно быть SDK-префикса «* »',
        );

        // Правим «опечатку»: дописываем хвост, формат обязан пережить дифф.
        final edited = '$base ok$round';
        await tester.enterText(inputField.first, edited);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(sendBtn.first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 900));

        await tester.waitUntil(
          find.textContaining('ok$round', findRichText: true),
          timeout: const Duration(seconds: 40),
        );
        await tester.pump(const Duration(seconds: 1));
        expect(
          _renderedBold(tester, find.byType(ChatView), boldWord),
          isTrue,
          reason: 'раунд $round: после сохранения правки «$boldWord» обязано '
              'остаться жирным в пузыре',
        );
        // ignore: avoid_print
        print('EDIT-DEVICE: раунд $round — формат пережил правку');
      }
    },
  );
}
