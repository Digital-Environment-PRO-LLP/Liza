// AC-4 витрины MCP: в НЕрусской локали блока примеров нет.
//
// ⚠️ ОТДЕЛЬНЫЙ файл не по прихоти: `l10n.yaml` → use-deferred-loading: true,
// и ВТОРАЯ локаль, поднятая в том же тест-файле, под fake-async не
// догружается — дерево остаётся пустым, а тест висит вечно (проверено:
// прогон упал по таймауту на 5-м кейсе). Один файл — одна локаль.
//
// До этого файла витрина MCP не была покрыта НИЧЕМ: её можно было сломать
// полностью (потерять бейдж, тумблер, переполнить строку) и получить зелёный
// прогон. Соседние тесты (`chat_settings_mcp_item_test`, `settings_routes_test`)
// стерегут только пункт меню и маршрут.
//
// Требование владельца (2026-09-10, дословно): «рядом с бейджиком "бесплатно"
// разместить кнопку "Подробнее" по клику на которую карточка будет раскрыаться
// и в ней будет более детальное описание возможностей данного mcp, но краткое,
// вместе с тем должен быть перечень тематик и пример команд».
//
// ledger:RL-mcp-showcase-details

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/settings_integrations/settings_integrations.dart';
import 'package:liza/widgets/matrix.dart';

import '../../utils/test_client.dart';

void main() {
  late Client client;
  late SharedPreferences store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    client = await prepareTestClient(loggedIn: true);
    // Фоновый sync держит таймер живым и роняет тест на «A Timer is still
    // pending even after the widget tree was disposed».
    client.backgroundSync = false;
    store = await SharedPreferences.getInstance();
  });

  tearDown(() async {
    await client.dispose(closeDatabase: true);
  });

  /// Шрифт Ahem рисует каждый глиф квадратом в кегль, поэтому длинные русские
  /// строки переполняют там, где реальный шрифт укладывается. Глушим ровно
  /// overflow: настоящую вёрстку меряет Ярус B (визуальный baseline), а не
  /// widget-ассерт — иначе ложный красный заглушат вместе с настоящим.
  void ignoreAhemOverflow() {
    final defaultOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('A RenderFlex overflowed')) {
        return;
      }
      defaultOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = defaultOnError);
  }

  Future<void> pumpScreen(WidgetTester tester, {Locale locale = const Locale('ru')}) async {
    ignoreAhemOverflow();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Matrix(
            clients: [client],
            store: store,
            child: const SettingsIntegrationsPage(),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        locale: locale,
        localizationsDelegates: const [
          L10n.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: L10n.supportedLocales,
        routerConfig: router,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  /// Matrix держит живой таймер; без разбора дерева тест падает на pending Timer.
  Future<void> teardownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
  }

  // AC:RL-mcp-showcase-details/4
  testWidgets('в английской локали блок примеров не рендерится', (tester) async {
    await pumpScreen(tester, locale: const Locale('en'));
    final en = (await tester.runAsync(
      () => L10n.delegate.load(const Locale('en')),
    ))!;

    await tester.tap(find.byKey(const Key('mcpDetailsBtn_vkusvill')));
    await tester.pumpAndSettle();

    // Проза переведена и видна…
    expect(find.text(en.settingsMcpTopics), findsOneWidget);
    // …а команды — нет: гейт `mcp_intent` на сервере кириллический, показать
    // англоязычному пользователю команду = пообещать неработающее.
    expect(find.text(en.settingsMcpExamples), findsNothing);
    expect(find.text(en.settingsMcpEx_vkusvill_milk), findsNothing);

    await teardownTree(tester);
  });
}
