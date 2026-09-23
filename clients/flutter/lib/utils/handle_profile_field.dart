import 'package:matrix/matrix.dart';

import 'channel_handle.dart';

/// Кастомное поле профиля Matrix, в которое дублируется публичный @-ник
/// пользователя — чтобы он приезжал ВМЕСТЕ с профилем (см. `UserHandleService`
/// в `user_handle_service.dart`, там же — почему резолв в MXID всё равно
/// идёт только через auth-proxy, а не через это поле).
const String lizaHandleField = 'ru.liza.handle';

/// Ник из кастомного поля профиля, если он там есть и валиден.
///
/// Поле пишет сам владелец аккаунта своим access token'ом — подделать его
/// может кто угодно на своём же профиле (выставить себе чужой ник или
/// `admin`). Поэтому значение ОБЯЗАНО пройти ту же проверку, что и при
/// установке ника через auth-proxy — иначе показ ника в UI можно
/// использовать для выдачи себя за другого пользователя. Правила
/// переиспользуются из [validateChannelHandle], а не дублируются.
String? handleFromProfile(ProfileInformation profile) {
  final raw = profile.additionalProperties[lizaHandleField];
  if (raw is! String) return null;
  final handle = normalizeChannelHandle(raw);
  if (handle.isEmpty) return null;
  if (validateChannelHandle(handle) != null) return null;
  return handle;
}

/// Публикует ник владельца в кастомное поле профиля `ru.liza.handle`.
///
/// Вызывается ПОСЛЕ успешной регистрации ника на auth-proxy — источник
/// истины там, это поле лишь ускоряет показ (приезжает вместе с профилем,
/// без отдельного запроса на резолв). Сбой публикации не должен ронять
/// вызывающую операцию — тот, кто дублирует ник в профиль, обязан сам
/// поймать исключение (см. `UserHandleService.setHandle`).
Future<void> publishHandle(Client client, String handle) async {
  final userId = client.userID;
  if (userId == null) return;
  await client.setProfileField(
    userId,
    lizaHandleField,
    {lizaHandleField: handle},
  );
}
