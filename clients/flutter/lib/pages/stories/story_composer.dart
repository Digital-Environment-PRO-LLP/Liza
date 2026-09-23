import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:matrix/matrix.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

import '../../l10n/l10n.dart';
import '../../utils/stories/stories_extension.dart';
import '../../utils/stories/story_media_picker.dart';
import '../../utils/stories/story_model.dart';
import '../../widgets/matrix.dart';
import 'story_composer_view.dart';

class StoryComposer extends StatefulWidget {
  const StoryComposer({
    required this.file,
    this.thumbnail,
    this.videoWasTrimmed = false,
    this.trim,
    this.channelId,
    super.key,
  });

  final MatrixFile file;
  final MatrixImageFile? thumbnail;
  final bool videoWasTrimmed;

  /// Окно видео-отрезка метаданными (desktop/web без физической обрезки).
  final StoryTrim? trim;

  /// Если задан — публикация идёт от имени КАНАЛА (publishChannelStory) в
  /// его сторис-комнату, а не в личную сторис-комнату автора.
  final String? channelId;

  @override
  State<StoryComposer> createState() => StoryComposerController();
}

class StoryComposerController extends State<StoryComposer> {
  final List<StoryOverlay> overlays = [];
  bool publishing = false;

  bool get isVideo => widget.file is MatrixVideoFile;

  // Трансформ переднего плана (пинч-зум + панорама), персистится в content и
  // виден зрителям. translation — доля РАМКИ кадра (не contain-rect медиа).
  double mediaScale = 1.0;
  Offset mediaTranslation = Offset.zero;

  /// Обновляет трансформ из жестов. Клампинг делает вьюер (у него размеры кадра),
  /// сюда приходят уже валидные значения.
  void setMediaTransform(double scale, Offset translation) {
    setState(() {
      mediaScale = scale;
      mediaTranslation = translation;
    });
  }

  // Постер для размытого фона (статичный): фото — само изображение; видео —
  // thumbnail (mobile) / первый кадр из media_kit (desktop). null → затемнение.
  late final ImageProvider? posterImage = _buildPosterImage();

  ImageProvider? _buildPosterImage() {
    if (!isVideo) return previewImage;
    final tb = widget.thumbnail?.bytes;
    if (tb == null) return null;
    return MemoryImage(Uint8List.fromList(tb));
  }

  // Кэшируем ImageProvider один раз, чтобы setState при drag не пересоздавал
  // декодер изображения и не вызывал мерцание фона. Для видео - null (фон
  // рисует живое media_kit-превью, см. videoController).
  late final ImageProvider? previewImage = _buildPreviewImage();

  double? mediaAspect; // ширина/высота отрисованного медиа

  // Живое превью видео в редакторе: media_kit-плеер из локального файла,
  // muted + loop. Нужно, потому что thumbnail видео не всегда есть (на desktop
  // VideoCompress.getByteThumbnail не работает) - иначе показывалась иконка на
  // весь экран вместо самого видео.
  Player? _videoPlayer;
  VideoController? _videoController;
  VideoController? get videoController => _videoController;

  @override
  void initState() {
    super.initState();
    if (isVideo) {
      _initVideoPreview();
    } else {
      _resolveImageAspect();
    }
  }

  // Временный файл превью и подписка на размеры — освобождаются в dispose
  // (иначе tmp копится при многократном «Назад», а подписка течёт).
  File? _videoTmpFile;
  StreamSubscription<int?>? _widthSub;

  Future<void> _initVideoPreview() async {
    try {
      final bytes = widget.file.bytes;
      final dir = await getTemporaryDirectory();
      final name = widget.file.name.isEmpty
          ? 'story_preview'
          : widget.file.name;
      final file = File('${dir.path}/composer_$name');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      _videoTmpFile = file;
      final player = Player(
        configuration: const PlayerConfiguration(muted: true),
      );
      final controller = VideoController(player);
      _videoPlayer = player;
      _videoController = controller;
      await player.setPlaylistMode(PlaylistMode.loop);
      await player.open(Media(file.path));
      await player.setVolume(0);
      // aspect из реальных размеров видео, когда media_kit их узнает.
      _widthSub = player.stream.width.listen((w) {
        final h = player.state.height;
        if (w != null && h != null && h > 0 && mounted) {
          setState(() => mediaAspect = w / h);
        }
      });
      if (mounted) setState(() {});
    } catch (e, s) {
      Logs().w('Story composer video preview failed', e, s);
    }
  }

  void _resolveImageAspect() {
    final provider = previewImage;
    if (provider == null) return;
    final stream = provider.resolve(const ImageConfiguration());
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        final w = info.image.width, h = info.image.height;
        if (h > 0 && mounted) {
          setState(() => mediaAspect = w / h);
        }
        stream.removeListener(listener);
      },
      onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
  }

  @override
  void dispose() {
    _widthSub?.cancel();
    _videoPlayer?.dispose();
    // Убираем временный файл превью (накапливался при повторном выборе видео).
    try {
      _videoTmpFile?.deleteSync();
    } catch (_) {}
    captionController.dispose();
    captionFocus.dispose();
    super.dispose();
  }

  ImageProvider? _buildPreviewImage() {
    // Видео рисуется живым media_kit-превью, не статичной картинкой.
    if (isVideo) return null;
    final bytes = widget.file.bytes;
    return MemoryImage(Uint8List.fromList(bytes));
  }

  bool get videoWasTrimmed => widget.videoWasTrimmed;

  void addOverlay() {
    setState(() {
      overlays.add(const StoryOverlay(text: '', x: 0.5, y: 0.5));
    });
  }

  void setOverlayText(int i, String text) {
    setState(() {
      final o = overlays[i];
      overlays[i] = StoryOverlay(text: text, x: o.x, y: o.y);
    });
  }

  void updateOverlayPosition(int i, double x, double y) {
    setState(() {
      final o = overlays[i];
      overlays[i] = StoryOverlay(
        text: o.text,
        x: x.clamp(0.0, 1.0),
        y: y.clamp(0.0, 1.0),
      );
    });
  }

  final TextEditingController captionController = TextEditingController();
  final FocusNode captionFocus = FocusNode();

  bool get canPublish => !publishing;

  /// «Назад» из редактора = заново выбрать медиа (вместо возврата в список
  /// чатов). При отмене выбора закрываем редактор.
  Future<void> goBackToPicker() async {
    final composer = await pickStoryMediaComposer(
      context,
      channelId: widget.channelId,
    );
    if (!mounted) return;
    if (composer == null) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => composer));
  }

  Future<void> publish() async {
    // Повторный вход (двойной клик / Enter по кнопке) игнорируем: иначе два
    // параллельных sendFileEvent опубликуют сторис дважды.
    if (publishing) return;
    setState(() => publishing = true);
    // Успешная публикация закрывает экран — сбрасывать publishing тогда не
    // нужно (и нельзя: setState после pop бьёт по размонтированному стейту).
    var published = false;
    try {
      final client = Matrix.of(context).client;
      final channelId = widget.channelId;
      final overlaysToSend = overlays
          .where((o) => o.text.trim().isNotEmpty)
          .toList();
      final caption = captionController.text.trim().isEmpty
          ? null
          : captionController.text.trim();
      final media = StoryMedia(
        background: StoryMediaBackground.blur,
        scale: mediaScale,
        dx: mediaTranslation.dx,
        dy: mediaTranslation.dy,
        trim: widget.trim,
      );
      if (channelId != null) {
        await client.publishChannelStory(
          channelId: channelId,
          file: widget.file,
          thumbnail: widget.thumbnail,
          overlays: overlaysToSend,
          caption: caption,
          media: media,
        );
      } else {
        await client.publishStory(
          file: widget.file,
          thumbnail: widget.thumbnail,
          overlays: overlaysToSend,
          caption: caption,
          media: media,
        );
      }
      published = true;
      if (mounted) Navigator.of(context).pop(true);
    } catch (e, s) {
      Logs().w('Story publish failed', e, s);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.of(context).storyPublishFailed)),
        );
      }
    } finally {
      // Кнопку разблокируем в finally, а не только в catch: при отмене или
      // нештатном выходе из sendFileEvent (без исключения) publishing иначе
      // оставался true навсегда и «Далее» гасла безвозвратно — пользователь
      // видел неактивную кнопку без единого сообщения об ошибке.
      if (mounted && !published) setState(() => publishing = false);
    }
  }

  @override
  Widget build(BuildContext context) => StoryComposerView(this);
}
