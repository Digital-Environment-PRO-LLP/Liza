import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/homeserver_picker/login_entry_actions.dart';

/// Первый экран должен помещаться в низкую карточку десктопного режима.
///
/// Ловушка, ради которой этот тест: содержимое живёт в `ConstrainedBox`
/// с `maxHeight`, а раскладка использует `Spacer` внутри `IntrinsicHeight`.
/// Spacer забирает весь остаток и выталкивает нижний блок за край карточки —
/// юр-сноска молча обрезалась, при этом ни один обычный виджет-тест этого не
/// замечал (они рендерят блок отдельно, без ограничения по высоте).
void main() {
  Widget wrapInCard(Widget child, {required double maxHeight}) => MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 480, maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('юр-сноска видна целиком в карточке 720', (tester) async {
    await tester.pumpWidget(
      wrapInCard(
        LoginEntryActions(
          isLoading: false,
          onRegister: () {},
          onSignIn: () {},
          onSubmitPhone: (_) {},
        ),
        maxHeight: 720,
      ),
    );
    await tester.pumpAndSettle();

    final notice = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          w.textSpan != null &&
          w.textSpan!.toPlainText().contains('политику конфиденциальности'),
    );
    expect(notice, findsOneWidget);

    // Нижняя граница сноски не должна уезжать за пределы экрана.
    final box = tester.getRect(notice);
    final screen = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(
      box.bottom,
      lessThanOrEqualTo(screen),
      reason: 'юр-сноска обрезана снизу: ${box.bottom} > $screen',
    );
  });

  testWidgets('переполнения раскладки нет', (tester) async {
    await tester.pumpWidget(
      wrapInCard(
        LoginEntryActions(
          isLoading: false,
          onRegister: () {},
          onSignIn: () {},
          onSubmitPhone: (_) {},
        ),
        maxHeight: 720,
      ),
    );
    await tester.pumpAndSettle();

    // RenderFlex overflow приходит через FlutterError — если он был,
    // takeException() его отдаст.
    expect(tester.takeException(), isNull);
  });

  testWidgets('низкое окно: содержимое скроллится, а не режется', (
    tester,
  ) async {
    // Карточка не может быть выше экрана: на ноутбуке с невысоким окном
    // потолок 800 не спасёт — содержимое обязано доезжать скроллом.
    await tester.pumpWidget(
      wrapInCard(
        LoginEntryActions(
          isLoading: false,
          onRegister: () {},
          onSignIn: () {},
          onSubmitPhone: (_) {},
        ),
        maxHeight: 420,
      ),
    );
    await tester.pumpAndSettle();

    // Переполнения быть не должно — вместо него скролл.
    expect(tester.takeException(), isNull);

    final scrollable = find.byType(Scrollable);
    expect(scrollable, findsWidgets);

    // Сноска доезжает прокруткой.
    final notice = find.byWidgetPredicate(
      (w) =>
          w is Text &&
          w.textSpan != null &&
          w.textSpan!.toPlainText().contains('политику конфиденциальности'),
    );
    await tester.scrollUntilVisible(notice, 100, scrollable: scrollable.first);
    expect(notice, findsOneWidget);
  });
}
