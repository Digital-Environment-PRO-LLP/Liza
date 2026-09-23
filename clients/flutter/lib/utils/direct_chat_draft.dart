import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

/// Чистое решение о цели навигации по правилу «чат/запрос — только с первым
/// сообщением» (тестируется без Client/виджета):
///
/// - передан `joinedRoomId` (есть присоединённый DM) → сразу реальная комната;
/// - иначе → ЧЕРНОВОЙ чат `/rooms/newchat/<userId>` (комната родится при
///   отправке первого сообщения).
String directChatTarget({required String userId, String? joinedRoomId}) {
  if (joinedRoomId != null) return '/rooms/$joinedRoomId';
  return '/rooms/newchat/${Uri.encodeComponent(userId)}';
}

/// Открывает личный чат с [userId]. Существующий ПРИСОЕДИНЁННЫЙ DM
/// (`membership == join`) открывает сразу; отсутствие DM ИЛИ только invite-DM
/// (мы ещё не приняли приглашение) → черновик. Боты, группы и redeem invite-
/// ссылки этот путь НЕ используют — им комната нужна сразу.
///
/// Спека: `docs/superpowers/specs/2026-09-03-direct-chat-draft-on-first-message-design.md`.
void openDirectChatOrDraft(
  GoRouter router,
  Client client,
  String userId, {
  Profile? profile,
}) {
  final existingId = client.getDirectChatFromUserId(userId);
  final existing = existingId == null ? null : client.getRoomById(existingId);
  final joinedRoomId =
      (existing != null && existing.membership == Membership.join)
      ? existingId
      : null;
  if (joinedRoomId != null) {
    router.go(directChatTarget(userId: userId, joinedRoomId: joinedRoomId));
  } else {
    router.go(directChatTarget(userId: userId), extra: profile);
  }
}

// Материализация черновика (ровно один `startDirectChat` при двойном тапе /
// текст+файл) — в общей воронке `Client.ensureDirectChat`
// (`utils/direct_chat_ensure.dart`), страж `RL-direct-chat-single-flight`.
