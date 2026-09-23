import 'package:liza/utils/pending_invite_code.dart';

/// Код приглашения, гарантированно поднятый из персиста.
///
/// Ожидание обязательно: без него рано нажатая кнопка читает ещё пустое
/// хранилище и молча теряет invite_code — сервер не вызывает
/// `register_via_invite`, и человек с ВАЛИДНОЙ ссылкой получает экран «нет
/// доступа». Особенно уязвим путь «сирота -> потом инвайт»: код там приходит
/// из персиста, а не из свежего deep-link.
///
/// Вынесено из [HomeserverPickerController] отдельной функцией, чтобы гонку
/// можно было проверять поведенчески — на реальном продакшен-коде, без
/// Matrix-клиента и виджетного дерева.
Future<String?> inviteCodeAfterRestore(Future<void> pendingRestore) async {
  await pendingRestore;
  return PendingInviteCode.current;
}
