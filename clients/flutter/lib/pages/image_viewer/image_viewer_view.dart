import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/image_viewer/video_player.dart';
import 'package:liza/utils/platform_infos.dart';
import 'package:liza/utils/secure_screen.dart';
import 'package:liza/widgets/hover_builder.dart';
import 'package:liza/widgets/mxc_image.dart';
import 'image_viewer.dart';

class ImageViewerView extends StatelessWidget {
  final ImageViewerController controller;

  const ImageViewerView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final iconButtonStyle = IconButton.styleFrom(
      backgroundColor: Colors.black.withAlpha(200),
      foregroundColor: Colors.white,
    );
    // Просмотрщик открывается ПОВЕРХ ленты канала, у которой страж уже стоит.
    // Свой страж всё равно нужен: сюда попадают и из поиска, и из галереи, где
    // ленты канала под нами нет. Двойного включения не будет — стражи
    // считаются, платформу дёргает только первый и последний.
    return SecureScreenGuard(
      enabled: controller.isContentProtected,
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: Scaffold(
          backgroundColor: Colors.black.withAlpha(128),
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            elevation: 0,
            leading: IconButton(
              style: iconButtonStyle,
              icon: const Icon(Icons.close),
              onPressed: Navigator.of(context).pop,
              color: Colors.white,
              tooltip: L10n.of(context).close,
            ),
            backgroundColor: Colors.transparent,
            actions: [
              // В защищённом канале кнопки выноса контента (переслать, скачать,
              // поделиться) не рисуем — смотреть медиа можно, сохранять нельзя.
              if (!controller.isContentProtected) ...[
                IconButton(
                  style: iconButtonStyle,
                  icon: const Icon(Icons.reply_outlined),
                  onPressed: controller.forwardAction,
                  color: Colors.white,
                  tooltip: L10n.of(context).share,
                ),
                const SizedBox(width: 8),
                IconButton(
                  style: iconButtonStyle,
                  icon: const Icon(Icons.download_outlined),
                  onPressed: () => controller.saveFileAction(context),
                  color: Colors.white,
                  tooltip: L10n.of(context).downloadFile,
                ),
                const SizedBox(width: 8),
              ],
              if (PlatformInfos.isMobile && !controller.isContentProtected)
                // Use builder context to correctly position the share dialog on iPad
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Builder(
                    builder: (context) => IconButton(
                      style: iconButtonStyle,
                      onPressed: () => controller.shareFileAction(context),
                      tooltip: L10n.of(context).share,
                      color: Colors.white,
                      icon: Icon(Icons.adaptive.share_outlined),
                    ),
                  ),
                ),
            ],
          ),
          body: HoverBuilder(
            builder: (context, hovered) => Stack(
              children: [
                KeyboardListener(
                  focusNode: controller.focusNode,
                  onKeyEvent: controller.onKeyEvent,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: controller.isZoomed,
                    builder: (context, zoomed, _) => PageView.builder(
                      scrollDirection: Axis.vertical,
                      physics: zoomed
                          ? const NeverScrollableScrollPhysics()
                          : const ClampingScrollPhysics(),
                      controller: controller.pageController,
                      onPageChanged: controller.onPageChanged,
                      itemCount: controller.allEvents.length,
                      itemBuilder: (context, i) {
                        final event = controller.allEvents[i];
                        switch (event.messageType) {
                          case MessageTypes.Video:
                            return Padding(
                              padding: const EdgeInsets.only(top: 52.0),
                              child: GestureDetector(
                                // Ignore taps to not go back here:
                                onTap: () {},
                                child: EventVideoPlayer(
                                  event,
                                  isActive: i == controller.activeIndex,
                                ),
                              ),
                            );
                          case MessageTypes.Image:
                          case MessageTypes.Sticker:
                          default:
                            return _ZoomableImage(
                              event: event,
                              isZoomed: controller.isZoomed,
                              onInteractionEnd: controller.onInteractionEnds,
                            );
                        }
                      },
                    ),
                  ),
                ),
                // Стрелки навигации — для desktop (показ по hover). На тач
                // листание делает свайп вверх/вниз, в т.ч. на странице видео
                // (media-v-format.md §8.9).
                if (hovered)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      mainAxisSize: .min,
                      children: [
                        if (controller.canGoBack)
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: IconButton(
                              style: iconButtonStyle,
                              tooltip: L10n.of(context).previous,
                              icon: const Icon(Icons.arrow_upward_outlined),
                              onPressed: controller.prevImage,
                            ),
                          ),
                        if (controller.canGoNext)
                          Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: IconButton(
                              style: iconButtonStyle,
                              tooltip: L10n.of(context).next,
                              icon: const Icon(Icons.arrow_downward_outlined),
                              onPressed: controller.nextImage,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Изображение с pinch-to-zoom и double-tap-to-zoom.
///
/// При scale == 1.0 — свайп PageView работает свободно (перелистывание
/// карусели). При scale > 1.0 — PageView заблокирован, InteractiveViewer
/// панит внутри увеличенного изображения. Паттерн Liza/WhatsApp/Signal.
class _ZoomableImage extends StatefulWidget {
  final Event event;
  final ValueNotifier<bool> isZoomed;
  final void Function(ScaleEndDetails) onInteractionEnd;

  const _ZoomableImage({
    required this.event,
    required this.isZoomed,
    required this.onInteractionEnd,
  });

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();
  late final AnimationController _animController;
  Animation<Matrix4>? _zoomAnimation;

  static const double _doubleTapScale = 3.0;
  static const double _zoomThreshold = 1.01;

  TapDownDetails? _lastTapDown;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(_onAnimTick);
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    _animController
      ..removeListener(_onAnimTick)
      ..dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final scale = _transformController.value.getMaxScaleOnAxis();
    final zoomed = scale > _zoomThreshold;
    if (widget.isZoomed.value != zoomed) {
      widget.isZoomed.value = zoomed;
    }
  }

  void _onAnimTick() {
    final anim = _zoomAnimation;
    if (anim == null) return;
    _transformController.value = anim.value;
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _lastTapDown = details;
  }

  void _onDoubleTap() {
    final position = _lastTapDown?.localPosition ?? Offset.zero;
    final currentScale = _transformController.value.getMaxScaleOnAxis();

    final Matrix4 target;
    if (currentScale > _zoomThreshold) {
      target = Matrix4.identity();
    } else {
      final dx = -position.dx * (_doubleTapScale - 1);
      final dy = -position.dy * (_doubleTapScale - 1);
      // ignore: deprecated_member_use
      target = Matrix4.identity()
        // ignore: deprecated_member_use
        ..translate(dx, dy)
        // ignore: deprecated_member_use
        ..scale(_doubleTapScale);
    }

    _zoomAnimation =
        Matrix4Tween(begin: _transformController.value, end: target).animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
        );
    _animController
      ..reset()
      ..forward();
  }

  void _resetIfNeeded() {
    if (_transformController.value.getMaxScaleOnAxis() > _zoomThreshold) {
      _transformController.value = Matrix4.identity();
    }
  }

  @override
  void didUpdateWidget(_ZoomableImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.eventId != widget.event.eventId) {
      _resetIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: _onDoubleTapDown,
      onDoubleTap: _onDoubleTap,
      onTap: () {},
      child: InteractiveViewer(
        transformationController: _transformController,
        minScale: 1.0,
        maxScale: 10.0,
        onInteractionEnd: widget.onInteractionEnd,
        child: Center(
          child: Hero(
            tag: widget.event.eventId,
            child: MxcImage(
              key: ValueKey(widget.event.eventId),
              event: widget.event,
              fit: BoxFit.contain,
              isThumbnail: false,
              animated: true,
            ),
          ),
        ),
      ),
    );
  }
}
