import 'package:matrix/matrix.dart';

import 'package:liza/utils/user_handle_service.dart';

/// Что показать человеку вместо технического адреса.
///
/// Синхронна и не ходит в сеть НАМЕРЕННО: её зовут из `build()` списков на
/// сотни строк. Ник берётся из клиентского кэша (наполняется резолвом,
/// открытием профиля и установкой своего ника через [UserHandleService]);
/// там, где ника нет — показываем MXID, ровно как до фичи.
///
/// [handle] — необязательный ник, если он уже есть на руках у вызывающей
/// стороны (например, из низкоуровневого `ProfileInformation`, который
/// кастомное поле `ru.liza.handle` сохраняет — см. `handle_profile_field.dart`).
/// Специально идти за профилем ради ника НЕ нужно: `Profile`, которым
/// пользуются экраны через `client.getProfileFromUserId`, это поле теряет.
String userIdentifier(
  String mxid, {
  required UserHandleService handles,
  String? handle,
}) {
  final resolved = handle ?? handles.cachedHandleFor(mxid);
  return resolved == null ? mxid : '@$resolved';
}

/// Заголовок и буква-фоллбэк аватара для карточки/строки результата поиска
/// людей (главный экран, «Пригласить в группу», «Новый личный чат», диалог
/// пользователя).
///
/// Приоритет: имя из профиля → `@ник` из кэша → localpart → [unknown].
/// Технический localpart (`user_<hex8>`, генерирует auth-proxy) показывается
/// ТОЛЬКО когда неизвестны ни имя, ни ник — до этого фикса он стоял вторым и
/// человек, найденный по нику, выглядел как `user_f86a7e57` (LABA-2552).
/// Для аватара ник отдаётся без сигила — иначе буквой становилось бы `@`.
///
/// Синхронна и не ходит в сеть — как [userIdentifier]: зовётся из `build()`.
/// Не строится через `displayName ?? userIdentifier(...) ?? localpart`:
/// [userIdentifier] non-null и без ника отдаёт ПОЛНЫЙ MXID — правая часть
/// была бы мёртвым кодом, а карточка получила бы длинный адрес вместо
/// короткого localpart.
({String title, String avatarName}) searchResultLabel(
  Profile profile, {
  required UserHandleService handles,
  required String unknown,
}) {
  final name = profile.displayName;
  final hasName = name != null && name.isNotEmpty;
  final handle = handles.cachedHandleFor(profile.userId);
  final localpart = profile.userId.localpart;
  return (
    title: hasName
        ? name
        : handle != null
            ? '@$handle'
            : localpart ?? unknown,
    avatarName: hasName ? name : handle ?? localpart ?? unknown,
  );
}
