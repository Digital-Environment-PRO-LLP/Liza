// ledger:RL-web-single-context-menu
// AC:RL-web-single-context-menu/4
//
// Заявка поддержки №41: на Web правый клик открывал наше меню и меню Chrome
// одновременно. Держится на одном вызове `disableContextMenu` при старте.
@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/browser_context_menu.dart';

void main() {
  test('на Web выключает браузерное меню ровно один раз', () {
    var calls = 0;
    configureBrowserContextMenu(
      isWeb: true,
      disable: () async => calls++,
    );
    expect(calls, 1);
  });

  test('вне Web не трогает меню (disableContextMenu там падает на assert)', () {
    var calls = 0;
    configureBrowserContextMenu(
      isWeb: false,
      disable: () async => calls++,
    );
    expect(calls, 0);
  });

  test('сбой выключения не роняет старт', () async {
    configureBrowserContextMenu(
      isWeb: true,
      disable: () async => throw StateError('channel'),
    );
    await Future<void>.delayed(Duration.zero);
  });

  test('main() выключает меню с kIsWeb до runApp', () {
    final main = File('lib/main.dart').readAsStringSync();
    final call = main.indexOf(
      RegExp(
        r'configureBrowserContextMenu\(\s*isWeb:\s*kIsWeb,\s*'
        r'disable:\s*BrowserContextMenu\.disableContextMenu,',
      ),
    );
    expect(call, isNonNegative, reason: 'вызов в main() пропал');
    expect(
      call,
      greaterThan(main.indexOf('WidgetsFlutterBinding.ensureInitialized()')),
    );
    expect(call, lessThan(main.indexOf('runApp(')));
  });

  test('никто в lib/ не включает браузерное меню обратно', () {
    final offenders = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('enableContextMenu'))
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty);
  });
}
