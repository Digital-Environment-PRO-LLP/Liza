// Страж инварианта invite-ссылок в cross-HS мультиаккаунт-бандле.
// ledger:RL-invite-link-host-client
//
// История:
//  - Баг 1 (2026-06-24): server_name брался из активного аккаунта → auth-proxy
//    отвечал "room_id ...:synapse... not on server nadezhda.liza.ru".
//  - Баг 2 (2026-06-25): фикс выбирал аккаунт по СОВПАДЕНИЮ домена room_id, но
//    у Нади prod-аккаунт совпадал по домену, а в комнате НЕ состоял →
//    "@...:synapse... not in !...:synapse..." (403). Член комнаты — её
//    федеративный аккаунт nadezhda.liza.ru.
//
// Инвариант (после фикса 2026-06-25): «чей токен» и «server_name» —
// ОРТОГОНАЛЬНЫ.
//  - Токен invite-операции = аккаунт, реально СОСТОЯЩИЙ в комнате (room.client),
//    даже если его домен ≠ домену room.id (cross-HS членство).
//  - server_name = домен room.id (хостящий HS), независимо от выбора токена.
//    auth-proxy резолвит mxid вызывающего по всем нашим HS и проверяет
//    членство/PL через Admin API; inviter-of-record он подбирает локальным
//    членом сам.

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat_details/invite_link_dialog.dart';

void main() {
  const synapseRoom = '!OyHJaAotDLIGEgzdHP:synapse.liza.laba.prodamus.tech';

  group('InviteLinkDialog.inviteServerName — server_name из домена room.id', () {
    test('cross-HS член: server_name = хостящий HS, НЕ домен аккаунта-члена', () {
      // Надя состоит в комнате федеративным @...:nadezhda.liza.ru, но комната
      // хостится на synapse... — server_name обязан быть хостящим HS.
      expect(
        InviteLinkDialog.inviteServerName(synapseRoom),
        'synapse.liza.laba.prodamus.tech',
      );
    });

    test('одно-серверный кейс: домен room.id', () {
      expect(
        InviteLinkDialog.inviteServerName('!abc:nadezhda.liza.ru'),
        'nadezhda.liza.ru',
      );
    });
  });
}
