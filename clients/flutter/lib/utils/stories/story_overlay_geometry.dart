import 'dart:math' as math;
import 'dart:ui';

/// Радиус скругления углов кадра сториса. Общий для редактора и просмотра,
/// чтобы рамка выглядела одинаково.
const double storyFrameCornerRadius = 16;

/// Границы пинч-зума переднего плана медиа сториса. 1.0 — медиа вписано целиком
/// (contain); дальше можно только приближать. Верхний предел бережёт от ухода в
/// «пиксельную кашу».
const double storyMinMediaScale = 1.0;
const double storyMaxMediaScale = 4.0;

/// Клампит смещение (панораму) переднего плана так, чтобы масштабированное
/// contain-медиа не открывало пустоту у краёв кадра.
///
/// [translation] — смещение как доля РАМКИ кадра по X/Y (то, что хранится в
/// content как `media.dx/dy`). [scale] — множитель зума. [containSize] — размер
/// вписанного (letterbox) медиа в пикселях (см. [mediaContainRect]). [frameSize] —
/// размер рамки кадра.
///
/// При `scale == 1` (или медиа меньше рамки) допустимое смещение = 0 → передний
/// план заперт по центру (панорамировать нечего, вокруг блюр-фон). При `scale > 1`
/// диапазон = половина перехлёста `(scaledSize - frame)/2`, нормированная на рамку.
Offset clampStoryTranslation({
  required Offset translation,
  required double scale,
  required Size containSize,
  required Size frameSize,
}) {
  if (frameSize.width <= 0 || frameSize.height <= 0) return Offset.zero;
  final scaledW = containSize.width * scale;
  final scaledH = containSize.height * scale;
  final maxX = math.max(0.0, (scaledW - frameSize.width) / 2) / frameSize.width;
  final maxY =
      math.max(0.0, (scaledH - frameSize.height) / 2) / frameSize.height;
  return Offset(
    translation.dx.clamp(-maxX, maxX),
    translation.dy.clamp(-maxY, maxY),
  );
}

/// Соотношение сторон кадра просмотра сториса (ширина/высота) — вертикальные
/// 9:16, как в Liza/Instagram/TikTok.
const double storyFrameAspect = 9 / 16;

/// Прямоугольник медиа внутри [area] при BoxFit.contain (letterbox).
/// [mediaAspect] = ширина/высота медиа. <=0 → медиа заполняет всю область.
Rect mediaContainRect(Size area, double mediaAspect) {
  if (mediaAspect <= 0 || area.width <= 0 || area.height <= 0) {
    return Offset.zero & area;
  }
  final areaAspect = area.width / area.height;
  double w, h;
  if (areaAspect > mediaAspect) {
    // область шире медиа → высота по области, ширина уже (по бокам поля)
    h = area.height;
    w = h * mediaAspect;
  } else {
    w = area.width;
    h = w / mediaAspect;
  }
  final left = (area.width - w) / 2;
  final top = (area.height - h) / 2;
  return Rect.fromLTWH(left, top, w, h);
}

/// Кадр РЕДАКТОРА сториса внутри доступной области [area] (медиа cover, без
/// чёрных полей внутри кадра). Оверлеи позиционируются от него.
///
/// [maxAspect] (ширина/высота) ограничивает ширину кадра — та же семантика,
/// что у [storyViewerMediaRect]: на широком desktop/web-окне ширина режется
/// под [maxAspect] и кадр центрируется по горизонтали, высота остаётся полной.
/// На узкой области (уже [maxAspect]) ограничение не срабатывает — ширина
/// полная, как на мобильном. null — без ограничения (мобильный дефолт).
///
/// Ограничение задаётся ПО ШИРИНЕ ОБЛАСТИ, а не по платформе: узкое окно
/// браузера на ПК получает мобильную раскладку, а планшет в ландшафте — поля.
/// Аспект общий с вьюером ([storyFrameAspect]), поэтому автор в редакторе
/// видит ту же пропорцию кадра, что и зритель — оверлеи не «едут».
Rect storyFrameRect(Size area, {double? maxAspect}) {
  if (area.width <= 0 || area.height <= 0) return Offset.zero & area;
  if (maxAspect == null || maxAspect <= 0) return Offset.zero & area;
  final constrained = area.height * maxAspect;
  if (constrained >= area.width) return Offset.zero & area;
  return Rect.fromLTWH(
    (area.width - constrained) / 2,
    0,
    constrained,
    area.height,
  );
}

/// Кадр ПРОСМОТРА сториса = вертикальный 9:16, вписанный по центру [area]
/// (contain по аспекту 9:16). На экране выше 9:16 — небольшие поля сверху/снизу;
/// шире — поля по бокам. Медиа внутри кадра рисуется BoxFit.cover +
/// Alignment.center, углы скруглены (ClipRRect). Оверлеи/подпись — от кадра.
Rect storyViewerFrameRect(Size area) {
  if (area.width <= 0 || area.height <= 0) return Offset.zero & area;
  return mediaContainRect(area, storyFrameAspect);
}

/// Доля [0..1] → точка центра блока в локальных координатах области.
Offset fractionToLocal(double x, double y, Rect media) =>
    Offset(media.left + x * media.width, media.top + y * media.height);

/// Локальная точка → доля [0..1] (clamped). Обратное к [fractionToLocal].
Offset localToFraction(Offset local, Rect media) {
  final dx = media.width == 0 ? 0.0 : (local.dx - media.left) / media.width;
  final dy = media.height == 0 ? 0.0 : (local.dy - media.top) / media.height;
  return Offset(dx.clamp(0.0, 1.0), dy.clamp(0.0, 1.0));
}

/// Три вертикальные зоны вьюера сториса (как Liza/IG): верхняя панель (прогресс+
/// автор), медиа (остаток, BoxFit.cover без чёрных полей), нижняя панель
/// (статистика/ответ, забронирована). Все зоны во всю ширину [area].
class StoryZones {
  final Rect top;
  final Rect media;
  final Rect bottom;
  const StoryZones({
    required this.top,
    required this.media,
    required this.bottom,
  });
}

/// Делит [area] по вертикали. Верхняя панель высотой [topInset]+[topPanelHeight]
/// (topInset это системный вырез), нижняя [bottomPanelHeight], медиа остаток
/// (>= 0, не уходит в минус на крошечном экране).
StoryZones storyViewerZones(
  Size area, {
  required double topInset,
  required double topPanelHeight,
  required double bottomPanelHeight,
}) {
  final w = area.width;
  final topH = topInset + topPanelHeight;
  final mediaH = (area.height - topH - bottomPanelHeight).clamp(
    0.0,
    double.infinity,
  );
  return StoryZones(
    top: Rect.fromLTWH(0, 0, w, topH),
    media: Rect.fromLTWH(0, topH, w, mediaH),
    bottom: Rect.fromLTWH(0, topH + mediaH, w, bottomPanelHeight),
  );
}

/// Небольшой зазор снизу под медиа-кадром (сверх системного safe-area), чтобы
/// последняя строка подписи/инпут не прилипали к самому краю экрана.
const double storyViewerBottomGap = 8;

/// Прямоугольник медиа вьюера сториса: почти весь экран (как Liza/IG). Сверху
/// начинается под системным вырезом ([topInset]), снизу оставляет safe-area
/// ([bottomInset]) плюс небольшой зазор [storyViewerBottomGap]. Таймлайн и
/// автор рисуются оверлеями ПОВЕРХ верха медиа. Нижняя панель (инпут ответа у
/// чужих сторис, статистика у своих) НЕ поверх медиа: под неё резервируется
/// [bottomPanelHeight] в чёрной зоне ПОД медиа (медиа заканчивается выше).
/// Высота clamp >= 0 (крошечный экран не даёт минус).
///
/// [maxAspect] (ширина/высота) ограничивает ширину кадра: если область шире
/// этого аспекта (широкое desktop/web-окно), ширина режется под [maxAspect] и
/// кадр центрируется по горизонтали (letterbox по бокам), высота остаётся на
/// весь экран. На узком мобильном (область уже [maxAspect]) ограничение не
/// срабатывает — ширина остаётся полной. null — без ограничения (мобильный
/// дефолт, во всю ширину).
Rect storyViewerMediaRect(
  Size area, {
  required double topInset,
  required double bottomInset,
  double bottomPanelHeight = 0,
  double? maxAspect,
}) {
  final top = topInset;
  final h =
      (area.height -
              top -
              bottomInset -
              storyViewerBottomGap -
              bottomPanelHeight)
          .clamp(0.0, double.infinity);
  var w = area.width;
  var left = 0.0;
  if (maxAspect != null && maxAspect > 0 && h > 0) {
    final constrained = h * maxAspect;
    if (constrained < w) {
      w = constrained;
      left = (area.width - w) / 2;
    }
  }
  return Rect.fromLTWH(left, top, w, h);
}
