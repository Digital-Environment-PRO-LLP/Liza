import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/homeserver_picker/login_entry_actions.dart';

/// Экран входа на НЕВЫСОКОМ мониторе.
///
/// Проверяется на реальном блоке ввода ([LoginEntryActions]) — том самом,
/// что рисуется в приложении, а не на его копии: именно его нижняя часть
/// (кнопка «Продолжить» и юр-сноска) обрезалась на вьюпорте 600-700px.
void main() {
  Widget wrap(Widget child, {double density = 1.0}) => MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: child,
            ),
          ),
        ),
      );

  /// Высота блока ввода при заданной плотности.
  Future<double> heightAt(WidgetTester tester, double density) async {
    await tester.pumpWidget(
      wrap(
        LoginEntryActions(
          isLoading: false,
          onRegister: () {},
          onSignIn: () {},
          onSubmitPhone: (_) {},
          density: density,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getSize(find.byType(LoginEntryActions)).height;
  }

  tearDown(() => TestWidgetsFlutterBinding.instance.reset());

  testWidgets('низкая плотность реально ужимает блок ввода', (tester) async {
    await tester.binding.setSurfaceSize(const Size(480, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final spacious = await heightAt(tester, 1.0);
    final tight = await heightAt(tester, 0.5);

    expect(
      tight,
      lessThan(spacious),
      reason: 'при density < 1 отступы обязаны сжиматься',
    );
  });

  testWidgets('на вьюпорте 640px кнопка и юр-сноска целиком видимы', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(
        LoginEntryActions(
          isLoading: false,
          onRegister: () {},
          onSignIn: () {},
          onSubmitPhone: (_) {},
          density: 0.5,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Блок ввода целиком должен помещаться в вьюпорт вместе с логотипом и
    // описанием — на них по замерам уходит около половины высоты экрана.
    final height = tester.getSize(find.byType(LoginEntryActions)).height;
    expect(
      height,
      lessThan(400),
      reason: 'на низком экране блоку ввода остаётся меньше половины высоты',
    );

    expect(find.text('Продолжить'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('на просторном экране вид не ужимается (density = 1)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final spacious = await heightAt(tester, 1.0);
    // 288 — замер ПРЕЖНЕЙ вёрстки, записанный в комментарии
    // `login_scaffold.dart` («блок ввода один занимает 288»). При density
    // = 1 все отступы умножаются на единицу, поэтому высота обязана
    // совпасть с точностью до пикселя: большой экран не тронут.
    // AC:RL-login-phone-input-max-digits/10 — лимит цифр в поле телефона
    // не добавил ни счётчика, ни зарезервированного места (LABA-2524).
    expect(
      spacious,
      288.0,
      reason: 'на большом экране раскладка обязана остаться прежней',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('сжатие не роняет кнопку и поле ниже 48px (палец)', (
    tester,
  ) async {
    // Отступы ужимаются, но интерактивные элементы обязаны остаться
    // нажимаемыми: минимум Material — 48 логических пикселей.
    for (final density in const [1.0, 0.6, 0.45]) {
      await tester.binding.setSurfaceSize(const Size(480, 640));
      await heightAt(tester, density);

      expect(
        tester.getSize(find.byType(ElevatedButton)).height,
        greaterThanOrEqualTo(48.0),
        reason: 'кнопка «Продолжить» при density=$density',
      );
      expect(
        tester.getSize(find.byType(TextField)).height,
        greaterThanOrEqualTo(48.0),
        reason: 'поле телефона при density=$density',
      );
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('переполнения нет ни на одной из проверяемых высот', (
    tester,
  ) async {
    for (final size in const [
      Size(480, 560),
      Size(480, 640),
      Size(480, 700),
      Size(480, 900),
    ]) {
      await tester.binding.setSurfaceSize(size);
      final density = (size.height / 720).clamp(0.45, 1.0);
      await heightAt(tester, density);
      expect(
        tester.takeException(),
        isNull,
        reason: 'вьюпорт $size не должен давать overflow',
      );
    }
    await tester.binding.setSurfaceSize(null);
  });
}
