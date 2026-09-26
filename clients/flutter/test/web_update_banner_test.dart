// ledger:RL-web-update-reload
// AC:RL-web-update-reload/6 AC:RL-web-update-reload/7
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat_list/web_update_banner.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: const Locale('ru'),
    home: Scaffold(body: Column(children: [child])),
  );

  testWidgets('нет обновления — плашки нет', (tester) async {
    final available = ValueNotifier(false);
    await tester.pumpWidget(
      wrap(WebUpdateBanner(updateAvailable: available, reload: () {})),
    );
    await tester.pumpAndSettle();
    expect(find.text('Доступна новая версия Liza'), findsNothing);
    expect(find.text('Обновить'), findsNothing);
  });

  testWidgets('появляется, как только обновление обнаружено (ru)', (
    tester,
  ) async {
    final available = ValueNotifier(false);
    await tester.pumpWidget(
      wrap(WebUpdateBanner(updateAvailable: available, reload: () {})),
    );
    await tester.pumpAndSettle();
    available.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Доступна новая версия Liza'), findsOneWidget);
    expect(find.text('Обновить'), findsOneWidget);
  });

  test('строки баннера есть в en и ru', () {
    // Без ключа в ru Flutter молча подставит английский (CLAUDE.md).
    Map<String, dynamic> arb(String lang) =>
        jsonDecode(File('lib/l10n/intl_$lang.arb').readAsStringSync())
            as Map<String, dynamic>;
    final en = arb('en');
    final ru = arb('ru');
    expect(en['newVersionAvailable'], 'A new version of Liza is available');
    expect(en['webUpdateReload'], 'Update');
    expect(ru['newVersionAvailable'], 'Доступна новая версия Liza');
    expect(ru['webUpdateReload'], 'Обновить');
  });

  testWidgets('тап перезагружает ровно один раз, даже двойной', (tester) async {
    var reloads = 0;
    await tester.pumpWidget(
      wrap(
        WebUpdateBanner(
          updateAvailable: ValueNotifier(true),
          reload: () => reloads++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Обновить'));
    await tester.tap(find.text('Обновить'), warnIfMissed: false);
    await tester.pump();
    await tester.tap(find.text('Обновить'), warnIfMissed: false);
    await tester.pump();
    expect(reloads, 1);
  });
}
