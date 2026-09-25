// ledger:RL-about-screen-legal
// AC:RL-about-screen-legal/4 AC:RL-about-screen-legal/5
// AC:RL-about-screen-legal/10 AC:RL-about-screen-legal/11
// AC:RL-about-screen-legal/12 AC:RL-about-screen-legal/13
//
// Рендер-страж экрана «О приложении» (сессия 2026-09-17): проверяет то, что
// пользователь ВИДИТ на РЕАЛЬНОМ `SettingsAboutView` — заголовок после
// переименования и строку версии с номером сборки (включая деградацию, когда
// номер недоступен).
//
// Редакция 2026-09-23 (OpenSpec public-agpl-mirror): ссылки на исходники
// проверяются ТАПОМ по реальным пунктам экрана с перехватом `launchUrl` — цель
// берётся из того, что реально уходит в браузер: ровно одна ссылка на монорепо
// Liza, голых форков fluffychat/synapse нет; текст лицензии называет FluffyChat,
// Synapse и Sygnal; каждый внешний пункт помечен `open_in_new`.
//
// guard.render: real-widget — в отличие от source-ассертов соседнего
// settings_about_screen_test.dart, здесь рендерится прод-виджет: подмена
// `versionWithBuildNumber` на `versionWithNumber` или возврат «О проекте»
// роняет именно этот тест.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/settings_about/settings_about.dart';
import 'package:liza/pages/settings_about/settings_about_view.dart';

/// Контроллер с заранее заданными версией и номером сборки: сам экран берёт их
/// из `PackageInfo`, которого в host-тесте нет.
class _StubController extends SettingsAboutController {
  _StubController(String version, String buildNumber) {
    this.version = version;
    this.buildNumber = buildNumber;
  }
}

/// Перехватывает `launchUrl`: цель ссылки проверяем по тому, что РЕАЛЬНО уходит
/// в браузер при тапе, а не по исходнику.
class _FakeUrlLauncher extends UrlLauncherPlatform
    with MockPlatformInterfaceMixin {
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launched.add(url);
    return true;
  }

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

const _lizaSource = 'https://github.com/Liza-App-Digital/Liza';

/// Тапает каждый кликабельный пункт экрана и возвращает, куда он увёл.
Future<List<String>> _tapAllLinks(
  WidgetTester tester,
  _FakeUrlLauncher launcher,
) async {
  final tappable = find.byWidgetPredicate(
    (w) => w is ListTile && w.onTap != null,
  );
  final count = tappable.evaluate().length;
  for (var i = 0; i < count; i++) {
    await tester.ensureVisible(tappable.at(i));
    await tester.tap(tappable.at(i));
    await tester.pumpAndSettle();
  }
  return launcher.launched;
}

Widget _wrap(SettingsAboutController controller, Locale locale) => MaterialApp(
  locale: locale,
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: SettingsAboutView(controller),
);

void main() {
  testWidgets('AC-10: заголовок экрана — «О приложении»', (tester) async {
    await tester.pumpWidget(
      _wrap(_StubController('2.4.0', '3762'), const Locale('ru')),
    );
    await tester.pumpAndSettle();

    expect(find.text('О приложении'), findsOneWidget);
    expect(find.text('О проекте'), findsNothing);
  });

  testWidgets('AC-11: показан номер сборки рядом с версией', (tester) async {
    await tester.pumpWidget(
      _wrap(_StubController('2.4.0', '3762'), const Locale('ru')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Версия: 2.4.0 (3762)'), findsOneWidget);
  });

  // EN-рендер проверен отдельным прогоном (даёт «Version: 2.4.0 (3762)»), но
  // в общем файле не воспроизводится: делегат локализаций кэшируется между
  // testWidgets, и вторая локаль не подхватывается. Сторона EN закрыта
  // ассертом на `intl_en.arb` в settings_about_screen_test.dart (AC-11).

  testWidgets('AC-11: без номера сборки — версия без пустых скобок', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(_StubController('2.4.0', ''), const Locale('ru')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Версия: 2.4.0'), findsOneWidget);
    expect(find.textContaining('()'), findsNothing);
  });

  group('исходники и лицензия (редакция 2026-09-23)', () {
    late _FakeUrlLauncher launcher;
    late UrlLauncherPlatform original;

    setUp(() {
      original = UrlLauncherPlatform.instance;
      launcher = _FakeUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
    });

    tearDown(() => UrlLauncherPlatform.instance = original);

    // AC:RL-about-screen-legal/4
    testWidgets('AC-4: ровно одна ссылка на исходники — монорепо Liza', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_StubController('2.4.0', '3762'), const Locale('ru')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Исходный код Liza'), findsOneWidget);
      final launched = await _tapAllLinks(tester, launcher);
      final sourceLinks = launched
          .where((u) => Uri.parse(u).host == 'github.com')
          .toList();
      expect(sourceLinks, [_lizaSource]);
    });

    // AC:RL-about-screen-legal/12
    testWidgets('AC-12: нет ссылок на голые форки fluffychat/synapse', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_StubController('2.4.0', '3762'), const Locale('ru')),
      );
      await tester.pumpAndSettle();

      final launched = await _tapAllLinks(tester, launcher);
      for (final fork in ['/fluffychat', '/synapse']) {
        expect(
          launched.where((u) => u.toLowerCase().contains(fork)),
          isEmpty,
          reason: 'форк $fork не является исходником Liza',
        );
      }
      expect(find.text('Исходный код FluffyChat'), findsNothing);
      expect(find.text('Исходный код Synapse'), findsNothing);
      // Прочие цели не изменились: политика и условия — как были.
      expect(launched, [
        'https://liza.cifrapro.kz/pp',
        'https://liza.cifrapro.kz/terms',
        _lizaSource,
      ]);
    });

    // AC:RL-about-screen-legal/5
    testWidgets(
      'AC-5: текст лицензии — AGPL для FluffyChat, Matrix, Synapse, Sygnal',
      (tester) async {
        await tester.pumpWidget(
          _wrap(_StubController('2.4.0', '3762'), const Locale('ru')),
        );
        await tester.pumpAndSettle();

        final notice = find.textContaining('AGPL');
        expect(notice, findsOneWidget);
        final text = tester.widget<Text>(notice).data!;
        for (final component in ['FluffyChat', 'Matrix', 'Synapse', 'Sygnal']) {
          expect(text, contains(component));
        }
      },
    );

    // AC:RL-about-screen-legal/13
    testWidgets('AC-13: каждый уводящий в браузер пункт помечен open_in_new', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(_StubController('2.4.0', '3762'), const Locale('ru')),
      );
      await tester.pumpAndSettle();

      final tappable = find.byWidgetPredicate(
        (w) => w is ListTile && w.onTap != null,
      );
      expect(tappable, findsNWidgets(3));
      for (final tile in tappable.evaluate()) {
        final trailing = (tile.widget as ListTile).trailing;
        expect(
          trailing is Icon && trailing.icon == Icons.open_in_new_outlined,
          isTrue,
          reason: 'внешняя ссылка обязана нести иконку open_in_new',
        );
      }
    });
  });
}
