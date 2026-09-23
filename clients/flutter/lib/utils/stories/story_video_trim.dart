/// Максимальная длина видео-сториса (Instagram-паритет — до одной минуты).
const int storyMaxVideoMs = 60000;

class TrimPlan {
  final bool needsTrim;
  final int startMs;
  final int endMs;
  const TrimPlan({
    required this.needsTrim,
    required this.startMs,
    required this.endMs,
  });
}

/// Решает, нужно ли обрезать видео и какой диапазон взять. Без выбора отрезка
/// (дорожка не двигалась) берём первые [storyMaxVideoMs] мс — см. [planTrimWindow]
/// для выбранного дорожкой окна.
TrimPlan planTrim(int durationMs) => planTrimWindow(durationMs, startMs: 0);

/// План обрезки под ВЫБРАННОЕ дорожкой окно. [startMs] — начало отрезка (может
/// быть > 0, если пользователь сдвинул дорожку). Окно всегда ровно [storyMaxVideoMs]
/// или короче, если упирается в конец видео. Границы клампятся:
/// - `startMs >= 0`;
/// - `endMs <= durationMs` (окно не выходит за конец);
/// - если после кламппинга к концу окно всё равно длиннее лимита — режем с конца.
///
/// Возвращает `needsTrim=false` только когда всё видео целиком помещается в лимит
/// И отрезок начинается с нуля (обрезать нечего).
TrimPlan planTrimWindow(int durationMs, {required int startMs}) {
  if (durationMs <= 0) {
    return const TrimPlan(needsTrim: false, startMs: 0, endMs: 0);
  }
  if (durationMs <= storyMaxVideoMs && startMs <= 0) {
    return TrimPlan(needsTrim: false, startMs: 0, endMs: durationMs);
  }
  var start = startMs < 0 ? 0 : startMs;
  // Стартовое окно не может начинаться так, чтобы вылезти за конец: если сдвинули
  // слишком вправо — прижимаем окно к концу видео.
  final maxStart = (durationMs - storyMaxVideoMs).clamp(0, durationMs);
  if (start > maxStart) start = maxStart;
  var end = start + storyMaxVideoMs;
  if (end > durationMs) end = durationMs;
  return TrimPlan(needsTrim: true, startMs: start, endMs: end);
}
