import 'package:shared_preferences/shared_preferences.dart';

/// Персистентность связки «отвечаю на событие» рядом с текстовым черновиком.
///
/// Без этого при переключении чата (ChatController пересоздаётся, а `replyEvent`
/// живёт только в state) текст ответа оставался в поле ввода, но сам reply
/// слетал. Ключ — по комнате, как у `draft_$roomId`.
class ReplyDraftStore {
  const ReplyDraftStore(this.prefs);

  final SharedPreferences prefs;

  static String keyFor(String roomId) => 'draft_reply_$roomId';

  /// Сохраняет `eventId` ответа; `null` — снимает черновик (ответ отменён/отправлен).
  Future<void> save(String roomId, String? eventId) {
    if (eventId == null || eventId.isEmpty) {
      return prefs.remove(keyFor(roomId));
    }
    return prefs.setString(keyFor(roomId), eventId);
  }

  Future<void> clear(String roomId) => prefs.remove(keyFor(roomId));

  /// eventId сохранённого ответа либо `null`.
  String? read(String roomId) {
    final id = prefs.getString(keyFor(roomId));
    return (id == null || id.isEmpty) ? null : id;
  }
}
