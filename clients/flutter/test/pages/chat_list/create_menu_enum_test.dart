// ledger:RL-create-menu-contacts-items
// AC:RL-create-menu-contacts-items/3 AC:RL-create-menu-contacts-items/4
//
// Страж enum-пунктов меню «+» и маршрутизации invite.
// guard.render:pure-function — не рендерит ChatListHeader (требует
// ChatListController + Matrix; device residual для AC-1/2, см. RL).
// AC-4: прежние и новые значения enum присутствуют.
// AC-3: invite-ветка вызывает shareInvitePeople, не QR-метод.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String src;

  setUpAll(() {
    // Путь относительно flutter/ (flutter test запускается из flutter/).
    src = File('lib/pages/chat_list/chat_list_header.dart').readAsStringSync();
  });

  // AC-4: регресс — прежние пункты enum + новые invite/contacts целы.
  // AC:RL-create-menu-contacts-items/4
  test(
    'AC-4: enum _CreateMenuAction содержит все ожидаемые значения '
    '(group/channel/story/bot/miniApp/invite/contacts)',
    () {
      const expected = [
        'group',
        'channel',
        'story',
        'bot',
        'miniApp',
        'invite',
        'contacts',
      ];
      for (final value in expected) {
        expect(
          src.contains(value),
          isTrue,
          reason: 'enum _CreateMenuAction должен содержать значение $value',
        );
      }
    },
  );

  // Витрина MCP: пункт «Добавить МСР» ведёт по ОБЩЕЙ константе, а не по
  // литералу пути. Порядок (после miniApp, отдельным разделом) source-ассертом
  // не проверить — он в manual-пункте RL-mcp-showcase-entry-points/AC-1.
  // AC:RL-mcp-showcase-entry-points/5
  test(
    'AC-5: пункт mcp есть в enum и ведёт по AppRoutes.settingsMcp',
    () {
      expect(
        src.contains('mcp'),
        isTrue,
        reason: 'enum _CreateMenuAction должен содержать значение mcp',
      );
      expect(
        src.contains('context.go(AppRoutes.settingsMcp)'),
        isTrue,
        reason:
            'вход «Добавить МСР» обязан идти по общей константе '
            'AppRoutes.settingsMcp — три литерала пути разъедутся молча',
      );
      expect(
        src.contains("context.go('/rooms/settings/integrations')"),
        isFalse,
        reason: 'литерал пути вместо константы — тот самый разъезд',
      );
    },
  );

  // AC-3: invite-ветка → shareInvitePeople (не QR / не LizaShare.share(mxid,…)).
  // AC:RL-create-menu-contacts-items/3
  test(
    'AC-3: ветка invite вызывает LizaShare.shareInvitePeople, '
    'contacts → /rooms/contacts',
    () {
      expect(
        src.contains('CreateMenuAction.invite'),
        isTrue,
        reason: 'enum-значение invite должно быть в switch',
      );
      expect(
        src.contains('LizaShare.shareInvitePeople'),
        isTrue,
        reason: 'invite-ветка должна вызывать shareInvitePeople, не share(mxid)',
      );
      expect(
        src.contains("context.go('/rooms/contacts')"),
        isTrue,
        reason: "contacts-ветка должна вести на '/rooms/contacts'",
      );
    },
  );
}
