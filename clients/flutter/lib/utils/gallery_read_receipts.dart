import 'package:liza/utils/room_status_extension.dart';

/// Переносит аватарки прочтения со скрытых членов медиа-галереи на их
/// anchor-событие (единственную видимую строку альбома).
///
/// Зачем (баг iOS 2026-07-08: «отправил скрины — своя аватарка прочтения
/// моргнула и скрылась»): несколько картинок с общим `com.liza.gallery.id`
/// лента схлопывает в одну строку — anchor (минимальный `galleryIndex` = самый
/// ранний по ts), остальные члены скрыты (`SizedBox.shrink`,
/// `chat_event_list.dart`). А [RoomStatusExtension.getReadReceiptsPerMessage]
/// считает по сырому таймлайну и про схлопывание не знает: граница прочтения
/// (в т.ч. своя — под своим новейшим сообщением) садится на НОВЕЙШИЙ член
/// галереи, а это как раз скрытый не-anchor. Аватарке негде отрисоваться (её
/// eventId нет среди видимых строк), и она пропадает, пока следующее видимое
/// событие не сдвинет границу. Это структурный близнец бага с правкой
/// (m.replace тоже скрыт из ленты и «забирал» аватарку) — только для галереи.
///
/// [skipToAnchor] — eventId скрытого члена → eventId anchor (строится в
/// `chat_event_list.dart` из тех же галерейных групп, что и `gallerySkipEventIds`,
/// поэтому знание о схлопывании галереи не дублируется в двух местах).
///
/// Возвращает новую карту: receipts скрытых членов слиты в список anchor с
/// дедупом по пользователю (оставляем позднюю квитанцию — бо́льший ts) и
/// сортировкой по ts (инвариант «прочитал раньше — первым», как в
/// [RoomStatusExtension.getReadReceiptsPerMessage]). Если переносить нечего —
/// возвращает исходную карту без копирования.
Map<String, List<MessageReadReceipt>> mergeGalleryReadReceipts(
  Map<String, List<MessageReadReceipt>> perMessage,
  Map<String, String> skipToAnchor,
) {
  if (skipToAnchor.isEmpty) return perMessage;
  if (!skipToAnchor.keys.any(perMessage.containsKey)) return perMessage;

  // Копируем всё, кроме скрытых членов (их строки не рендерятся — ключи не
  // нужны). Списки, которые будем менять, тоже копируем, чтобы не мутировать
  // результат getReadReceiptsPerMessage.
  final result = <String, List<MessageReadReceipt>>{
    for (final entry in perMessage.entries)
      if (!skipToAnchor.containsKey(entry.key))
        entry.key: List.of(entry.value),
  };

  skipToAnchor.forEach((skipId, anchorId) {
    final moved = perMessage[skipId];
    if (moved == null) return;
    (result[anchorId] ??= <MessageReadReceipt>[]).addAll(moved);
  });

  for (final anchorId in skipToAnchor.values.toSet()) {
    final list = result[anchorId];
    if (list == null) continue;
    final byUser = <String, MessageReadReceipt>{};
    for (final receipt in list) {
      final cur = byUser[receipt.user.id];
      if (cur == null || receipt.ts > cur.ts) byUser[receipt.user.id] = receipt;
    }
    result[anchorId] = byUser.values.toList()
      ..sort((a, b) => a.ts.compareTo(b.ts));
  }

  return result;
}
