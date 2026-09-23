import 'package:matrix/matrix.dart';

import 'package:liza/utils/chat_topology.dart';

/// Сколько участников ждут одобрения. Чистая функция — тестируется без клиента.
int countKnocking(Iterable<Membership> memberships) =>
    memberships.where((m) => m == Membership.knock).length;

/// Заявки в комнате. getParticipants() по умолчанию уже включает
/// Membership.knock. ВНИМАНИЕ: при room.partial==true состояние может не
/// содержать knock-членов до requestParticipants() — см. KnockRequestBadge,
/// который подтягивает участников явно перед подсчётом.
int knockRequestCount(Room room) =>
    countKnocking(room.getParticipants().map((u) => u.membership));

/// Показывать счётчик только тем, кто реально может рассматривать заявки:
/// ownPowerLevel >= модератора. НЕ room.canInvite — у компании (space)
/// invite:0 по умолчанию, и canInvite вернул бы true ВСЕМ участникам, бейдж
/// утёк бы всем (нарушение приватности заявки). moderatorPowerLevel совпадает
/// с серверным гейтом knock_notify и с canSeeMembersAt (chat_topology.dart).
bool canReviewKnockRequests(Room room) =>
    room.membership == Membership.join &&
    room.ownPowerLevel >= moderatorPowerLevel;
