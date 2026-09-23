import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/secure_screen.dart';

// Спек 2026-07-30 §3.1 (риск): FLAG_SECURE обязан сниматься при уходе с
// экрана. Залипший флаг блокирует скриншоты во ВСЁМ приложении.
void main() {
  setUp(debugResetSecureScreen);

  testWidgets('защита включается на экране и снимается при уходе', (
    tester,
  ) async {
    final calls = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SecureScreenGuard(
          enabled: true,
          setSecure: (v) async => calls.add(v),
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, [true], reason: 'защита не включилась');

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(calls, [true, false], reason: 'защита не снялась при уходе');
  });

  testWidgets('при enabled=false защита не включается', (tester) async {
    final calls = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SecureScreenGuard(
          enabled: false,
          setSecure: (v) async => calls.add(v),
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
  });

  testWidgets('смена enabled на лету включает и снимает защиту', (
    tester,
  ) async {
    final calls = <bool>[];

    Future<void> pumpWith(bool enabled) => tester.pumpWidget(
      MaterialApp(
        home: SecureScreenGuard(
          enabled: enabled,
          setSecure: (v) async => calls.add(v),
          child: const SizedBox(),
        ),
      ),
    );

    await pumpWith(false);
    await tester.pumpAndSettle();
    expect(calls, isEmpty);

    await pumpWith(true);
    await tester.pumpAndSettle();
    expect(calls, [true]);

    await pumpWith(false);
    await tester.pumpAndSettle();
    expect(calls, [true, false]);
  });

  // Негативный сценарий «два экрана канала в стеке»: лента канала + поверх
  // неё просмотрщик медиа. Закрытие ВЕРХНЕГО экрана не должно снимать флаг,
  // пока нижний ещё в дереве.
  testWidgets('вложенные стражи: флаг снимается только с последним', (
    tester,
  ) async {
    final calls = <bool>[];
    Future<void> setSecure(bool v) async => calls.add(v);

    Widget tree({required bool withViewer}) => MaterialApp(
      home: SecureScreenGuard(
        enabled: true,
        setSecure: setSecure,
        child: withViewer
            ? SecureScreenGuard(
                enabled: true,
                setSecure: setSecure,
                child: const SizedBox(),
              )
            : const SizedBox(),
      ),
    );

    await tester.pumpWidget(tree(withViewer: false));
    await tester.pumpAndSettle();
    expect(calls, [true]);

    // Открыли просмотрщик поверх ленты — платформу дёргать повторно незачем.
    await tester.pumpWidget(tree(withViewer: true));
    await tester.pumpAndSettle();
    expect(calls, [true], reason: 'повторное включение ушло на платформу');

    // Закрыли просмотрщик — лента ещё защищена, флаг снимать НЕЛЬЗЯ.
    await tester.pumpWidget(tree(withViewer: false));
    await tester.pumpAndSettle();
    expect(calls, [true], reason: 'флаг снялся, пока лента ещё на экране');

    // Ушли с ленты — теперь защиту снимаем.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(calls, [true, false], reason: 'флаг залип после ухода с ленты');
  });

  // Быстрое переключение «защищённый канал → обычный чат»: старый страж
  // умирает, новый не появляется — флаг обязан сняться.
  testWidgets('переход из защищённого канала в обычный чат снимает флаг', (
    tester,
  ) async {
    final calls = <bool>[];
    Future<void> setSecure(bool v) async => calls.add(v);

    await tester.pumpWidget(
      MaterialApp(
        home: SecureScreenGuard(
          key: const ValueKey('channel'),
          enabled: true,
          setSecure: setSecure,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      MaterialApp(
        home: SecureScreenGuard(
          key: const ValueKey('plain-chat'),
          enabled: false,
          setSecure: setSecure,
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, [true, false], reason: 'флаг залип в обычном чате');
  });

  // Сценарий C из отчёта Task 11: headless push-движок (FcmPushService)
  // может проглотить MissingPluginException, пока канал ещё не привязан к
  // MainActivity, — Dart-страж тогда думает, что защита включена, а
  // платформа флаг не получила. `resumed` обязан переутвердить состояние.
  testWidgets('resumed переутверждает защиту, если страж её держит', (
    tester,
  ) async {
    final calls = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SecureScreenGuard(
          enabled: true,
          setSecure: (v) async => calls.add(v),
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, [true]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(
      calls,
      [true, true],
      reason: 'resumed не переутвердил защиту повторным setSecure(true)',
    );
  });

  testWidgets('resumed не шлёт setSecure, если ни один страж защиту не держит', (
    tester,
  ) async {
    final calls = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: SecureScreenGuard(
          enabled: false,
          setSecure: (v) async => calls.add(v),
          child: const SizedBox(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(calls, isEmpty);
  });

  // Minor 3 из фикс-раунда: вложенные стражи не должны дублировать
  // setSecure(true) на один и тот же resumed — реассерт общий на процесс.
  testWidgets('resumed при вложенных стражах шлёт один реассерт, не два', (
    tester,
  ) async {
    final calls = <bool>[];
    Future<void> setSecure(bool v) async => calls.add(v);

    await tester.pumpWidget(
      MaterialApp(
        home: SecureScreenGuard(
          enabled: true,
          setSecure: setSecure,
          child: SecureScreenGuard(
            enabled: true,
            setSecure: setSecure,
            child: const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, [true]);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(
      calls,
      [true, true],
      reason: 'реассерт должен быть один на оба вложенных стража, не два',
    );
  });
}
