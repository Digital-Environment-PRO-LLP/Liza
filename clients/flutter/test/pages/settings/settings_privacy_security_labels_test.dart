// ledger:RL-settings-privacy-security-labels
// AC:RL-settings-privacy-security-labels/1 AC:RL-settings-privacy-security-labels/2
// AC:RL-settings-privacy-security-labels/3 AC:RL-settings-privacy-security-labels/4
// AC:RL-settings-privacy-security-labels/5 AC:RL-settings-privacy-security-labels/6
//
// Страж подписей пунктов настроек (LABA-2548): пункт, уводящий на внешний
// liza.ru/legal, называется «Политика конфиденциальности» и помечен иконкой
// open_in_new; пункт и экран внутренних настроек — «Приватность и безопасность».
// guard.render: source/l10n-ассерты — полный рендер SettingsView требует
// SettingsController + Matrix + GoRouter (тот же компромисс, что и в
// settings_invite_friends_test.dart); визуальный AC-7 — manual-остаток, см. RL.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String settingsSrc;
  late String securitySrc;
  late String ruArb;

  setUpAll(() {
    settingsSrc = File(
      'lib/pages/settings/settings_view.dart',
    ).readAsStringSync();
    securitySrc = File(
      'lib/pages/settings_security/settings_security_view.dart',
    ).readAsStringSync();
    ruArb = File('lib/l10n/intl_ru.arb').readAsStringSync();
  });

  /// Тело ListTile, внутри которого встречается [marker].
  String tileContaining(String src, String marker) {
    final markerIdx = src.indexOf(marker);
    expect(markerIdx, isNot(-1), reason: 'в исходнике нет «$marker»');
    final start = src.lastIndexOf('ListTile(', markerIdx);
    expect(start, isNot(-1), reason: '«$marker» не внутри ListTile');
    final end = src.indexOf('),\n', markerIdx);
    return src.substring(start, end == -1 ? src.length : end);
  }

  // AC-1: внешняя ссылка на liza.ru/legal подписана privacyPolicy, не privacy.
  // Ловит возврат к подписи «Приватность» на юридическом документе.
  // AC:RL-settings-privacy-security-labels/1
  test('AC-1: пункт launchUrl(privacyUrl) использует ключ privacyPolicy', () {
    final tile = tileContaining(settingsSrc, 'launchUrl(AppConfig.privacyUrl)');
    expect(
      tile.contains('L10n.of(context).privacyPolicy'),
      isTrue,
      reason: 'внешняя ссылка должна называться «Политика конфиденциальности» '
          '(ключ privacyPolicy), а не generic «Приватность»',
    );
    expect(
      tile.contains('L10n.of(context).privacy)'),
      isFalse,
      reason: 'старый ключ privacy на внешней ссылке = регресс LABA-2548',
    );
  });

  // AC-2: у внешней ссылки иконка open_in_new — предупреждение «уйдёшь в браузер».
  // AC:RL-settings-privacy-security-labels/2
  test('AC-2: у пункта privacyPolicy есть trailing Icons.open_in_new*', () {
    final tile = tileContaining(settingsSrc, 'launchUrl(AppConfig.privacyUrl)');
    expect(
      tile.contains('trailing') && tile.contains('Icons.open_in_new'),
      isTrue,
      reason: 'пункт уводит из приложения — нужна trailing-иконка open_in_new',
    );
  });

  // AC-3: вход в «Приватность и безопасность» скрыт из меню настроек
  // (требование сессии 2026-09-17), но САМ экран и его маршрут сохранены —
  // удалён только пункт меню. Прежняя редакция AC-3 требовала обратного
  // (наличия пункта с подписью privacyAndSecurity) и этим замещена.
  // Тот же ассерт закрывает AC-2 записи RL-about-screen-legal («вместо
  // Приватности раскрываем О проекте» — две стороны одного требования).
  // AC:RL-settings-privacy-security-labels/3 AC:RL-about-screen-legal/2
  test('AC-3: в меню настроек нет входа в /rooms/settings/security', () {
    expect(
      settingsSrc.contains("context.go('/rooms/settings/security')"),
      isFalse,
      reason: 'пункт «Приватность и безопасность» должен быть скрыт из меню',
    );
  });

  // AC-4: AppBar экрана — тот же ключ, что и пункт меню (не разъезжаются).
  // AC:RL-settings-privacy-security-labels/4
  test('AC-4: AppBar settings_security_view использует privacyAndSecurity', () {
    final appBarIdx = securitySrc.indexOf('appBar: AppBar(');
    expect(appBarIdx, isNot(-1));
    final head = securitySrc.substring(appBarIdx, appBarIdx + 200);
    expect(
      head.contains('L10n.of(context).privacyAndSecurity'),
      isTrue,
      reason: 'заголовок экрана обязан совпадать с подписью пункта меню',
    );
  });

  // AC-5: обе русские строки есть в intl_ru.arb дословно.
  // Отсутствие ключа в intl_en.arb ловит кодогенерация gen_l10n раньше теста;
  // молчаливо ломается только ru (английский fallback в русском UI).
  // AC:RL-settings-privacy-security-labels/5
  test('AC-5: intl_ru.arb содержит русские значения обоих новых ключей', () {
    expect(
      ruArb.contains('"privacyPolicy": "Политика конфиденциальности"'),
      isTrue,
      reason: 'без русского значения UI покажет английский Privacy policy',
    );
    expect(
      ruArb.contains('"privacyAndSecurity": "Приватность и безопасность"'),
      isTrue,
      reason: 'без русского значения UI покажет английский Privacy and security',
    );
  });

  // AC-6: старый ключ privacy жив как заголовок секции внутри экрана —
  // страж против глобальной замены .privacy → .privacyPolicy.
  // AC:RL-settings-privacy-security-labels/6
  test('AC-6: секционный заголовок .privacy внутри экрана не снесён', () {
    expect(
      securitySrc.contains('L10n.of(context).privacy,'),
      isTrue,
      reason: 'секция «Приватность» внутри экрана должна остаться '
          '(в неё едет profileVisibility из feat/types)',
    );
  });
}
