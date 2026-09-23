import 'package:matrix/matrix.dart';

/// Ссылка на конкретное сообщение (событие) в комнате — аналог Liza
/// «Copy Message Link». Формат — стандартный matrix.to:
/// `https://matrix.to/#/<roomId>/<eventId>?via=<server>`.
///
/// Такую ссылку уже умеет открывать [UrlLauncher.openMatrixToUrl] (через
/// `parseIdentifierIntoParts`) → переход в комнату с прокруткой к событию.
/// Здесь — симметричные построение и разбор, чтобы клиент мог сам показать
/// превью при вставке.
class MessageLink {
  final String roomId;
  final String eventId;

  const MessageLink({required this.roomId, required this.eventId});

  static const String _matrixToPrefix = 'https://matrix.to/#/';

  // Голая matrix.to-ссылка без пробелов; разбор делает parseIdentifierIntoParts.
  static final RegExp _urlRegExp = RegExp(r'https://matrix\.to/#/\S+');

  String url({String? via}) {
    final viaPart = (via != null && via.isNotEmpty)
        ? '?via=${Uri.encodeQueryComponent(via)}'
        : '';
    return '$_matrixToPrefix$roomId/$eventId$viaPart';
  }

  /// Разобрать одиночную matrix.to-ссылку именно на событие (room + event).
  /// Возвращает null для ссылок на комнату/пользователя без события.
  static MessageLink? tryParse(String input) {
    final parts = input.parseIdentifierIntoParts();
    if (parts == null) return null;
    final primary = parts.primaryIdentifier;
    final secondary = parts.secondaryIdentifier;
    if (secondary == null) return null;
    if (primary.sigil != '!' && primary.sigil != '#') return null;
    if (secondary.sigil != '\$') return null;
    return MessageLink(roomId: primary, eventId: secondary);
  }

  /// Найти первую ссылку-на-событие внутри произвольного текста композера.
  static MessageLink? firstFrom(String text) {
    for (final match in _urlRegExp.allMatches(text)) {
      final link = tryParse(match.group(0)!);
      if (link != null) return link;
    }
    return null;
  }

  /// Тело сообщения — это голая ссылка-на-событие и ничего больше.
  /// По такому телу получатель рендерит превью-карточку вместо сырого URL.
  static MessageLink? bareLinkFrom(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty || trimmed.contains(RegExp(r'\s'))) return null;
    return tryParse(trimmed);
  }

  @override
  bool operator ==(Object other) =>
      other is MessageLink &&
      other.roomId == roomId &&
      other.eventId == eventId;

  @override
  int get hashCode => Object.hash(roomId, eventId);
}

/// Как открыть matrix.to-ссылку на комнату/сообщение (sigil `!` или `#`).
///
/// Инвариант безопасности (LABA-2217): ссылка на сообщение — это не
/// приглашение. Не-участник, открывший `!roomId`, не должен получать
/// предложение вступить в чат (наши ЧАТЫ invite-only, `joinRoom` постороннего
/// всё равно = `M_FORBIDDEN`) — он должен видеть честный информационный экран.
///
/// Peek тут ни при чём: он работает только для открытых КАНАЛОВ
/// (`history_visibility: world_readable`, см. `utils/channel_peek.dart`), и
/// вход в них идёт своей веткой — `ChatPage` пробует `ChannelPeekPage`.
/// Обычный чат по-прежнему не показать не-участнику.
enum MatrixToOpenAction {
  /// Комната есть локально (участник или приглашённый) — открыть её.
  openRoom,

  /// `#alias`, которого нет локально, — показать превью из room directory
  /// (вступление возможно только для реально публичных/knock-комнат).
  publicPreview,

  /// `!roomId` у не-участника — информационный экран без предложения вступить.
  notMemberInfo,
}

/// Чистое решение о поведении при открытии matrix.to-ссылки на комнату.
/// Вынесено из [UrlLauncher.openMatrixToUrl] ради тестируемости инварианта
/// LABA-2217 (см. [MatrixToOpenAction]).
MatrixToOpenAction matrixToOpenAction({
  required bool roomKnownLocally,
  required String? sigil,
}) {
  if (roomKnownLocally) return MatrixToOpenAction.openRoom;
  return sigil == '#'
      ? MatrixToOpenAction.publicPreview
      : MatrixToOpenAction.notMemberInfo;
}

/// go_router-путь к комнате, опционально со скроллом к событию.
///
/// Общий для перехода из message-link ([UrlLauncher.openMatrixToUrl]) и после
/// входа в `PublicRoomDialog`: одинаковое Uri-энкоженное построение вместо
/// строковой склейки — иначе `:`/`$` в `eventId` ломают маршрут.
String roomEventPath(String roomId, [String? eventId]) => eventId == null
    ? '/rooms/$roomId'
    : '/${Uri(pathSegments: ['rooms', roomId], queryParameters: {'event': eventId})}';
