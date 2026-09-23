import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../utils/stories/story_model.dart';
import '../../utils/stories/story_overlay_geometry.dart';

/// Общий рендер медиа сториса для РЕДАКТОРА и ВЬЮЕРА (единый источник геометрии,
/// как у оверлеев). Слои снизу вверх:
///   [0] размытый фон — статичный постер/thumbnail того же медиа, BoxFit.cover
///       (механика MAX). НИКОГДА не второй `Video` (media_kit: один
///       VideoController — один Video в дереве).
///   [1] передний план — медиа BoxFit.contain c Transform(scale + pan).
///
/// Оверлеи и подпись рисуются ВЫШЕ этого виджета (в композере/вьюере) и якорятся
/// к РАМКЕ кадра — Transform их НЕ трогает, поэтому автор и зритель видят оверлей
/// в одной доле рамки при любом зуме.
///
/// [background] == cover (легаси) → фон не строится, медиа заполняет кадр (старое
/// поведение). Виджет размещают в `Positioned.fromRect`/`SizedBox`, он заполняет
/// свой бокс — рамкой служит его собственный размер (см. LayoutBuilder).
class StoryMediaCanvas extends StatelessWidget {
  const StoryMediaCanvas({
    required this.foreground,
    required this.background,
    required this.scale,
    required this.translation,
    required this.mediaAspect,
    this.blurBackground,
    this.blurSigma = 24,
    super.key,
  });

  /// Виджет медиа переднего плана (фото — `Image`, видео — `Video`/
  /// `EventVideoPlayer`). Должен заполнять переданный бокс (`fit: BoxFit.cover` —
  /// бокс уже в аспекте медиа, поэтому cover == contain == точное вписывание).
  final Widget foreground;

  final StoryMediaBackground background;

  /// Множитель зума и смещение (доля рамки) переднего плана.
  final double scale;
  final Offset translation;

  /// Аспект медиа (ширина/высота). null → фон не строим, медиа заполняет кадр
  /// (fallback к cover — нет данных для letterbox).
  final double? mediaAspect;

  /// Виджет-источник размытого фона (тот же кадр/постер, `fit: BoxFit.cover`):
  /// редактор — `Image(MemoryImage)`, вьюер — `MxcImage(isThumbnail)`. Канвас сам
  /// оборачивает его в блюр. null → затемнение (нет источника, напр. desktop без
  /// постера).
  final Widget? blurBackground;

  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final frame = Size(c.maxWidth, c.maxHeight);
        final aspect = mediaAspect;

        // Легаси/нет аспекта → медиа заполняет кадр как раньше (без блюра/transform).
        if (background == StoryMediaBackground.cover ||
            aspect == null ||
            aspect <= 0 ||
            frame.width <= 0 ||
            frame.height <= 0) {
          return SizedBox.expand(child: foreground);
        }

        final containRect = mediaContainRect(frame, aspect);
        // Защита от битого content чужого клиента: scale вне [1..max] или
        // не-конечный схлопнул бы медиа в точку/невидимость.
        final safeScale = (scale.isFinite && scale >= storyMinMediaScale)
            ? scale.clamp(storyMinMediaScale, storyMaxMediaScale)
            : storyMinMediaScale;
        final clamped = clampStoryTranslation(
          translation: translation,
          scale: safeScale,
          containSize: containRect.size,
          frameSize: frame,
        );
        final panPx = Offset(
          clamped.dx * frame.width,
          clamped.dy * frame.height,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            // [0] Размытый фон — статичный постер, cover, изолирован
            // RepaintBoundary (зум переднего плана его не перерисовывает).
            RepaintBoundary(
              child: blurBackground == null
                  ? const ColoredBox(color: Colors.black)
                  : ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: blurSigma,
                        sigmaY: blurSigma,
                      ),
                      child: SizedBox(
                        width: frame.width,
                        height: frame.height,
                        child: blurBackground,
                      ),
                    ),
            ),
            // Лёгкое затемнение фона, чтобы яркий блюр не «съедал» передний план.
            const Positioned.fill(child: ColoredBox(color: Colors.black26)),
            // [1] Передний план: contain-медиа + зум/пан вокруг центра кадра.
            // Порядок матрицы (применяется к точке справа налево): scale, затем
            // translate в экранных px — пан не масштабируется зумом.
            Positioned.fill(
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..translateByDouble(panPx.dx, panPx.dy, 0, 1)
                  ..scaleByDouble(safeScale, safeScale, 1, 1),
                child: Stack(
                  children: [
                    Positioned.fromRect(rect: containRect, child: foreground),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
