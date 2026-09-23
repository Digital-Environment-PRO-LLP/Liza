import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/utils/reply_draft_store.dart';

/// Подставить текст в композер чата, который сейчас откроется.
///
/// Контракт черновика живёт в `ChatController`: `_loadDraft` читает
/// `draft_<roomId>` в `initState`, `draftfmt_<roomId>` хранит спаны
/// форматирования той же длины, `draft_reply_<roomId>` — событие, на которое
/// отвечает черновик. Пишем только текст: старые спаны легли бы на чужую длину
/// (случайное форматирование), а живой reply отправил бы заявку ответом на
/// старое событие. Собственный недописанный текст пользователя не затираем —
/// дописываем ниже.
Future<void> writeComposerDraft(
  SharedPreferences prefs,
  String roomId,
  String text,
) async {
  final existing = prefs.getString('draft_$roomId');
  final merged = existing == null || existing.trim().isEmpty
      ? text
      : '$existing\n\n$text';
  await prefs.setString('draft_$roomId', merged);
  await prefs.remove('draftfmt_$roomId');
  await prefs.remove(ReplyDraftStore.keyFor(roomId));
}
