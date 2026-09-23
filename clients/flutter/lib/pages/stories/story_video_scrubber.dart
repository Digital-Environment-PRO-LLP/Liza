import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../utils/stories/story_video_picker.dart';
import '../../utils/stories/story_video_trim.dart';

/// Дорожка выбора отрезка для видео длиннее [storyMaxVideoMs] (Instagram-механика:
/// внизу филмстрип, сверху окно ровно на минуту, которое можно двигать). Возвращает
/// через Navigator выбранный `startMs` (int) или null при отмене.
///
/// Mobile — филмстрип из реальных кадров (VideoCompress, последовательно). Desktop/
/// web — временная шкала без кадров (клиентского энкодера нет; окно едет
/// метаданными, см. `prepareStoryVideo`).
class StoryVideoScrubber extends StatefulWidget {
  const StoryVideoScrubber({
    required this.path,
    required this.durationMs,
    super.key,
  });

  final String path;
  final int durationMs;

  @override
  State<StoryVideoScrubber> createState() => _StoryVideoScrubberState();
}

class _StoryVideoScrubberState extends State<StoryVideoScrubber> {
  static const int _frameCount = 10;

  final List<Uint8List?> _frames = List.filled(_frameCount, null);
  bool _disposed = false;

  /// Начало выбранного окна как доля [0..1] от длительности.
  double _startFraction = 0;

  /// Ширина окна как доля длительности (ровно [storyMaxVideoMs]).
  double get _windowFraction =>
      (storyMaxVideoMs / widget.durationMs).clamp(0.0, 1.0);

  @override
  void initState() {
    super.initState();
    _loadFrames();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _loadFrames() async {
    // Последовательно (VideoCompress — singleton, параллельный вызов ломается).
    for (var i = 0; i < _frameCount; i++) {
      if (_disposed) return;
      final positionMs = (widget.durationMs * (i + 0.5) / _frameCount).round();
      final bytes = await storyVideoFrameAt(widget.path, positionMs);
      if (_disposed) return;
      if (bytes != null) setState(() => _frames[i] = bytes);
    }
  }

  int get _startMs => (_startFraction * widget.durationMs).round();

  void _onWindowDrag(double dxFraction) {
    if (!dxFraction.isFinite) return; // trackWidth≤0 дал бы NaN — не двигаем
    final maxStart = 1.0 - _windowFraction;
    setState(() {
      _startFraction = (_startFraction + dxFraction).clamp(0.0, maxStart);
    });
  }

  String _fmt(int ms) {
    final total = ms ~/ 1000;
    final m = total ~/ 60;
    final s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.storyPickVideoSegment),
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              l10n.storyVideoSegmentHint,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, c) {
              final trackWidth = (c.maxWidth - 32).clamp(1.0, double.infinity);
              final windowW = trackWidth * _windowFraction;
              final windowLeft = trackWidth * _startFraction;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: 72,
                  child: Stack(
                    children: [
                      // Филмстрип
                      Row(
                        children: [
                          for (var i = 0; i < _frameCount; i++)
                            Expanded(
                              child: _frames[i] == null
                                  ? const ColoredBox(color: Colors.white10)
                                  : Image.memory(
                                      _frames[i]!,
                                      fit: BoxFit.cover,
                                      height: 72,
                                    ),
                            ),
                        ],
                      ),
                      // Затемнение вне окна
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: windowLeft,
                        child: const ColoredBox(color: Colors.black54),
                      ),
                      Positioned(
                        left: windowLeft + windowW,
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: const ColoredBox(color: Colors.black54),
                      ),
                      // Окно 60с (перетаскиваемое)
                      Positioned(
                        left: windowLeft,
                        top: 0,
                        bottom: 0,
                        width: windowW,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragUpdate: (d) =>
                              _onWindowDrag(d.delta.dx / trackWidth),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            '${_fmt(_startMs)} – ${_fmt(_startMs + storyMaxVideoMs)}',
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.cancel),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(_startMs),
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(l10n.next),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
