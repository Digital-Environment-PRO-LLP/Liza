// ledger:RL-settings-invite-friends-action
// AC:RL-settings-invite-friends-action/1 AC:RL-settings-invite-friends-action/2
//
// Страж пункта «Пригласить друзей» в настройках: текст из intl_ru (AC-1) и
// вызов shareInvitePeople а не share(mxid) (AC-2 — source-ассерт).
// guard.render: текстовый AC-1 — source/l10n ассерт (SettingsView требует
// SettingsController + Matrix + GoRouter; полный рендер — device residual, см. RL).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    src = File('lib/pages/settings/settings_view.dart').readAsStringSync();
  });

  // AC-1: пункт «Пригласить друзей» присутствует (использует l10n-ключ inviteFriends).
  // Ловит дыру intl_ru: если ключ удалён из arb — компиляция упадёт раньше.
  // Если ListTile убран — ассерт краснеет.
  // AC:RL-settings-invite-friends-action/1
  test(
    'AC-1: settings_view использует L10n-ключ inviteFriends (не хардкод)',
    () {
      expect(
        src.contains('.inviteFriends'),
        isTrue,
        reason: 'ListTile должен использовать L10n.of(context).inviteFriends, '
            'а не хардкод строки',
      );
    },
  );

  // AC-2: действие — shareInvitePeople, не LizaShare.share(mxid, copyOnly).
  // Ловит регресс возврата к QR/копирование mxid вместо нативного шеринга.
  // AC:RL-settings-invite-friends-action/2
  test(
    'AC-2: onTap пункта inviteFriends вызывает shareInvitePeople, '
    'не share(mxid,…) / LizaShare.share',
    () {
      expect(
        src.contains('LizaShare.shareInvitePeople'),
        isTrue,
        reason: 'inviteFriends должен вызывать shareInvitePeople (нативный share), '
            'а не share(mxid, copyOnly)',
      );
      // Проверяем, что shareInvitePeople присутствует рядом с inviteFriends.
      final inviteFriendsIdx = src.indexOf('.inviteFriends');
      final shareInviteIdx = src.indexOf('LizaShare.shareInvitePeople');
      expect(
        inviteFriendsIdx,
        isNot(-1),
        reason: 'inviteFriends должен быть в исходнике',
      );
      expect(
        shareInviteIdx,
        isNot(-1),
        reason: 'shareInvitePeople должен быть в исходнике',
      );
      // Оба находятся в одном ListTile-блоке (расстояние < 200 символов).
      final distance = (shareInviteIdx - inviteFriendsIdx).abs();
      expect(
        distance,
        lessThan(200),
        reason: 'shareInvitePeople должен быть рядом с inviteFriends '
            '(один ListTile), дистанция: $distance',
      );
    },
  );
}
