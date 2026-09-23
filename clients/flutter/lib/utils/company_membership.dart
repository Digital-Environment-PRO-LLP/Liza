import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';

/// Как текущий аккаунт относится к этому пространству-компании.
enum CompanyMembershipKind {
  /// Своё главное пространство (тот же homeserver) — leave запрещён, кнопку скрыть.
  own,

  /// Чужая компания (другой homeserver), подписка — показать "Отписаться".
  foreign,

  /// Не компания (обычное пространство/суб-пространство) — обычное "Покинуть".
  none,
}

/// Что на самом деле делает пункт «выхода» из комнаты — и, значит, как он
/// обязан быть подписан (LABA-2540).
///
/// До LABA-2540 подпись расходилась с действием: пункт назывался «Удалить чат»
/// с иконкой корзины, а вызывал `room.leave()` — чат оставался у остальных
/// участников и уезжал в архив. Слово «Удалить» правдиво ровно в одном месте
/// клиента — на корзине экрана «Архив», где вызывается `Room.forget()`.
enum LeaveActionKind {
  /// Своё главное пространство: `single_space_guard` запрещает leave (вернёт
  /// 403), поэтому пункт не показываем вовсе.
  hidden,

  /// Своё главное пространство глазами админа (LABA-2533): компания = целый
  /// Synapse-инстанс, из клиента её не удалить — выводит из эксплуатации
  /// поддержка. Пункт ведёт в DM с `@support` с готовой заявкой в композере;
  /// `leave()`/`forget()` не вызываются.
  deleteCompanyViaSupport,

  /// Приглашение ещё не принято: `leave()` здесь — отказ от приглашения,
  /// никакой чат никуда не переезжает.
  declineInvite,

  /// Чужая компания: `leave()` — отписка от компании, а не выход из чата.
  unsubscribeCompany,

  /// Канал.
  leaveChannel,

  /// Обычное пространство (не компания).
  leaveSpace,

  /// Группа, личка, чат-обсуждение канала.
  leaveChat,
}

/// Таблица решений «тип комнаты + membership → как подписать выход».
///
/// Чистая функция: единственный источник правды для трёх точек входа (меню в
/// шапке чата, контекстное меню плитки списка, меню пространства), которые
/// раньше разошлись между собой на четырёх ветках из шести.
///
/// [isAdmin] — PL текущего пользователя ≥ `adminPowerLevel`. Считается только
/// для своей компании: админу вместо пустоты даём вход «удалить через
/// поддержку». Права берём по power level, а не по домену: кросс-доменный
/// админ (ops-аккаунт с другого сервера) по домену — `foreign`, и ему по модели
/// положена отписка, а не заявка на удаление.
LeaveActionKind leaveActionKind({
  required Membership membership,
  required CompanyMembershipKind companyKind,
  required bool isMainRootSpace,
  required bool isChannel,
  required bool isSpace,
  bool isAdmin = false,
}) {
  if (isMainRootSpace || companyKind == CompanyMembershipKind.own) {
    return isAdmin && membership == Membership.join
        ? LeaveActionKind.deleteCompanyViaSupport
        : LeaveActionKind.hidden;
  }
  if (membership == Membership.invite) return LeaveActionKind.declineInvite;
  if (companyKind == CompanyMembershipKind.foreign) {
    return LeaveActionKind.unsubscribeCompany;
  }
  if (isChannel) return LeaveActionKind.leaveChannel;
  if (isSpace) return LeaveActionKind.leaveSpace;
  return LeaveActionKind.leaveChat;
}

/// Подпись действия. Один и тот же глагол идёт в пункт меню, в заголовок
/// диалога и на кнопку подтверждения: рассинхрон «Удалить чат» → «Покинуть»
/// и был предметом жалобы LABA-2540.
String leaveActionLabel(L10n l10n, LeaveActionKind kind) => switch (kind) {
  LeaveActionKind.hidden => '',
  LeaveActionKind.deleteCompanyViaSupport => l10n.deleteCompanyViaSupport,
  LeaveActionKind.declineInvite => l10n.declineInvitation,
  LeaveActionKind.unsubscribeCompany => l10n.unsubscribeFromCompany,
  LeaveActionKind.leaveChannel => l10n.channelLeave,
  LeaveActionKind.leaveSpace => l10n.leave,
  LeaveActionKind.leaveChat => l10n.leaveChatAction,
};

/// Тело диалога подтверждения: что именно произойдёт и что останется у
/// остальных участников.
String leaveActionMessage(L10n l10n, LeaveActionKind kind) => switch (kind) {
  LeaveActionKind.hidden => '',
  // Диалог с именем компании собирает `requestCompanyDeletion`
  // (company_deletion.dart) — через общий leave-путь этот вид не идёт.
  LeaveActionKind.deleteCompanyViaSupport => '',
  LeaveActionKind.declineInvite => l10n.areYouSure,
  LeaveActionKind.unsubscribeCompany => l10n.unsubscribeFromCompanyDescription,
  LeaveActionKind.leaveSpace => l10n.leaveSpaceDescription,
  LeaveActionKind.leaveChannel ||
  LeaveActionKind.leaveChat => l10n.archiveRoomDescription,
};

String? _domain(String id) {
  final idx = id.indexOf(':');
  return idx < 0 ? null : id.substring(idx + 1);
}

/// Определяет тип членства для пространства по доменам и top-level-признаку.
///
/// [isTopLevelSpace] — пространство без входящего m.space.child (root-space).
CompanyMembershipKind foreignCompanyKind({
  required String? userId,
  required String roomId,
  required bool isTopLevelSpace,
}) {
  if (!isTopLevelSpace) return CompanyMembershipKind.none;
  final userDomain = userId == null ? null : _domain(userId);
  final roomDomain = _domain(roomId);
  if (userDomain == null || roomDomain == null) {
    return CompanyMembershipKind.none;
  }
  return userDomain == roomDomain
      ? CompanyMembershipKind.own
      : CompanyMembershipKind.foreign;
}

/// Является ли комната top-level пространством: это space, и ни одно joined
/// пространство клиента не содержит её как m.space.child.
bool isTopLevelSpaceRoom(Room room) {
  if (!room.isSpace) return false;
  return !room.client.rooms.any(
    (s) => s.isSpace && s.spaceChildren.any((c) => c.roomId == room.id),
  );
}

/// Показывать ли в чате плашку "подписаться на компанию".
///
/// [parentCompanyId] — room_id компании, дочерним которой является чат.
/// [userId] — текущий пользователь.
/// [localCompanyRoom] — пространство-компания в client.rooms, если оно там
/// есть (юзер подписан/был подписан/имеет invite). null, если не знает о ней.
///
/// Условия плашки: компания на ЧУЖОМ для юзера домене (foreign) И юзер сейчас
/// не подписан (не в client.rooms ИЛИ membership != join).
bool shouldShowCompanySubscribeBanner({
  required String? parentCompanyId,
  required String? userId,
  required Room? localCompanyRoom,
}) {
  if (parentCompanyId == null) return false;
  final kind = foreignCompanyKind(
    userId: userId,
    roomId: parentCompanyId,
    isTopLevelSpace: true,
  );
  if (kind != CompanyMembershipKind.foreign) return false;
  if (localCompanyRoom == null) return true;
  return localCompanyRoom.membership != Membership.join;
}
