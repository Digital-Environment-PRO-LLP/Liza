import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter_native_video_trimmer/flutter_native_video_trimmer.dart';
import 'package:matrix/matrix.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_compress/video_compress.dart';

import '../mp4_faststart.dart';
import '../platform_infos.dart';
import '../resize_video.dart';
import 'story_model.dart';
import 'story_video_trim.dart';

/// Порог, ниже которого видео не сжимаем (мелочь не стоит транскода).
const int _storyMinSizeToCompress = 20 * 1000;

/// Результат подготовки видео к публикации как сторис.
class PickedStoryVideo {
  final MatrixVideoFile file;
  final MatrixImageFile? thumbnail;

  /// true, если видео было ФИЗИЧЕСКИ обрезано (mobile) до окна [storyMaxVideoMs].
  final bool wasTrimmed;

  /// Окно отрезка МЕТАДАННЫМИ (desktop/web, где физической обрезки нет —
  /// вьюер проигрывает срез `[startMs..endMs]`). null — обрезка не нужна или
  /// выполнена физически (mobile).
  final StoryTrim? trim;

  const PickedStoryVideo({
    required this.file,
    this.thumbnail,
    required this.wasTrimmed,
    this.trim,
  });
}

class _VideoProbe {
  final int? width;
  final int? height;
  final int durationMs;
  final Uint8List? poster;
  const _VideoProbe({
    this.width,
    this.height,
    required this.durationMs,
    this.poster,
  });
}

/// Готовит видео к публикации как сторис.
///
/// [startMs] — начало выбранного дорожкой окна (0 — от начала). Видео длиннее
/// [storyMaxVideoMs]: mobile — режется физически; desktop/web — окно едет
/// метаданными (`PickedStoryVideo.trim`), т.к. клиентского энкодера в стеке нет.
///
/// Метаданные (w/h/duration) заполняются ВСЕГДА: без них `EventVideoPlayer`
/// падает на fallback-размер, ломая aspect-кадр и таймбар. Постер нужен для
/// размытого фона (mobile — thumbnail, desktop/web — кадр из media_kit).
Future<PickedStoryVideo?> prepareStoryVideo(
  XFile xfile, {
  int startMs = 0,
}) async {
  if (PlatformInfos.isMobile) {
    return _prepareMobile(xfile, startMs);
  }
  return _prepareDesktop(xfile, startMs);
}

/// Длительность видео в мс (для решения, показывать ли дорожку-скраббер).
/// Mobile — VideoCompress; desktop/web — media_kit. 0 при неудаче.
Future<int> probeStoryVideoDurationMs(String path) async {
  if (PlatformInfos.isMobile) {
    try {
      final info = await VideoCompress.getMediaInfo(path);
      return (info.duration ?? 0).round();
    } catch (_) {
      return 0;
    }
  }
  final probe = await _probeVideoWithMediaKit(path);
  return probe?.durationMs ?? 0;
}

/// Кадр видео в позиции [positionMs] для филмстрипа дорожки. Mobile —
/// VideoCompress (singleton: звать ПОСЛЕДОВАТЕЛЬНО), с таймаутом. Desktop/web —
/// null (филмстрип деградирует до временной шкалы без кадров — carve).
Future<Uint8List?> storyVideoFrameAt(String path, int positionMs) async {
  if (!PlatformInfos.isMobile) return null;
  try {
    return await VideoCompress.getByteThumbnail(
      path,
      position: positionMs,
    ).timeout(const Duration(seconds: 5), onTimeout: () => null);
  } catch (_) {
    return null;
  }
}

Future<PickedStoryVideo?> _prepareMobile(XFile xfile, int startMs) async {
  var path = xfile.path;
  var wasTrimmed = false;

  final info = await VideoCompress.getMediaInfo(path);
  final durationMs = (info.duration ?? 0).round();
  final plan = planTrimWindow(durationMs, startMs: startMs);
  if (plan.needsTrim) {
    final trimmer = VideoTrimmer();
    await trimmer.loadVideo(path);
    final trimmedPath = await trimmer.trimVideo(
      startTimeMs: plan.startMs,
      endTimeMs: plan.endMs,
    );
    if (trimmedPath != null) {
      path = trimmedPath;
      wasTrimmed = true;
    }
  }
  // Если обрезка нужна, но физически не удалась (нативный триммер вернул null:
  // мало места/ошибка кодека) — не публикуем молча полный ролик, а везём окно
  // МЕТАДАННЫМИ (вьюер проиграет срез), как на desktop.
  final fallbackTrim = plan.needsTrim && !wasTrimmed
      ? StoryTrim(startMs: plan.startMs, endMs: plan.endMs)
      : null;

  final prepared = XFile(path);
  // Сжимаем сторис-видео до 720p (сторис не нужен 4K): держит размер под лимитом
  // и не грузит гигабайты в RAM. getVideoInfo заполняет w/h/duration обрезанного
  // файла (Android portrait-swap учтён внутри).
  final length = await prepared.length();
  var file = await prepared.getVideoInfo(
    compress: length > _storyMinSizeToCompress,
  );
  // Faststart на отправке: moov в начало (не-MMR хосты иначе хантят индекс).
  final fast = Mp4Faststart.process(file.bytes);
  if (fast != null) {
    file = MatrixVideoFile(
      bytes: fast,
      name: file.name,
      mimeType: file.mimeType,
      width: file.width,
      height: file.height,
      duration: file.duration,
    );
  }
  final thumbnail = await prepared.getVideoThumbnail();

  return PickedStoryVideo(
    file: file,
    thumbnail: thumbnail,
    wasTrimmed: wasTrimmed,
    trim: fallbackTrim,
  );
}

Future<PickedStoryVideo?> _prepareDesktop(XFile xfile, int startMs) async {
  final probe = await _probeVideoWithMediaKit(xfile.path);
  final durationMs = probe?.durationMs ?? 0;
  final plan = planTrimWindow(durationMs, startMs: startMs);

  var bytes = await xfile.readAsBytes();
  final fast = Mp4Faststart.process(bytes);
  if (fast != null) bytes = fast;

  final file = MatrixVideoFile(
    bytes: bytes,
    name: xfile.name,
    mimeType: xfile.mimeType,
    width: probe?.width,
    height: probe?.height,
    duration: durationMs > 0 ? durationMs : null,
  );

  MatrixImageFile? thumbnail;
  if (probe?.poster != null && await videoThumbnailBytesDecode(probe!.poster)) {
    thumbnail = MatrixImageFile(bytes: probe.poster!, name: 'thumb.jpg');
  }

  return PickedStoryVideo(
    file: file,
    thumbnail: thumbnail,
    wasTrimmed: false,
    // Физической обрезки на desktop нет — окно едет метаданными, вьюер играет срез.
    trim: plan.needsTrim
        ? StoryTrim(startMs: plan.startMs, endMs: plan.endMs)
        : null,
  );
}

/// Считывает w/h/duration и первый кадр видео через media_kit (desktop/web, где
/// VideoCompress недоступен). Всё best-effort: при любой осечке возвращает то,
/// что успел узнать (постер может быть null → блюр-фон деградирует в затемнение).
Future<_VideoProbe?> _probeVideoWithMediaKit(String path) async {
  Player? player;
  try {
    player = Player(configuration: const PlayerConfiguration(muted: true));
    // VideoController инициализирует видео-вывод (нужно для screenshot); сам
    // объект дальше не используем — привязан к player, освобождается с ним.
    // ignore: unused_local_variable
    final controller = VideoController(player);
    await player.open(Media(path), play: false);
    // Ждём, пока media_kit узнает размеры (короткий поллинг вместо гонки).
    for (var i = 0; i < 40; i++) {
      if (player.state.width != null && player.state.width! > 0) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final width = player.state.width;
    final height = player.state.height;
    final durationMs = player.state.duration.inMilliseconds;
    Uint8List? poster;
    try {
      poster = await player.screenshot(format: 'image/jpeg');
    } catch (_) {
      poster = null;
    }
    return _VideoProbe(
      width: width,
      height: height,
      durationMs: durationMs,
      poster: poster,
    );
  } catch (e, s) {
    Logs().w('Story video probe (media_kit) failed', e, s);
    return null;
  } finally {
    await player?.dispose();
  }
}
