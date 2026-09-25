// ledger:RL-about-screen-legal
// AC:RL-about-screen-legal/1 AC:RL-about-screen-legal/3 AC:RL-about-screen-legal/4
// AC:RL-about-screen-legal/5 AC:RL-about-screen-legal/6 AC:RL-about-screen-legal/7
// AC:RL-about-screen-legal/8 AC:RL-about-screen-legal/10 AC:RL-about-screen-legal/11
// AC:RL-about-screen-legal/12
//
// Экран «О приложении» (сессия 2026-09-17): доступен всем, ведёт на собственный
// экран, несёт юр-документы + исходники (монорепо Liza, редакция 2026-09-23) +
// AGPL v3, и НЕ несёт журналы/расширенные настройки/«Посмотреть лицензии».
//
// guard.render: source/l10n-ассерты — полный рендер SettingsView требует
// SettingsController + Matrix + GoRouter (тот же компромисс, что и в
// settings_privacy_security_labels_test.dart); визуальный AC-9 — manual, см. RL.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String settingsSrc;
  late String aboutViewSrc;
  late String aboutCtrlSrc;
  late Map<String, dynamic> enArb;
  late Map<String, dynamic> ruArb;

  setUpAll(() {
    settingsSrc = File(
      'lib/pages/settings/settings_view.dart',
    ).readAsStringSync();
    aboutViewSrc = File(
      'lib/pages/settings_about/settings_about_view.dart',
    ).readAsStringSync();
    aboutCtrlSrc = File(
      'lib/pages/settings_about/settings_about.dart',
    ).readAsStringSync();
    enArb =
        jsonDecode(File('lib/l10n/intl_en.arb').readAsStringSync())
            as Map<String, dynamic>;
    ruArb =
        jsonDecode(File('lib/l10n/intl_ru.arb').readAsStringSync())
            as Map<String, dynamic>;
  });

  /// Тело ListTile, внутри которого встречается [marker].
  ///
  /// Границу ищем по балансу скобок от `ListTile(`: наивный поиск `),\n`
  /// обрывается на первом же вложенном виджете (`Text(L10n...about),`).
  String tileContaining(String src, String marker) {
    final markerIdx = src.indexOf(marker);
    expect(markerIdx, isNot(-1), reason: 'в исходнике нет «$marker»');
    final start = src.lastIndexOf('ListTile(', markerIdx);
    expect(start, isNot(-1), reason: '«$marker» не внутри ListTile');
    var depth = 0;
    for (var i = src.indexOf('(', start); i < src.length; i++) {
      if (src[i] == '(') depth++;
      if (src[i] == ')') {
        depth--;
        if (depth == 0) return src.substring(start, i + 1);
      }
    }
    fail('не найдена закрывающая скобка ListTile для «$marker»');
  }

  // AC-1: пункт доступен всем и ведёт на свой экран.
  // AC:RL-about-screen-legal/1
  test('AC-1: «О проекте» без IfDeveloper и ведёт на /rooms/settings/about', () {
    final tile = tileContaining(settingsSrc, "L10n.of(context).about)");
    expect(
      tile.contains("context.go('/rooms/settings/about')"),
      isTrue,
      reason: 'пункт должен вести на собственный экран',
    );
    expect(
      tile.contains('PlatformInfos.showDialog'),
      isFalse,
      reason: 'системный showAboutDialog навязывает «Посмотреть лицензии»',
    );
    // IfDeveloper обёртывает пункт, если стоит непосредственно перед ListTile.
    final tileIdx = settingsSrc.indexOf(tile);
    final before = settingsSrc.substring(tileIdx - 220, tileIdx);
    expect(
      before.contains('IfDeveloper('),
      isFalse,
      reason: 'пункт «О проекте» должен быть виден всем пользователям',
    );
  });

  // AC-3: оба юр-документа на экране и только через AppConfig.
  // AC:RL-about-screen-legal/3
  test('AC-3: экран несёт privacyPolicy и termsOfUse через AppConfig', () {
    expect(aboutViewSrc.contains('l10n.privacyPolicy'), isTrue);
    expect(aboutViewSrc.contains('l10n.termsOfUse'), isTrue);
    expect(aboutViewSrc.contains('AppConfig.privacyUrl'), isTrue);
    expect(aboutViewSrc.contains('AppConfig.termsUrl'), isTrue);
    // Свой URL на экране = разъезд адресов (дефект LABA-2525).
    expect(
      RegExp(r"Uri\.parse\(\s*'https").hasMatch(aboutViewSrc),
      isFalse,
      reason: 'адреса документов берём только из AppConfig',
    );
  });

  // AC-4: исходники — один публичный монорепозиторий (редакция 2026-09-23).
  // Цель ссылки на РЕАЛЬНОМ виджете проверяет settings_about_render_test.dart;
  // здесь — единый источник адреса в AppConfig.
  // AC:RL-about-screen-legal/4 AC:RL-about-screen-legal/12
  test('AC-4/AC-12: исходники — только монорепо Liza, без голых форков', () {
    final appConfigSrc = File('lib/config/app_config.dart').readAsStringSync();
    expect(
      appConfigSrc.contains("'https://github.com/Liza-App-Digital/Liza'"),
      isTrue,
    );
    expect(aboutViewSrc.contains('AppConfig.lizaSourceUrl'), isTrue);
    for (final fork in [
      'Liza-App-Digital/fluffychat',
      'Liza-App-Digital/synapse',
    ]) {
      expect(appConfigSrc.contains(fork), isFalse, reason: 'форк $fork');
      expect(aboutViewSrc.contains(fork), isFalse, reason: 'форк $fork');
    }
  });

  // AC-5: лицензия AGPL v3 названа и привязана к FluffyChat, Matrix, Synapse,
  // Sygnal — в обеих локализациях (квантор ∀ по {ru, en}). AC-14: без точки
  // в конце (требование 2026-09-25, «не наш стиль»).
  // AC:RL-about-screen-legal/5 AC:RL-about-screen-legal/14
  test('AC-5: AGPL v3 относится к FluffyChat, Matrix, Synapse и Sygnal', () {
    expect(aboutViewSrc.contains('l10n.aboutLicenseNotice'), isTrue);
    for (final entry in {'en': enArb, 'ru': ruArb}.entries) {
      final notice = entry.value['aboutLicenseNotice'] as String;
      expect(
        notice.contains('AGPL'),
        isTrue,
        reason: '${entry.key}: лицензия должна называться AGPL (не APGL)',
      );
      for (final component in ['FluffyChat', 'Matrix', 'Synapse', 'Sygnal']) {
        expect(
          notice.contains(component),
          isTrue,
          reason: '${entry.key}: лицензия относится к $component',
        );
      }
      expect(
        notice.trimRight().endsWith('.'),
        isFalse,
        reason: '${entry.key}: текст лицензии без точки в конце',
      );
    }
  });

  // AC-6: трёх диагностических пунктов на экране нет (∀ по трём).
  // AC:RL-about-screen-legal/6
  test('AC-6: нет журналов, расширенных настроек и «Посмотреть лицензии»', () {
    final src = aboutViewSrc + aboutCtrlSrc;
    // Комментарии объясняют, ПОЧЕМУ этого нет, — исключаем их из проверки.
    final code = src
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    for (final forbidden in [
      'appLogs',
      'advancedConfigs',
      'showAboutDialog',
      'LicensePage',
      "context.go('/logs')",
      "context.go('/configs')",
    ]) {
      expect(
        code.contains(forbidden),
        isFalse,
        reason: 'на экране «О проекте» не должно быть «$forbidden»',
      );
    }
  });

  // AC-7: каждая внешняя ссылка помечена open_in_new.
  // AC:RL-about-screen-legal/7
  test('AC-7: у всех уводящих в браузер пунктов есть Icons.open_in_new', () {
    final launchCount = RegExp(r'launchUrl\(').allMatches(aboutViewSrc).length;
    expect(
      launchCount,
      greaterThan(0),
      reason: 'на экране есть внешние ссылки',
    );
    expect(
      aboutViewSrc.contains('Icons.open_in_new'),
      isTrue,
      reason: 'внешние пункты обязаны предупреждать иконкой open_in_new',
    );
    // Все внешние пункты идут через один _ExternalTile, который несёт иконку.
    final tile = aboutViewSrc.substring(aboutViewSrc.indexOf('_ExternalTile'));
    expect(tile.contains('Icons.open_in_new'), isTrue);
  });

  // AC-8: ключи есть в ОБЕИХ локализациях, кириллицы в коде экрана нет.
  // AC:RL-about-screen-legal/8
  test('AC-8: новые ключи в ru+en, без хардкода кириллицы в коде', () {
    for (final key in [
      'termsOfUse',
      'aboutSourceCodeLiza',
      'aboutLicenseNotice',
    ]) {
      expect(enArb.containsKey(key), isTrue, reason: 'intl_en.arb: нет $key');
      expect(
        ruArb.containsKey(key),
        isTrue,
        reason: 'intl_ru.arb: нет $key — русский UI молча покажет английский',
      );
    }
    // Ключи двух форков удалены вместе со ссылками (2026-09-23).
    for (final gone in [
      'aboutSourceCodeFluffyChat',
      'aboutSourceCodeSynapse',
    ]) {
      expect(enArb.containsKey(gone), isFalse, reason: 'intl_en.arb: $gone');
      expect(ruArb.containsKey(gone), isFalse, reason: 'intl_ru.arb: $gone');
    }
    final code = aboutViewSrc
        .split('\n')
        .where(
          (l) =>
              !l.trimLeft().startsWith('//') && !l.trimLeft().startsWith('///'),
        )
        .join('\n');
    expect(
      RegExp('[А-Яа-яЁё]').hasMatch(code),
      isFalse,
      reason: 'UI-строки только через L10n, не хардкодом',
    );
  });

  // AC-10: пункт называется «О приложении».
  // AC:RL-about-screen-legal/10
  test('AC-10: русская строка about — «О приложении»', () {
    expect(ruArb['about'], 'О приложении');
  });

  // AC-11: версия + номер сборки, один источник на все пять платформ.
  // AC:RL-about-screen-legal/11
  test(
    'AC-11: экран показывает номер сборки из pubspec на всех платформах',
    () {
      // Номер приходит из PackageInfo.buildNumber — единственного источника,
      // который на web/ios/macos/android/windows наполняется из
      // `version: X.Y.Z+NNNN` в pubspec.yaml силами самого Flutter.
      final platformInfosSrc = File(
        'lib/utils/platform_infos.dart',
      ).readAsStringSync();
      expect(
        RegExp(r'getBuildNumber\(\)\s*async').hasMatch(platformInfosSrc),
        isTrue,
        reason: 'номер сборки берём централизованно из PlatformInfos',
      );
      expect(
        platformInfosSrc.contains('PackageInfo.fromPlatform()).buildNumber'),
        isTrue,
        reason: 'источник номера — PackageInfo, одинаковый на всех платформах',
      );
      // Платформо-специфичных веток быть не должно: они и есть способ потерять
      // номер на одной из пяти платформ.
      final getBuildNumberBody = platformInfosSrc.substring(
        platformInfosSrc.indexOf('getBuildNumber'),
      );
      for (final branch in ['isWeb', 'isWindows', 'isAndroid', 'isIOS']) {
        expect(
          getBuildNumberBody.split('}').first.contains(branch),
          isFalse,
          reason: 'getBuildNumber не должен ветвиться по платформе ($branch)',
        );
      }

      expect(aboutCtrlSrc.contains('PlatformInfos.getBuildNumber()'), isTrue);
      expect(
        aboutViewSrc.contains('l10n.versionWithBuildNumber('),
        isTrue,
        reason: 'экран обязан показывать номер сборки рядом с версией',
      );
      // Деградация: пустой номер → одна версия, а не «Версия: 2.4.0 ()».
      expect(
        aboutViewSrc.contains('controller.buildNumber.isEmpty'),
        isTrue,
        reason: 'при недоступном номере показываем версию без пустых скобок',
      );

      for (final arb in {'en': enArb, 'ru': ruArb}.entries) {
        final value = arb.value['versionWithBuildNumber'] as String?;
        expect(
          value,
          isNotNull,
          reason: '${arb.key}: нет ключа versionWithBuildNumber',
        );
        expect(
          value!.contains('{version}') && value.contains('{buildNumber}'),
          isTrue,
          reason: '${arb.key}: строка обязана нести обе подстановки',
        );
      }

      // Номер в pubspec задан — иначе показывать нечего ни на одной платформе.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        RegExp(
          r'^version:\s*\d+\.\d+\.\d+\+\d+',
          multiLine: true,
        ).hasMatch(pubspec),
        isTrue,
        reason: 'pubspec.yaml должен нести version: X.Y.Z+NNNN',
      );
    },
  );
}
