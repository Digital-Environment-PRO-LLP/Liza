import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:cross_file/cross_file.dart';
import 'package:matrix/matrix.dart';
import 'package:universal_html/html.dart' as html;

/// `true`, если MIME-тип относится к видео.
bool isVideoMime(String? mime) => mime != null && mime.startsWith('video');

/// Генерирует JPEG-постер (первый кадр) видео **на Web** через HTML5
/// `VideoElement` + `Canvas`. На нативных платформах возвращает `null`
/// (там постер делает media_kit `_VideoThumbnailView` в `send_file_dialog`
/// либо `video_compress` на mobile).
///
/// Постер заливается в `m.video.info.thumbnail_url` при отправке — это
/// единственный надёжный способ дать превью всем получателям (см.
/// `plans/media-v-format.md` §8.8). libmpv-`screenshot` на Flutter Web
/// недоступен, поэтому здесь — нативный браузерный декодер.
Future<MatrixImageFile?> generateWebVideoThumbnail(XFile file) async {
  if (!kIsWeb) return null;
  String? objectUrl;
  try {
    final bytes = await file.readAsBytes();
    objectUrl = html.Url.createObjectUrlFromBlob(html.Blob([bytes]));

    final video = html.VideoElement()
      ..src = objectUrl
      ..muted = true
      ..preload = 'auto';
    video.setAttribute('playsinline', 'true');
    video.load();

    await video.onLoadedMetadata.first.timeout(const Duration(seconds: 15));
    // `videoWidth`/`videoHeight` есть только в web-реализации DOM; через
    // `dynamic` обходим ограничение кросс-платформенного типа universal_html
    // (этот код исполняется лишь на Web — выше стоит `kIsWeb`-guard).
    final dynamic dynVideo = video;
    final width = (dynVideo.videoWidth as num?)?.toInt() ?? 0;
    final height = (dynVideo.videoHeight as num?)?.toInt() ?? 0;
    if (width == 0 || height == 0) {
      Logs().w('Web video thumbnail: zero dimensions for ${file.name}');
      return null;
    }

    // Перематываемся на ~0.1с — у первого кадра часто чёрный fade-in.
    final duration = video.duration;
    video.currentTime = (duration.isFinite && duration > 0.3) ? 0.1 : 0.0;
    await video.onSeeked.first.timeout(const Duration(seconds: 15));

    final canvas = html.CanvasElement(width: width, height: height);
    canvas.context2D.drawImageScaled(
      video,
      0,
      0,
      width.toDouble(),
      height.toDouble(),
    );

    final dataUrl = canvas.toDataUrl('image/jpeg', 0.85);
    final base64Part = dataUrl.substring(dataUrl.indexOf(',') + 1);
    final jpeg = base64Decode(base64Part);
    if (jpeg.length < 1024) {
      Logs().w('Web video thumbnail: suspicious size ${jpeg.length}');
      return null;
    }
    return MatrixImageFile(
      bytes: Uint8List.fromList(jpeg),
      name: 'thumbnail.jpg',
      mimeType: 'image/jpeg',
      width: width,
      height: height,
    );
  } catch (e, s) {
    Logs().w('Web video thumbnail generation failed', e, s);
    return null;
  } finally {
    if (objectUrl != null) html.Url.revokeObjectUrl(objectUrl);
  }
}
