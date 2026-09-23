import 'package:matrix/matrix.dart';

import 'package:liza/utils/auth_proxy_service.dart';
import 'package:liza/utils/miniapp_room.dart';

/// Синхронизация блокировок участников магазина (mini App) с auth-proxy.
///
/// Matrix-бан/кик выполняет клиент своим токеном (мгновенный выброс + запрет
/// входа в комнату), а эти helper'ы пишут источник истины статуса в auth-proxy
/// и гейтят повторный redeem по ссылке per-user (в т.ч. ветку miniapp_invite,
/// которую Matrix-бан не закрывает). Подробности — plans/miniApps/deletUsers.md.

/// True, если комната — чат-лаунчер магазина (есть `com.liza.miniapp.config`).
bool isMiniAppStoreRoom(Room room) => miniAppLaunchForRoom(room) != null;

/// Статусы блокировки. Совпадают с enum в auth-proxy (store._VALID_BLOCK_STATUSES).
class MemberBlockStatus {
  static const banned = 'banned';
  static const removed = 'removed';
  static const inviteRevoked = 'invite_revoked';
}

/// server_name для blocklist-операций — домен хостящего комнату HS (из room.id),
/// а не домен аккаунта-члена (cross-HS бандл). Ортогонально выбору токена.
String _storeServerName(String roomId) => roomId.split(':').last;

String _requireToken(Room room) {
  final token = room.client.accessToken;
  if (token == null) {
    throw StateError('No access_token in Matrix client');
  }
  return token;
}

/// Заносит участника в blocklist магазина (banned/removed/invite_revoked).
Future<void> blockStoreMember({
  required Room room,
  required String userId,
  required String status,
  String? displayName,
  String? reason,
}) async {
  await AuthProxyService().blockMember(
    serverName: _storeServerName(room.id),
    roomId: room.id,
    mxid: userId,
    status: status,
    accessToken: _requireToken(room),
    reason: reason,
    displayName: displayName,
  );
}

/// Снимает блокировку участника магазина.
Future<void> unblockStoreMember({
  required Room room,
  required String userId,
}) async {
  await AuthProxyService().unblockMember(
    serverName: _storeServerName(room.id),
    roomId: room.id,
    mxid: userId,
    accessToken: _requireToken(room),
  );
}

/// Список активных блокировок магазина.
Future<List<MemberBlockInfo>> listStoreBlocks(Room room) =>
    AuthProxyService().listMemberBlocks(
      serverName: _storeServerName(room.id),
      roomId: room.id,
      accessToken: _requireToken(room),
    );
