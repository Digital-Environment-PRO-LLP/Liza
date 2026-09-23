import 'package:flutter/widgets.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/widgets/adaptive_dialogs/user_dialog.dart';
import 'package:liza/widgets/liza_app.dart';

/// Открывает карточку профиля поверх текущего экрана после навигации.
///
/// Единая точка для ссылок `/u/<ник>` и user-инвайта `/i/<code>`
/// («Пригласить друзей», LABA-2551): обе ведут на нейтральный `/rooms`, а
/// карточка пушится post-frame через глобальный navigatorKey — собственный
/// context redirect'а/OpeningPage к моменту показа уже размонтирован
/// навигацией. Корневой Navigator единый на весь GoRouter (у ShellRoute нет
/// своего navigatorKey), поэтому в column-mode диалог модален поверх всего
/// TwoColumnLayout — это допущение, не случайность.
///
/// Профиль тянется с таймаутом: зависший запрос иначе означал бы «диалог так
/// и не появился», неотличимо от проглоченной ссылки.
///
/// [navigatorContext] — ради теста: в приложении это context корневого
/// навигатора `LizaApp.router`, статик которого в тесте не подменить.
void openUserProfile(
  Client client,
  String mxid, {
  Duration profileTimeout = const Duration(seconds: 10),
  BuildContext? Function() navigatorContext = _rootNavigatorContext,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final navContext = navigatorContext();
    if (navContext == null) return;
    var noProfileWarning = false;
    final profile = await client
        .getProfileFromUserId(mxid)
        .timeout(profileTimeout)
        .catchError((Object e) {
      // Любой сбой (таймаут, сеть, ошибка SDK) деградирует в карточку без
      // профиля, но причина обязана попасть в лог — иначе регресс профиля
      // неотличим от обычного сетевого сбоя.
      Logs().w('[UserProfile] профиль $mxid не подтянулся: $e');
      noProfileWarning = true;
      return Profile(userId: mxid);
    });
    if (!navContext.mounted) return;
    await UserDialog.show(
      context: navContext,
      profile: profile,
      noProfileWarning: noProfileWarning,
    );
  });
}

BuildContext? _rootNavigatorContext() =>
    LizaApp.router.routerDelegate.navigatorKey.currentContext;
