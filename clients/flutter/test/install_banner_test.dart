// ledger:RL-web-install-banner
// AC:RL-web-install-banner/5 AC:RL-web-install-banner/6
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat_list/install_banner.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        locale: const Locale('ru'),
        home: Scaffold(body: Column(children: [child])),
      );

  setUp(InstallBannerDismissal.debugReset);

  testWidgets('плашка видна, когда есть ссылка установки', (tester) async {
    await tester.pumpWidget(
      wrap(const InstallBanner(installUrl: 'https://i/a', isWeb: true)),
    );
    // Загрузка локализации асинхронна (deferred lookupL10n) — без settle
    // текст ещё не подгружен на момент первого pump.
    await tester.pumpAndSettle();
    expect(find.text('Установить приложение Liza'), findsOneWidget);
  });

  testWidgets('без ссылки плашки нет', (tester) async {
    await tester.pumpWidget(
      wrap(const InstallBanner(installUrl: null, isWeb: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Установить приложение Liza'), findsNothing);
  });

  testWidgets('на нативной сборке плашки нет', (tester) async {
    await tester.pumpWidget(
      wrap(const InstallBanner(installUrl: 'https://i/a', isWeb: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Установить приложение Liza'), findsNothing);
  });

  testWidgets('крестик закрывает плашку', (tester) async {
    await tester.pumpWidget(
      wrap(const InstallBanner(installUrl: 'https://i/a', isWeb: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Установить приложение Liza'), findsNothing);
  });

  testWidgets('после перезапуска вкладки плашка снова видна', (tester) async {
    await tester.pumpWidget(
      wrap(const InstallBanner(installUrl: 'https://i/a', isWeb: true)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    // Новая вкладка = новый запуск приложения: состояние закрытия живёт только
    // в памяти вкладки и НЕ персистится.
    InstallBannerDismissal.debugReset();
    await tester.pumpWidget(
      wrap(const InstallBanner(installUrl: 'https://i/a', isWeb: true)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Установить приложение Liza'), findsOneWidget);
  });
}
