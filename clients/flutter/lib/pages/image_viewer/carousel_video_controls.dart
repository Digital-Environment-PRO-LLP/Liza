import 'dart:async';

import 'package:flutter/material.dart';

import 'package:media_kit/media_kit.dart';

/// Форматирует позицию/длительность видео: `m:ss` либо `h:mm:ss`.
String formatVideoPosition(Duration d) {
  if (d < Duration.zero) d = Duration.zero;
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  final seconds = d.inSeconds.remainder(60);
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final mm = minutes.toString().padLeft(2, '0');
    return '$hours:$mm:$ss';
  }
  return '$minutes:$ss';
}

/// Кастомные контролы видео для карусели просмотрщика
/// (`image_viewer/video_player.dart`).
///
/// Почему не `AdaptiveVideoControls` из media_kit: его `MaterialVideoControls`
/// вешает на весь кадр `GestureDetector` с безусловным `onVerticalDragUpdate`
/// (яркость/громкость). Этот распознаватель — глубже в дереве, чем
/// вертикальный `PageView` карусели, и всегда выигрывает gesture-арену →
/// пользователь «застревает» на видео, свайп вверх/вниз не листает
/// (`plans/media-v-format.md` §8.9).
///
/// Здесь на поверхности кадра — только `onTap` (показать/скрыть контролы).
/// Tap-распознаватель не конкурирует с вертикальным drag: на свайпе он
/// проигрывает, и жест уходит в `PageView`. Перемотка — `Slider` в нижней
/// полосе, его горизонтальный drag локален и вертикальной оси `PageView`
/// не мешает.
class CarouselVideoControls extends StatefulWidget {
  final Player player;

  const CarouselVideoControls(this.player, {super.key});

  @override
  State<CarouselVideoControls> createState() => _CarouselVideoControlsState();
}

class _CarouselVideoControlsState extends State<CarouselVideoControls> {
  static const _autoHide = Duration(seconds: 3);
  static const _textShadows = [
    Shadow(blurRadius: 4, color: Colors.black54),
    Shadow(blurRadius: 8, color: Colors.black38),
  ];

  static const _speedSteps = [1.0, 1.25, 1.5, 2.0, 0.5];

  bool _visible = true;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _bufferPosition = Duration.zero;
  double _rate = 1.0;

  /// Позиция в мс, пока пользователь тащит `Slider`. `null` — не тащит.
  double? _dragValue;

  Timer? _hideTimer;
  final _subs = <StreamSubscription<dynamic>>[];

  @override
  void initState() {
    super.initState();
    final player = widget.player;
    _playing = player.state.playing;
    _position = player.state.position;
    _duration = player.state.duration;
    _bufferPosition = player.state.buffer;
    _subs.add(
      player.stream.playing.listen((value) {
        if (!mounted) return;
        setState(() => _playing = value);
        if (value) {
          _scheduleHide();
        } else {
          _hideTimer?.cancel();
        }
      }),
    );
    _subs.add(
      player.stream.position.listen((value) {
        if (mounted) setState(() => _position = value);
      }),
    );
    _subs.add(
      player.stream.duration.listen((value) {
        if (mounted) setState(() => _duration = value);
      }),
    );
    _subs.add(
      player.stream.buffer.listen((value) {
        if (mounted) setState(() => _bufferPosition = value);
      }),
    );
    _subs.add(
      player.stream.rate.listen((value) {
        if (mounted) setState(() => _rate = value);
      }),
    );
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  /// Прячет контролы через [_autoHide] — но только при проигрывании.
  /// На паузе контролы держим видимыми.
  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_playing) return;
    _hideTimer = Timer(_autoHide, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  void _toggleVisible() {
    setState(() => _visible = !_visible);
    if (_visible) _scheduleHide();
  }

  void _togglePlay() {
    widget.player.playOrPause();
    setState(() => _visible = true);
    _scheduleHide();
  }

  void _cycleSpeed() {
    final idx = _speedSteps.indexOf(_rate);
    final next = _speedSteps[(idx + 1) % _speedSteps.length];
    widget.player.setRate(next);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final durationMs = _duration.inMilliseconds;
    final hasDuration = durationMs > 0;
    final sliderMax = hasDuration ? durationMs.toDouble() : 1.0;
    final sliderValue = (_dragValue ?? _position.inMilliseconds.toDouble())
        .clamp(0.0, sliderMax);
    final bufferFraction = hasDuration
        ? (_bufferPosition.inMilliseconds / durationMs).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      // Только onTap, без drag-распознавателя → вертикальный свайп
      // уходит в PageView карусели (см. doc-комментарий класса).
      behavior: HitTestBehavior.opaque,
      onTap: _toggleVisible,
      child: Column(
        children: [
          // Центральная область: play/pause + буферинг.
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Индикатора буферизации здесь НЕТ намеренно: он живёт в
                // `EventVideoPlayer` (по mpv-property `paused-for-cache`, тот же
                // источник, что кормит детекторы затыка) и пинуется
                // `AC:RL-video-viewer-save-and-overlay/4`. Раньше спиннер
                // рисовался и тут — по собственной подписке на сигнал
                // буферизации media_kit — и на одном затыке пользователь видел
                // ДВА индикатора разом: тот же класс
                // «две поверхности на один факт», что и две ошибки в LABA-2557,
                // только про загрузку. Заодно кнопка play/pause больше не
                // исчезает на буферизации: раньше её гейтил `!_buffering`, и
                // поставить паузу во время затыка было физически нечем.
                AnimatedOpacity(
                  opacity: _visible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 150),
                  child: IgnorePointer(
                    ignoring: !_visible,
                    child: GestureDetector(
                      onTap: _togglePlay,
                      child: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 56,
                        color: Colors.white,
                        shadows: const [
                          Shadow(blurRadius: 12, color: Colors.black54),
                          Shadow(blurRadius: 24, color: Colors.black38),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Seek bar — всегда внизу Column.
          AnimatedOpacity(
            opacity: _visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: IgnorePointer(
              ignoring: !_visible,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                    children: [
                      Text(
                        formatVideoPosition(
                          Duration(milliseconds: sliderValue.round()),
                        ),
                        style: const TextStyle(
                          color: Colors.white,
                          shadows: _textShadows,
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 2.0,
                            trackShape: _BufferedTrackShape(
                              bufferFraction: bufferFraction,
                            ),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white.withAlpha(40),
                            thumbColor: Colors.white,
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6.0,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 14.0,
                            ),
                            overlayColor: Colors.white.withAlpha(40),
                          ),
                          child: Slider(
                            value: sliderValue,
                            max: sliderMax,
                            onChanged: hasDuration
                                ? (value) {
                                    setState(() => _dragValue = value);
                                    _hideTimer?.cancel();
                                  }
                                : null,
                            onChangeEnd: hasDuration
                                ? (value) {
                                    widget.player.seek(
                                      Duration(milliseconds: value.round()),
                                    );
                                    setState(() => _dragValue = null);
                                    _scheduleHide();
                                  }
                                : null,
                          ),
                        ),
                      ),
                      Text(
                        formatVideoPosition(_duration),
                        style: const TextStyle(
                          color: Colors.white,
                          shadows: _textShadows,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _cycleSpeed,
                        child: SizedBox(
                          width: 44,
                          height: 44,
                          child: Center(
                            child: Text(
                              '${_rate == _rate.roundToDouble() ? _rate.toInt() : _rate}x',
                              style: TextStyle(
                                color: _rate == 1.0
                                    ? Colors.white
                                    : Colors.amber,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                shadows: _textShadows,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Seek bar с тремя зонами: active (просмотрено), buffered (загружено),
/// inactive (не загружено). Аналог YouTube/Liza seek bar.
class _BufferedTrackShape extends RoundedRectSliderTrackShape {
  final double bufferFraction;

  const _BufferedTrackShape({required this.bufferFraction});

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 2.0;
    final trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final canvas = context.canvas;
    final radius = Radius.circular(trackHeight / 2);
    final rrect = RRect.fromRectAndRadius(trackRect, radius);

    // 1. Inactive (не загружено) — тёмный
    canvas.drawRRect(
      rrect,
      Paint()..color = sliderTheme.inactiveTrackColor ?? Colors.white24,
    );

    // 2. Buffered (загружено) — полупрозрачный белый
    if (bufferFraction > 0) {
      final bufferWidth = trackRect.width * bufferFraction;
      final bufferRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          trackRect.left,
          trackRect.top,
          bufferWidth,
          trackRect.height,
        ),
        radius,
      );
      canvas.drawRRect(
        bufferRect,
        Paint()..color = Colors.white.withAlpha(100),
      );
    }

    // 3. Active (просмотрено) — яркий белый
    final activeWidth = thumbCenter.dx - trackRect.left;
    if (activeWidth > 0) {
      final activeRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          trackRect.left,
          trackRect.top,
          activeWidth,
          trackRect.height,
        ),
        radius,
      );
      canvas.drawRRect(
        activeRect,
        Paint()..color = sliderTheme.activeTrackColor ?? Colors.white,
      );
    }
  }
}
