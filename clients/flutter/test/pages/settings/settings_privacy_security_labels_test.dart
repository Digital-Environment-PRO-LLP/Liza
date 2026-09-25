// ledger:RL-settings-privacy-security-labels
// AC:RL-settings-privacy-security-labels/1
// AC:RL-settings-privacy-security-labels/3 AC:RL-settings-privacy-security-labels/4
// AC:RL-settings-privacy-security-labels/5 AC:RL-settings-privacy-security-labels/6
//
// Страж подписей пунктов настроек (LABA-2548): экран внутренних настроек —
// «Приватность и безопасность»; внешней ссылки на политику конфиденциальности
// в меню нет (с 2026-09-25 она только в «О приложении»).
// guard.render: source/l10n-ассерты — полный рендер SettingsView требует
// SettingsController + Matrix + GoRouter (тот же компромисс, что и в
// settings_invite_friends_test.dart).
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

  // AC-1 (переформулирован 2026-09-25): пункт «Политика конфиденциальности»
  // убран из меню «Настройки» — документ доступен в «О приложении» (там его
  // держит AC-3 RL-about-screen-legal). Прежняя редакция AC-1/AC-2 требовала
  // наличия пункта с подписью privacyPolicy и иконкой open_in_new.
  // AC:RL-settings-privacy-security-labels/1
  test('AC-1: в меню настроек нет пункта launchUrl(privacyUrl)', () {
    expect(
      settingsSrc.contains('AppConfig.privacyUrl'),
      isFalse,
      reason:
          'политика конфиденциальности — только в «О приложении», '
          'дубль в меню настроек убран',
    );
    expect(settingsSrc.contains('.privacyPolicy'), isFalse);
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
      reason:
          'без русского значения UI покажет английский Privacy and security',
    );
  });

  // AC-6: старый ключ privacy жив как заголовок секции внутри экрана —
  // страж против глобальной замены .privacy → .privacyPolicy.
  // AC:RL-settings-privacy-security-labels/6
  test('AC-6: секционный заголовок .privacy внутри экрана не снесён', () {
    expect(
      securitySrc.contains('L10n.of(context).privacy,'),
      isTrue,
      reason:
          'секция «Приватность» внутри экрана должна остаться '
          '(в неё едет profileVisibility из feat/types)',
    );
  });
}
