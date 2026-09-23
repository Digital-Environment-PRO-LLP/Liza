import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:liza/utils/user_handle_service.dart';

/// Matrix ID внутри текста: серверная часть — hostname с TLD (или IPv4) и
/// опциональный порт. Мусор вида `@user:...` и точка конца предложения
/// (`@bob:example.org.`) больше не матчатся — раньше они уходили на сервер
/// запросом профиля и получали 400 (LABA-2530).
///
/// Без lookbehind: на web Dart компилирует RegExp в JS, а Safari < 16.4 бросает
/// SyntaxError на lookbehind. Левая граница захватывается группой 1 и
/// возвращается в вывод.
final _matrixMxidRegex = RegExp(
  r'(^|[^A-Za-z0-9._%+\-])'
  r'(@[A-Za-z0-9._=/+\-]+:'
  r'(?:(?:[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,}'
  r'|\d{1,3}(?:\.\d{1,3}){3})(?::\d{1,5})?)',
);

/// Regex matching mention pills like @[Display Name]
final _matrixPillRegex = RegExp(r'@\[([^\]]+)\]');

/// Cleans up raw Matrix mentions in notification text:
/// - Replaces @user:server.com with display name, cached @handle or localpart
/// - Replaces @[Display Name] pill syntax with just the display name
///
/// Сеть не трогает никогда. `Room.unsafeGetUserFromMemoryOrFallback` на промахе
/// памяти шлёт `/state/m.room.member` + `/profile`, а функция зовётся на каждой
/// перерисовке списка чатов: плейсхолдер-mxid из сообщения BotFather давал
/// 404 + 403 и ошибку в консоли на каждой загрузке web (LABA-2530).
String stripMatrixMentions(
  String text,
  Room room, {
  UserHandleService? handles,
}) {
  var result = text.replaceAllMapped(_matrixMxidRegex, (match) {
    final mxid = match.group(2)!;
    return '${match.group(1)}${_mentionLabel(mxid, room, handles)}';
  });
  // Strip @[Name] pill syntax → just Name
  result = result.replaceAllMapped(_matrixPillRegex, (match) {
    return match.group(1)!;
  });
  return result;
}

String _mentionLabel(String mxid, Room room, UserHandleService? handles) {
  final displayName = room
      .getState(EventTypes.RoomMember, mxid)
      ?.asUser(room)
      .displayName;
  if (displayName != null && displayName.isNotEmpty) return displayName;

  // Только локальная БД: после холодного старта комнаты partial и держат
  // участников в базе, а не в памяти. Найденный попадёт в state через
  // setState, и следующая перерисовка превью покажет имя.
  if (mxid.isValidMatrixId) {
    unawaited(
      room.requestUser(
        mxid,
        requestState: false,
        requestProfile: false,
        ignoreErrors: true,
      ),
    );
  }

  final handle = handles?.cachedHandleFor(mxid);
  if (handle != null && handle.isNotEmpty) {
    return handle.startsWith('@') ? handle : '@$handle';
  }
  return mxid.localpart ?? mxid;
}
