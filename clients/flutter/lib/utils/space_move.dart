import 'package:matrix/matrix.dart';

/// Перенести чат [roomId] из пространства [from] в пространство [to].
///
/// Порядок значим: сначала добавляем в новое, потом снимаем из старого — при
/// обрыве между шагами чат остаётся виден хотя бы в одном пространстве, а не
/// исчезает из обоих.
///
/// Вынесено из `space_view.dart` (LABA-2539): там инлайн-обработчик слал
/// `to.setSpaceChild(to.id)` — добавлял пространство в САМО СЕБЯ вместо чата,
/// после чего `from.removeSpaceChild(roomId)` выкидывал чат из старого, и он
/// пропадал из иерархии вовсе. Self-ребро вдобавок ломает определение
/// главного пространства на сервере: `single_space_guard` считает root-space'ом
/// space без входящего `m.space.child` (`__init__.py` `_find_main_root_space_txn`),
/// а пространство со ссылкой на себя перестаёт им быть.
///
/// `space_view` в widget-тесте не поднимается (общий гэп с
/// `RL-delete-company-via-support`), поэтому логика живёт здесь и стережётся
/// юнит-тестом по фактически вызванным эндпоинтам.
Future<void> moveRoomToSpace({
  required Room from,
  required Room to,
  required String roomId,
}) async {
  await to.setSpaceChild(roomId);
  await from.removeSpaceChild(roomId);
}
