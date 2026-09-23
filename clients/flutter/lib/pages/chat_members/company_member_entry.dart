import 'package:liza/utils/access_admin_service.dart';

/// Эффективный уровень прав участника компании.
///
/// У участника, состоящего ТОЛЬКО в дочерних сущностях, нет User-объекта из
/// SDK: вьюха строит синтетический, и его powerLevel всегда равен
/// users_default корневой комнаты (0). Поэтому роль такого участника берём из
/// данных space_members, иначе фильтр ролей судит по заведомо нулевому PL.
int effectiveMemberPowerLevel({
  required int roomPowerLevel,
  SpaceMember? spaceMember,
}) {
  final spacePower = spaceMember?.maxPowerLevel ?? 0;
  return roomPowerLevel > spacePower ? roomPowerLevel : spacePower;
}

/// Относится ли аккаунт к серверу компании — по домену Matrix ID.
bool memberBelongsToServer({
  required String userId,
  required String serverName,
}) {
  final separator = userId.indexOf(':');
  if (separator < 0) return false;
  return userId.substring(separator + 1) == serverName;
}

/// Подписан ли аккаунт на саму компанию (а не только на её дочерние сущности).
bool memberJoinedCompany({
  required bool joinedRoom,
  SpaceMember? spaceMember,
}) =>
    joinedRoom || spaceMember?.membershipInSpace != null;

/// Два чекбокса под табами ролей — независимые сужения, комбинируются по AND.
/// Снятый чекбокс не фильтрует ничего.
bool matchesMembershipCheckboxes({
  required bool onServerOnly,
  required bool inCompanyOnly,
  required bool belongsToServer,
  required bool joinedCompany,
}) {
  if (onServerOnly && !belongsToServer) return false;
  if (inCompanyOnly && !joinedCompany) return false;
  return true;
}
