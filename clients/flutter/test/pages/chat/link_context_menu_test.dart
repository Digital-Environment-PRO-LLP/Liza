import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/linkified_span.dart';

// Страж реестра регрессии: ledger:RL-link-context-menu (см. tests/registry/).
// guard.render:real-widget
//
// LABA-1965: правый клик (desktop/web) и долгое нажатие (mobile) ПО ССЫЛКЕ
// показывают меню ссылки («Открыть» / «Копировать ссылку»), а НЕ контекстное
// меню всего сообщения. Тап по ссылке по-прежнему открывает её; протяжка
// (скролл) поверх ссылки не открывает меню.
//
// Рендерим РЕАЛЬНЫЕ спаны через [buildLinkifiedSpans] внутри `Text.rich`,
// обёрнутого в GestureDetector-«пузырь» (как в message.dart), и проверяем, что
// жест по ссылке НЕ доходит до пузыря (анти-дубль).

const _url = 'https://example.com/path';
final _linkStyle = const TextStyle(color: Colors.blue, fontSize: 16);

/// Хост: «пузырь» с onSecondaryTapDown/onLongPressStart (как в реальном
/// сообщении) оборачивает `Text.rich` со ссылкой. Слева — пустая зона, чтобы
/// проверить, что жест ВНЕ ссылки доходит до пузыря.
Widget _host({
  required List<GestureRecognizer> pool,
  required void Function() onBubbleMenu,
  required void Function(String) onOpen,
  required bool touch,
}) {
  return MaterialApp(
    locale: const Locale('ru'),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    // Меню как шторка (ListTile) — детерминированно ищем по тексту.
    theme: ThemeData(platform: TargetPlatform.android),
    home: Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => GestureDetector(
            onSecondaryTapDown: (_) => onBubbleMenu(),
            onLongPressStart: (_) => onBubbleMenu(),
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 80, height: 40, key: Key('empty')),
                Text.rich(
                  key: const Key('linkText'),
                  TextSpan(
                    children: buildLinkifiedSpans(
                      context: context,
                      text: _url,
                      textStyle: const TextStyle(color: Colors.black),
                      linkStyle: _linkStyle,
                      onOpen: (el) => onOpen(el.url),
                      recognizerPool: pool,
                      touchLongPress: touch,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _rightClick(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryButton,
  );
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _longPress(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(tester.getCenter(finder));
  await tester.pump(const Duration(milliseconds: 600));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  Finder linkText() => find.byKey(const Key('linkText'));

  testWidgets(
    'desktop правый клик по ссылке → меню ссылки, пузырь НЕ вызван — ledger:RL-link-context-menu AC:RL-link-context-menu/1',
    (tester) async {
      final pool = <GestureRecognizer>[];
      var bubble = 0;
      final opened = <String>[];
      await tester.pumpWidget(
        _host(
          pool: pool,
          onBubbleMenu: () => bubble++,
          onOpen: opened.add,
          touch: false,
        ),
      );
      await tester.pumpAndSettle();

      await _rightClick(tester, linkText());

      expect(find.text('Копировать ссылку'), findsOneWidget);
      expect(find.text('Открыть'), findsOneWidget);
      expect(bubble, 0, reason: 'меню пузыря НЕ должно открыться (анти-дубль)');
      expect(opened, isEmpty, reason: 'правый клик не открывает ссылку');
      disposeRecognizers(pool);
    },
  );

  testWidgets(
    'mobile долгое нажатие по ссылке → меню ссылки, пузырь НЕ вызван — AC:RL-link-context-menu/2',
    (tester) async {
      final pool = <GestureRecognizer>[];
      var bubble = 0;
      await tester.pumpWidget(
        _host(
          pool: pool,
          onBubbleMenu: () => bubble++,
          onOpen: (_) {},
          touch: true,
        ),
      );
      await tester.pumpAndSettle();

      await _longPress(tester, linkText());

      expect(find.text('Копировать ссылку'), findsOneWidget);
      expect(bubble, 0, reason: 'long-press по ссылке не должен дать меню сообщения');
      disposeRecognizers(pool);
    },
  );

  testWidgets(
    'копирование кладёт именно URL — AC:RL-link-context-menu/3',
    (tester) async {
      final pool = <GestureRecognizer>[];
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );

      await tester.pumpWidget(
        _host(
          pool: pool,
          onBubbleMenu: () {},
          onOpen: (_) {},
          touch: false,
        ),
      );
      await tester.pumpAndSettle();

      await _rightClick(tester, linkText());
      await tester.tap(find.text('Копировать ссылку'));
      await tester.pumpAndSettle();

      expect(copied, _url);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      disposeRecognizers(pool);
    },
  );

  testWidgets('тап по ссылке открывает её (desktop) — AC:RL-link-context-menu/4', (
    tester,
  ) async {
    final pool = <GestureRecognizer>[];
    final opened = <String>[];
    await tester.pumpWidget(
      _host(
        pool: pool,
        onBubbleMenu: () {},
        onOpen: opened.add,
        touch: false,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(linkText());
    await tester.pumpAndSettle();

    expect(opened, [_url]);
    expect(find.text('Копировать ссылку'), findsNothing);
    disposeRecognizers(pool);
  });

  testWidgets('тап по ссылке открывает её (mobile combined recognizer)', (
    tester,
  ) async {
    final pool = <GestureRecognizer>[];
    final opened = <String>[];
    await tester.pumpWidget(
      _host(
        pool: pool,
        onBubbleMenu: () {},
        onOpen: opened.add,
        touch: true,
      ),
    );
    await tester.pumpAndSettle();

    // Быстрый тап (down+up до порога long-press) — открыть, без меню.
    await tester.tap(linkText());
    await tester.pumpAndSettle();

    expect(opened, [_url]);
    expect(find.text('Копировать ссылку'), findsNothing);
    disposeRecognizers(pool);
  });

  testWidgets('протяжка поверх ссылки (mobile) НЕ открывает меню и НЕ открывает ссылку', (
    tester,
  ) async {
    final pool = <GestureRecognizer>[];
    final opened = <String>[];
    await tester.pumpWidget(
      _host(
        pool: pool,
        onBubbleMenu: () {},
        onOpen: opened.add,
        touch: true,
      ),
    );
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(tester.getCenter(linkText()));
    await gesture.moveBy(const Offset(0, 60));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('Копировать ссылку'), findsNothing);
    expect(opened, isEmpty, reason: 'скролл поверх ссылки не открывает её');
    disposeRecognizers(pool);
  });

  testWidgets(
    'контроль: правый клик по ПУСТОЙ зоне пузыря → меню пузыря (не ссылки) — AC:RL-link-context-menu/6',
    (tester) async {
      final pool = <GestureRecognizer>[];
      var bubble = 0;
      await tester.pumpWidget(
        _host(
          pool: pool,
          onBubbleMenu: () => bubble++,
          onOpen: (_) {},
          touch: false,
        ),
      );
      await tester.pumpAndSettle();

      await _rightClick(tester, find.byKey(const Key('empty')));

      expect(bubble, 1, reason: 'вне ссылки правый клик доходит до пузыря');
      expect(find.text('Копировать ссылку'), findsNothing);
      disposeRecognizers(pool);
    },
  );

  // AC-5 (HTML `<a>` через HtmlMessage) авто-тестом НЕ покрыт намеренно:
  // HtmlMessage требует Room → живой Matrix-клиент (prepareTestClient), а он в
  // widget-тесте роняет teardown («Cannot close sink while adding stream») и
  // делает тест флакающим/зависающим — недопустимо для pre-push/CI. `<a>`-путь
  // делит ВСЮ логику меню и арены с плейн-URL (AC-1..4, тот же
  // `showLinkContextMenu`); уникальна лишь тернарная проводка InkWell
  // (`onSecondaryTapDown`/`onLongPress`) в html_message.dart — она под
  // анализатором + manual Android/desktop-прогоном (см. RL AC-5).
}
