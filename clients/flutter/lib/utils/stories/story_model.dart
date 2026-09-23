import 'package:matrix/matrix.dart';

/// Ключ кастомного поля сториса в content события.
const String storyContentKey = 'com.liza.story';

/// Текстовый блок поверх медиа. x/y - доли [0..1] от размера превью.
/// Ссылки авто-распознаются linkify по тексту.
class StoryOverlay {
  final String text;
  final double x;
  final double y;

  const StoryOverlay({required this.text, required this.x, required this.y});

  /// Масштаб координат в JSON. Matrix запрещает float в content события
  /// (Bad JSON value: float), поэтому x/y храним целыми промилле 0-10000,
  /// а в API класса оставляем удобные доли [0..1].
  static const int _coordScale = 10000;

  Map<String, Object?> toJson() => {
    'text': text,
    'x': (x * _coordScale).round(),
    'y': (y * _coordScale).round(),
  };

  static StoryOverlay? fromJson(Map<String, Object?> json) {
    final text = json.tryGet<String>('text');
    if (text == null) return null;
    return StoryOverlay(
      text: text,
      x: _readCoord(json['x']),
      y: _readCoord(json['y']),
    );
  }

  /// Читает координату. Новый формат - int промилле; старый - float доля
  /// (события, записанные до перехода на промилле).
  static double _readCoord(Object? raw) {
    if (raw is int) return raw / _coordScale;
    if (raw is double) return raw;
    if (raw is num) return raw.toDouble();
    return 0.5;
  }
}

/// Фон под медиа в кадре сториса.
/// - [cover] — медиа заполняет кадр 9:16 с обрезкой (легаси-поведение). Дефолт при
///   ОТСУТСТВИИ поля `media` в content — старые сторис рисуются как раньше.
/// - [blur] — медиа вписано целиком (contain), фон — размытая копия того же медиа
///   (механика MAX). Так публикуют новые сторис из обновлённого редактора.
enum StoryMediaBackground { cover, blur }

/// Диапазон видео-отрезка, выбранный дорожкой-скраббером (для видео длиннее
/// [storyMaxVideoMs]). На mobile отрезок вырезается физически перед публикацией;
/// на desktop/web (нет клиентского энкодера) окно едет в content, и вьюер
/// проигрывает срез `[startMs..endMs]`.
class StoryTrim {
  final int startMs;
  final int endMs;

  const StoryTrim({required this.startMs, required this.endMs});

  Map<String, Object?> toJson() => {'start_ms': startMs, 'end_ms': endMs};

  static StoryTrim? fromJson(Map<String, Object?> json) {
    final start = json.tryGet<int>('start_ms');
    final end = json.tryGet<int>('end_ms');
    if (start == null || end == null) return null;
    return StoryTrim(startMs: start, endMs: end);
  }
}

/// Параметры отображения медиа в кадре сториса: фон (cover/blur) и трансформ
/// переднего плана (пинч-зум + панорама), заданные автором и видимые зрителям.
///
/// Matrix запрещает float в content события («Bad JSON value: float»), поэтому:
/// - [scale] хранится целыми ТЫСЯЧНЫМИ от 1.0 (1000 = ×1.0, 1500 = ×1.5);
/// - [dx]/[dy] — целыми промилле [-10000..10000] от ширины/высоты РАМКИ кадра
///   (не от contain-прямоугольника медиа), знак допускается.
/// API класса оставляет удобные double: [scale] как множитель, [dx]/[dy] как доли.
class StoryMedia {
  final StoryMediaBackground background;

  /// Множитель масштаба переднего плана, [scale] >= 1.0 (1.0 — вписано целиком).
  final double scale;

  /// Смещение переднего плана как доля рамки кадра по X/Y.
  final double dx;
  final double dy;

  /// Окно видео-отрезка (для видео длиннее лимита). null — целиком/первые 60с.
  final StoryTrim? trim;

  const StoryMedia({
    this.background = StoryMediaBackground.blur,
    this.scale = 1.0,
    this.dx = 0.0,
    this.dy = 0.0,
    this.trim,
  });

  static const int _scaleUnit = 1000; // 1000 = ×1.0
  static const int _offsetScale =
      10000; // доля рамки → промилле, как у overlays

  Map<String, Object?> toJson() => {
    'bg': background == StoryMediaBackground.blur ? 'blur' : 'cover',
    'scale': (scale * _scaleUnit).round(),
    'dx': (dx * _offsetScale).round(),
    'dy': (dy * _offsetScale).round(),
    if (trim != null) 'trim': trim!.toJson(),
  };

  /// Читает `media` из content. Отсутствие поля → null (легаси-сторис, рендер
  /// cover). Значения читаются через forward-compat путь (int-промилле или
  /// старый float), как координаты оверлеев.
  static StoryMedia? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    final bg = json.tryGet<String>('bg') == 'blur'
        ? StoryMediaBackground.blur
        : StoryMediaBackground.cover;
    final trimMap = json.tryGetMap<String, Object?>('trim');
    return StoryMedia(
      background: bg,
      scale: _readScale(json['scale']),
      dx: _readOffset(json['dx']),
      dy: _readOffset(json['dy']),
      trim: trimMap == null ? null : StoryTrim.fromJson(trimMap),
    );
  }

  static double _readScale(Object? raw) {
    if (raw is int) return raw / _scaleUnit;
    if (raw is double) return raw; // старый float-множитель
    if (raw is num) return raw.toDouble() / _scaleUnit;
    return 1.0;
  }

  static double _readOffset(Object? raw) {
    if (raw is int) return raw / _offsetScale;
    if (raw is double) return raw; // старый float-доля
    if (raw is num) return raw.toDouble() / _offsetScale;
    return 0.0;
  }
}

/// Распарсенное содержимое com.liza.story.
class StoryContent {
  final int expiresTs;
  final List<StoryOverlay> overlays;
  final String? caption;

  /// Параметры отображения медиа (фон + трансформ). null — легаси-сторис без
  /// поля `media`: рендерится по-старому (BoxFit.cover), нулевой регресс.
  final StoryMedia? media;

  const StoryContent({
    required this.expiresTs,
    required this.overlays,
    this.caption,
    this.media,
  });

  Map<String, Object?> toJson() => {
    'expires_ts': expiresTs,
    if (caption != null && caption!.isNotEmpty) 'caption': caption,
    'overlays': overlays.map((o) => o.toJson()).toList(),
    if (media != null) 'media': media!.toJson(),
  };

  static StoryContent? fromContent(Map<String, Object?> content) {
    final map = content.tryGetMap<String, Object?>(storyContentKey);
    if (map == null) return null;
    final rawOverlays = ((map['overlays'] as List?) ?? [])
        .whereType<Map<String, Object?>>()
        .toList();
    return StoryContent(
      expiresTs: map.tryGet<int>('expires_ts') ?? 0,
      caption: map.tryGet<String>('caption'),
      overlays: rawOverlays
          .map(StoryOverlay.fromJson)
          .whereType<StoryOverlay>()
          .toList(),
      media: StoryMedia.fromJson(map.tryGetMap<String, Object?>('media')),
    );
  }
}

/// Сторис активен, пока now < expires_ts.
bool storyIsActive(StoryContent story, int nowMs) => nowMs < story.expiresTs;

/// Возраст сториса для оверлея автора: часы, если >= 1 ч, иначе минуты.
({int value, bool hours}) storyAge(Duration age) {
  if (age.inHours >= 1) return (value: age.inHours, hours: true);
  final minutes = age.inMinutes < 1 ? 1 : age.inMinutes;
  return (value: minutes, hours: false);
}

/// Ключ ссылки на сторис в content сообщения-карточки (reply/share).
const String storyRefKey = 'com.liza.story.ref';

/// Ссылка на сегмент сторис внутри обычного m.text-сообщения.
/// Старые клиенты видят только body (fallback), новые рендерят карточку.
class StoryRef {
  final String roomId;
  final String eventId;
  final String authorId;
  final String? thumbnailMxc;
  final int expiresTs;

  const StoryRef({
    required this.roomId,
    required this.eventId,
    required this.authorId,
    this.thumbnailMxc,
    required this.expiresTs,
  });

  Map<String, Object?> toJson() => {
    'room_id': roomId,
    'event_id': eventId,
    'author_id': authorId,
    if (thumbnailMxc != null) 'thumbnail_mxc': thumbnailMxc,
    'expires_ts': expiresTs,
  };

  static StoryRef? fromContent(Map<String, Object?> content) {
    final map = content.tryGetMap<String, Object?>(storyRefKey);
    if (map == null) return null;
    final roomId = map.tryGet<String>('room_id');
    final eventId = map.tryGet<String>('event_id');
    final authorId = map.tryGet<String>('author_id');
    if (roomId == null || eventId == null || authorId == null) return null;
    return StoryRef(
      roomId: roomId,
      eventId: eventId,
      authorId: authorId,
      thumbnailMxc: map.tryGet<String>('thumbnail_mxc'),
      expiresTs: map.tryGet<int>('expires_ts') ?? 0,
    );
  }

  /// Content сообщения-карточки: m.text с fallback body + этот ref.
  Map<String, Object?> buildMessageContent({required String body}) => {
    'msgtype': 'm.text',
    'body': body,
    storyRefKey: toJson(),
  };
}
