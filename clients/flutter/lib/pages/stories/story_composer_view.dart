import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../l10n/l10n.dart';
import '../../utils/stories/story_model.dart';
import '../../utils/stories/story_overlay_geometry.dart';
import 'story_composer.dart';
import 'story_media_canvas.dart';

class StoryComposerView extends StatelessWidget {
  const StoryComposerView(this.controller, {super.key});

  final StoryComposerController controller;

  // Высота, зарезервированная снизу под панель ввода (поле подписи + кнопки +
  // нижний safe-area). Изображение заканчивается над этой зоной, поэтому не
  // наезжает на панель. При многострочной подписи панель растёт вверх (поверх
  // нижнего края изображения) — приемлемо.
  static const double _panelReserve = 150;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) controller.goBackToPicker();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // Клавиатура НЕ сжимает body (resize:false): изображение фиксированной
        // высоты остаётся на месте, а поле подписи сами поднимаем над
        // клавиатурой через Positioned(bottom: viewInsets.bottom).
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          toolbarHeight: 40,
        ),
        // Раскладка: изображение СВЕРХУ (фиксированной высоты, заканчивается до
        // панели), панель ввода ПОД ним. При открытии клавиатуры панель
        // поднимается над клавиатурой, изображение остаётся на месте.
        body: Builder(
          builder: (context) {
            final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
            return Stack(
              children: [
                // Изображение СВЕРХУ, фиксированной высоты: занимает область от
                // AppBar до панели ввода (bottom: _panelReserve). НЕ зависит от
                // клавиатуры (resize:false + фиксированный bottom), поэтому при
                // наборе подписи остаётся ровно на месте — не сжимается и не
                // подлетает. Панель ввода ниже по Stack заканчивает экран.
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: _panelReserve,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final area = Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      );
                      // Кадр = область над панелью (медиа cover, без чёрных
                      // полей внутри кадра). Оверлеи — от кадра.
                      //
                      // На широком окне (ПК/веб) ширина режется под 9:16 с
                      // полями по бокам — иначе редактор растягивался на всю
                      // ширину монитора и не совпадал с кадром вьюера.
                      // Порог — по ШИРИНЕ области, не по платформе: узкое
                      // окно браузера получает мобильную раскладку.
                      final media = storyFrameRect(
                        area,
                        maxAspect: storyFrameAspect,
                      );
                      return Stack(
                        children: [
                          // Тап по изображению скрывает клавиатуру и выходит
                          // из режима набора подписи (текст сохраняется — он
                          // в captionController). GestureDetector ПОВЕРХ
                          // медиа (иначе media_kit/Video съедал бы тап), но
                          // ПОД оверлеями ниже — drag оверлеев имеет приоритет.
                          // Кадр медиа: заполнение без полей (cover, как
                          // Liza/IG/TikTok), скруглённые углы (ClipRRect).
                          // RepaintBoundary изолирует фон от перерисовки
                          // оверлеев при drag; previewImage кэшируется
                          // контроллером — нет пере-декода и мерцания.
                          Positioned.fromRect(
                            rect: media,
                            child: _MediaEditor(
                              controller: controller,
                              frame: media.size,
                            ),
                          ),
                          for (var i = 0; i < controller.overlays.length; i++)
                            Builder(
                              builder: (_) {
                                final o = controller.overlays[i];
                                final center = fractionToLocal(o.x, o.y, media);
                                return Positioned(
                                  // Якорь по ЦЕНТРУ блока через
                                  // FractionalTranslation.
                                  left: center.dx,
                                  top: center.dy,
                                  child: FractionalTranslation(
                                    translation: const Offset(-0.5, -0.5),
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.move,
                                      child: GestureDetector(
                                        onPanUpdate: (d) {
                                          final newCenter = center + d.delta;
                                          final f = localToFraction(
                                            newCenter,
                                            media,
                                          );
                                          controller.updateOverlayPosition(
                                            i,
                                            f.dx,
                                            f.dy,
                                          );
                                        },
                                        child: _OverlayChip(
                                          text: o.text,
                                          mediaWidth: media.width,
                                          onChanged: (t) =>
                                              controller.setOverlayText(i, t),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ),
                // Нижняя панель (поле подписи + кнопки). Прижата к низу и
                // поднимается над клавиатурой через bottom: keyboardInset.
                // ВАЖНО: структура панели НЕ зависит от того, открыта ли
                // клавиатура (никаких if(keyboardOpen)) — иначе перестроение в
                // момент фокуса схлопывало клавиатуру (открылась-закрылась).
                // Поле подписи ОДНО (общий FocusNode): тап по изображению
                // (captionFocus.unfocus) надёжно закрывает клавиатуру.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: keyboardInset,
                  child: Container(
                    color: Colors.black,
                    child: SafeArea(
                      top: false,
                      // Панель по ширине совпадает с кадром 9:16 (см. media
                      // выше): на широком мониторе поле подписи и кнопки не
                      // растягиваются через весь экран, а стоят под кадром.
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: _panelMaxWidth(context),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (controller.videoWasTrimmed)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 6,
                                    horizontal: 12,
                                  ),
                                  child: Text(
                                    L10n.of(context).storyVideoTrimmedToMinute,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              _CaptionField(controller: controller),
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.arrow_back,
                                        color: Colors.white,
                                      ),
                                      onPressed: controller.goBackToPicker,
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.text_fields,
                                        color: Colors.white,
                                      ),
                                      tooltip: L10n.of(context).storyAddText,
                                      onPressed: controller.addOverlay,
                                    ),
                                    const Spacer(),
                                    FilledButton.icon(
                                      onPressed: controller.canPublish
                                          ? controller.publish
                                          : null,
                                      icon: const Icon(Icons.arrow_forward),
                                      label: Text(L10n.of(context).next),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Ширина нижней панели = ширина кадра 9:16 при текущем размере окна.
  /// Считается от той же области, что и кадр (высота минус AppBar и резерв
  /// панели), поэтому панель и кадр всегда одной ширины.
  static double _panelMaxWidth(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final frameArea = Size(size.width, size.height - _panelReserve);
    return storyFrameRect(frameArea, maxAspect: storyFrameAspect).width;
  }
}

/// Редактируемое медиа сториса: блюр-фон + вписанный передний план с пинч-зумом
/// и панорамой (touch — GestureDetector.onScale; desktop/web — колесо мыши через
/// Listener). Оверлеи рисуются ВЫШЕ (в Stack родителя) и якорятся к рамке — зум их
/// не трогает. onTap снимает фокус с подписи (сосуществует с onScale; конфликта
/// нет — GestureDetector допускает tap+scale).
class _MediaEditor extends StatefulWidget {
  const _MediaEditor({required this.controller, required this.frame});

  final StoryComposerController controller;
  final Size frame;

  @override
  State<_MediaEditor> createState() => _MediaEditorState();
}

class _MediaEditorState extends State<_MediaEditor> {
  double _scaleStart = 1.0;

  StoryComposerController get c => widget.controller;

  Size get _containSize {
    final aspect = c.mediaAspect;
    if (aspect == null || aspect <= 0) return widget.frame;
    return mediaContainRect(widget.frame, aspect).size;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _scaleStart = c.mediaScale;
    c.captionFocus.unfocus();
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final frame = widget.frame;
    if (frame.width <= 0 || frame.height <= 0) return;
    final newScale = (_scaleStart * d.scale).clamp(
      storyMinMediaScale,
      storyMaxMediaScale,
    );
    final deltaFrac = Offset(
      d.focalPointDelta.dx / frame.width,
      d.focalPointDelta.dy / frame.height,
    );
    final clamped = clampStoryTranslation(
      translation: c.mediaTranslation + deltaFrac,
      scale: newScale,
      containSize: _containSize,
      frameSize: frame,
    );
    c.setMediaTransform(newScale, clamped);
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final frame = widget.frame;
    if (frame.width <= 0 || frame.height <= 0) return;
    final newScale = (c.mediaScale - e.scrollDelta.dy / 300).clamp(
      storyMinMediaScale,
      storyMaxMediaScale,
    );
    final clamped = clampStoryTranslation(
      translation: c.mediaTranslation,
      scale: newScale,
      containSize: _containSize,
      frameSize: frame,
    );
    c.setMediaTransform(newScale, clamped);
  }

  @override
  Widget build(BuildContext context) {
    final foreground = c.isVideo
        ? (c.videoController != null
              ? Video(
                  controller: c.videoController!,
                  fit: BoxFit.cover,
                  controls: NoVideoControls,
                )
              : const Center(child: CircularProgressIndicator()))
        : (c.previewImage != null
              ? Image(image: c.previewImage!, fit: BoxFit.cover)
              : const Center(
                  child: Icon(
                    Icons.image_outlined,
                    color: Colors.white54,
                    size: 64,
                  ),
                ));

    return Listener(
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: c.captionFocus.unfocus,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(storyFrameCornerRadius),
          child: StoryMediaCanvas(
            foreground: foreground,
            background: StoryMediaBackground.blur,
            scale: c.mediaScale,
            translation: c.mediaTranslation,
            mediaAspect: c.mediaAspect,
            blurBackground: c.posterImage == null
                ? null
                : Image(image: c.posterImage!, fit: BoxFit.cover),
          ),
        ),
      ),
    );
  }
}

/// Поле ввода подписи сториса. Единственное в дереве (общий focusNode),
/// поэтому тап по изображению (captionFocus.unfocus) надёжно закрывает
/// клавиатуру и выходит из режима набора; текст сохраняется в контроллере.
class _CaptionField extends StatelessWidget {
  const _CaptionField({required this.controller});

  final StoryComposerController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: controller.captionController,
        focusNode: controller.captionFocus,
        maxLines: null,
        keyboardType: TextInputType.multiline,
        textCapitalization: TextCapitalization.sentences,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: L10n.of(context).storyAddCaption,
          hintStyle: const TextStyle(color: Colors.white54),
          filled: true,
          fillColor: Colors.white12,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

class _OverlayChip extends StatelessWidget {
  const _OverlayChip({
    required this.text,
    required this.mediaWidth,
    required this.onChanged,
  });

  final String text;
  final double mediaWidth;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      // maxWidth совпадает с просмотрщиком (_OverlayLabel): 90% ширины
      // медиа-прямоугольника, чтобы перенос строк совпадал на обоих экранах.
      constraints: BoxConstraints(maxWidth: mediaWidth * 0.9),
      decoration: BoxDecoration(
        color: Colors.black45,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: IntrinsicWidth(
        child: TextFormField(
          initialValue: text,
          onChanged: onChanged,
          textAlign: TextAlign.center,
          // maxLines: null + multiline — поле растёт по высоте под текст,
          // Enter вставляет перенос строки.
          maxLines: null,
          keyboardType: TextInputType.multiline,
          textCapitalization: TextCapitalization.sentences,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
          ),
        ),
      ),
    );
  }
}
