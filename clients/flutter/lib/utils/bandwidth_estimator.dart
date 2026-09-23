/// Оценщик пропускной способности сети.
///
/// Использует EWMA (Exponentially Weighted Moving Average) — стандартный
/// алгоритм адаптивных стриминговых плееров (HLS.js, dash.js, ExoPlayer).
/// Записывает замеры реальных загрузок (media download, Range-стрим) и
/// отдаёт сглаженную оценку текущей скорости.
class BandwidthEstimator {
  static final BandwidthEstimator instance = BandwidthEstimator._();
  BandwidthEstimator._();

  /// Вес нового замера: 0.3 даёт баланс между отзывчивостью и
  /// устойчивостью к кратковременным просадкам (spike).
  static const _alpha = 0.3;

  double _ewmaBps = 0;
  int _sampleCount = 0;

  /// Минимальный размер замера — слишком короткие загрузки дают
  /// нестабильный результат из-за TCP slow start и DNS/TLS overhead.
  static const _minSampleBytes = 4096;

  /// Записать результат загрузки.
  void addSample(int bytes, Duration elapsed) {
    if (elapsed.inMilliseconds <= 0 || bytes < _minSampleBytes) return;
    final bps = bytes * 8 / elapsed.inMilliseconds * 1000;
    _ewmaBps = _ewmaBps == 0 ? bps : (_alpha * bps + (1 - _alpha) * _ewmaBps);
    _sampleCount++;
  }

  /// Оценка в bits/sec. Fallback 500 Kbps если нет замеров.
  double get estimatedBps => _ewmaBps > 0 ? _ewmaBps : 500000;

  /// Оценка в Mbps.
  double get estimatedMbps => estimatedBps / 1000000;

  /// Есть ли хотя бы один реальный замер.
  bool get hasSamples => _sampleCount > 0;

  /// Время последнего обновления — для определения необходимости
  /// повторного probe (> 5 минут без медиа-загрузок).
  DateTime _lastSampleTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime get lastSampleTime => _lastSampleTime;

  /// Расширенная версия [addSample] с таймштампом.
  void addTimedSample(int bytes, Duration elapsed) {
    addSample(bytes, elapsed);
    if (bytes >= _minSampleBytes && elapsed.inMilliseconds > 0) {
      _lastSampleTime = DateTime.now();
    }
  }

  /// Рассчитать битрейт видео из метаданных event.
  /// [fileSize] — info.size в байтах, [durationMs] — info.duration в мс.
  static double? videoBitrateMbps(int? fileSize, int? durationMs) {
    if (fileSize == null || durationMs == null || durationMs <= 0) return null;
    return (fileSize * 8) / durationMs / 1000;
  }

  /// Достаточна ли текущая скорость для комфортного стриминга видео
  /// с заданным битрейтом. Margin 1.5x — стандарт для progressive download.
  bool canStream(double videoBitrateMbps) =>
      estimatedMbps > videoBitrateMbps * 1.5;

  /// Сброс — для тестов.
  void reset() {
    _ewmaBps = 0;
    _sampleCount = 0;
    _lastSampleTime = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
