/// Отображаемое имя элемента иерархии пространства.
///
/// У DM нет `m.room.name` — имя вычисляется из собеседника, поэтому перед
/// фолбэком на «Пустой чат» спрашиваем клиент об известной комнате. Без этого
/// любой DM без сообщений показывался как «Пустой чат».
String hierarchyDisplayname({
  required String? itemName,
  required String? canonicalAlias,
  required String? knownRoomDisplayname,
  required String emptyChatFallback,
}) {
  if (itemName != null && itemName.isNotEmpty) return itemName;
  if (canonicalAlias != null && canonicalAlias.isNotEmpty) return canonicalAlias;
  if (knownRoomDisplayname != null && knownRoomDisplayname.isNotEmpty) {
    return knownRoomDisplayname;
  }
  return emptyChatFallback;
}
