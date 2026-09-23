import 'package:matrix/matrix.dart';

import 'chat_topology.dart';
import 'stories/active_stories_provider.dart';

/// Цель навигации при тапе по уведомлению (фон-пуш / внутреннее уведомление),
/// вычисленная ЧИСТО — без Navigator/BuildContext, чтобы решение «сторис-вьюер
/// vs обычный чат» покрывалось unit-тестом. Навигацию исполняет вызывающий
/// (`notificationTap` и iOS cold-start в `background_push`).
///
/// Зачем: раньше тап безусловно шёл в `/rooms/$roomId`, и для сторис это
/// открывало топологически СКРЫТУЮ техническую сторис-комнату (её же прячет
/// `isHiddenChat`) вместо просмотрщика — а после выхода она «пропадала» из
/// списка (список фильтрует `!isHiddenChat`).
sealed class PushTapTarget {
  const PushTapTarget();
}

/// Обычная комната или invite — go_router по [routePath]
/// (`/rooms/$roomId` для чата, `/rooms` для invite/отсутствующей комнаты).
class RoomTapTarget extends PushTapTarget {
  const RoomTapTarget(this.routePath);
  final String routePath;

  @override
  bool operator ==(Object other) =>
      other is RoomTapTarget && other.routePath == routePath;

  @override
  int get hashCode => routePath.hashCode;
}

/// Сторис-комната — открыть `StoryViewer` с этими аргументами.
///
/// Инвариант (INV-1): `roomIds[initialIndex]` == сторис-комната из уведомления.
/// Без него `StoryViewer._loadAuthor` не применит `initialEventId` (он берётся
/// только когда `authorIndex == initialIndex`) и кликнутый сегмент потеряется.
class StoryTapTarget extends PushTapTarget {
  const StoryTapTarget({
    required this.roomIds,
    required this.initialIndex,
    required this.initialEventId,
  });
  final List<String> roomIds;
  final int initialIndex;
  final String? initialEventId;
}

/// Санитайз eventId из пуш-payload.
///
/// `LizaPushPayload.toString` интерполирует Dart `null` в литерал `"null"`, а
/// `fromString` делает голый `split('|')` — значит при отсутствии `event_id` в
/// пуше `payload.eventId == "null"`. Без очистки `initialEventId == "null"` не
/// совпадёт ни с одним сегментом → фолбэк на первый непрочитанный вместо
/// кликнутого. Пустая строка — тот же случай.
String? sanitizePushEventId(String? eventId) {
  if (eventId == null || eventId.isEmpty || eventId == 'null') return null;
  return eventId;
}

/// Чистое ЯДРО резолва — без `Client`, чтобы тестироваться без sync/Navigator
/// (тот же приём, что `resolveInviteTargetFromResult`: pure core + тонкая
/// обёртка над Client).
///
/// - комнаты нет / invite → `RoomTapTarget('/rooms')`;
/// - сторис-комната (`isStoryRoom`, вкл. канальные — тот же маркер) →
///   `StoryTapTarget`;
/// - иначе → `RoomTapTarget('/rooms/$roomId')`.
///
/// [activeQueueIds] — порядок сторис-комнат из `ActiveStoriesProvider` (единый
/// со `StoriesBar`). При непрогретом кэше (cold-start, бар ещё не смонтирован)
/// он пуст → деградация до `[roomId]` single-author (INV-3): известное
/// ограничение, не баг — `/sync` прогреет бар, следующий тап даст полную очередь.
///
/// Инвариант INV-1: `StoryTapTarget.roomIds[initialIndex] == roomId` в ОБЕИХ
/// ветках (найдено в очереди / деградация) — иначе `initialEventId` не применится.
PushTapTarget pushTapTargetFor({
  required String roomId,
  required bool roomExists,
  required bool isInvite,
  required bool isStoryRoom,
  required bool isJoined,
  required List<String> activeQueueIds,
  required String? eventId,
}) {
  if (!roomExists || isInvite) {
    return const RoomTapTarget('/rooms');
  }
  if (isStoryRoom) {
    // Сторис-комната, из которой пользователь вышел/забанен (membership !=
    // join): StoryViewer всё равно не загрузит сегменты (activeStoriesWithTimeline
    // требует join) → мигнул бы и закрылся. Ведём в список чатов, а не в вьюер.
    if (!isJoined) return const RoomTapTarget('/rooms');
  } else {
    return RoomTapTarget('/rooms/$roomId');
  }
  var idx = activeQueueIds.indexOf(roomId);
  final roomIds = idx >= 0 ? List<String>.of(activeQueueIds) : <String>[roomId];
  if (idx < 0) idx = 0;
  return StoryTapTarget(
    roomIds: roomIds,
    initialIndex: idx,
    initialEventId: sanitizePushEventId(eventId),
  );
}

/// Резолвер цели тапа над живым `Client` — собирает входы ядра и делегирует.
PushTapTarget resolvePushTapTarget(
  Client client,
  String roomId,
  String? eventId,
) {
  final room = client.getRoomById(roomId);
  return pushTapTargetFor(
    roomId: roomId,
    roomExists: room != null,
    isInvite: room?.membership == Membership.invite,
    isStoryRoom: room?.lizaChatType == 'stories',
    isJoined: room?.membership == Membership.join,
    activeQueueIds: ActiveStoriesProvider.instance
        .orderedRoomsWithActive(client)
        .map((r) => r.id)
        .toList(),
    eventId: eventId,
  );
}
