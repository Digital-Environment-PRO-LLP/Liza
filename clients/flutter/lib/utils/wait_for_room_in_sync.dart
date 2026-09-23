import 'package:matrix/matrix.dart';

/// Ждёт, пока комната появится в локальном [Client.rooms] через `/sync`.
///
/// `createRoom` возвращает успех сразу после записи на сервере, но
/// `client.getRoomById` видит комнату только после следующего sync-цикла —
/// без ожидания переход в комнату (`context.go('/rooms/$roomId')`) сразу
/// после создания натыкается на `room == null` (ChatPage показывает "вы
/// больше не участвуете в этом чате").
///
/// Условие готовности:
/// - для пространства (`expectSpace`) — рум появился И `isSpace` распознан
///   (пришёл m.room.create с типом m.space), чтобы навигация не ушла в ChatPage;
/// - иначе — membership join ИЛИ invite (для статуса invited рум приходит как
///   invite, ждать только join бессмысленно — упёрлись бы в полный таймаут).
/// Возвращает `true`, если комната дождалась, и `false` — если истёк [timeout].
/// Отличать эти исходы обязательно: «не приехала за отведённое время» — это НЕ
/// «сервер отказал», и пользователю о них надо говорить разное
/// (см. `ChannelDiscussion.ensureDiscussionMembership`).
Future<bool> waitForRoomInSync(
  Client client,
  String roomId, {
  Duration timeout = const Duration(seconds: 5),
  bool expectSpace = false,
}) async {
  bool ready(Room? room) {
    if (room == null) return false;
    if (expectSpace) return room.isSpace;
    return room.membership == Membership.join ||
        room.membership == Membership.invite;
  }

  if (ready(client.getRoomById(roomId))) return true;
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await client.oneShotSync();
    if (ready(client.getRoomById(roomId))) return true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  Logs().w('[waitForRoomInSync] room $roomId did not appear within $timeout');
  return false;
}
