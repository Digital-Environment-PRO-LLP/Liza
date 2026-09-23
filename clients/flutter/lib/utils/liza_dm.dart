import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';

/// Живая 1:1-комната с ассистентом Лизой.
///
/// Ищем по MEMBER-стейту, а НЕ по `directChatMatrixID`: последний выводится из
/// m.direct, а именно его запись могла не создаться (сетевой сбой после
/// `startDirectChat` / стухший кеш) — тогда поиск промахнулся бы и появился второй
/// DM. Мёртвый `@liza:synapse...` DM (партнёр leave) под условие не подходит.
/// mini App-чат исключаем по непустому имени (единственный @liza-DM без
/// m.room.name — ассистент).
Room? findLizaAssistantDm(Client client, String lizaMxid) =>
    client.rooms.firstWhereOrNull(
      (r) =>
          !r.isSpace &&
          (r.getState(EventTypes.RoomName)?.content.tryGet<String>('name') ??
                  '')
              .isEmpty &&
          r
                  .getState(EventTypes.RoomMember, lizaMxid)
                  ?.content
                  .tryGet<String>('membership') ==
              'join',
    );

/// Ждёт, пока [userId] вступит в комнату. Нужна свежему DM с ботом: событие,
/// отправленное до его join, бот увидит вперемешку с историей и приветствием.
Future<bool> waitForMemberJoin(
  Client client,
  String roomId,
  String userId, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  bool joined() =>
      client
          .getRoomById(roomId)
          ?.getState(EventTypes.RoomMember, userId)
          ?.content
          .tryGet<String>('membership') ==
      'join';

  final deadline = DateTime.now().add(timeout);
  while (!joined()) {
    if (!DateTime.now().isBefore(deadline)) {
      Logs().w('[LizaDm] $userId не вступил в $roomId за $timeout');
      return false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return true;
}
