import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

/// Файловый кэш предзагруженных видео.
///
/// Хранит полностью скачанные малые видео (< 5 МБ) в
/// `{tempDir}/liza_video_cache/{sha256(mxc)}.mp4`. Используется
/// [VideoPrefetchManager]-ом для фоновой предзагрузки и
/// `video_player.dart` для мгновенного воспроизведения из кэша.
///
/// LRU-eviction: при превышении [maxCacheBytes] удаляются файлы
/// с самой старой датой доступа.
class VideoPrefetchCache {
  static final VideoPrefetchCache instance = VideoPrefetchCache._();
  VideoPrefetchCache._();

  Directory? _cacheDir;

  /// Лимит размера кэша. По умолчанию 500 МБ.
  int maxCacheBytes = 500 * 1024 * 1024;

  /// Максимальный размер видео для prefetch (5 МБ).
  static const maxPrefetchFileSize = 5 * 1024 * 1024;

  Future<Directory> _ensureDir() async {
    final cached = _cacheDir;
    if (cached != null) return cached;
    final tmp = await getTemporaryDirectory();
    final d = Directory('${tmp.path}/liza_video_cache');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    _cacheDir = d;
    return d;
  }

  /// Ключ кэша: URI-encoded mxc URL (безопасен для файловой системы).
  static String _cacheKey(Uri mxcUri) =>
      Uri.encodeComponent(mxcUri.toString());

  /// Проверить, есть ли полностью скачанный файл в кэше.
  /// Возвращает файл только если размер совпадает с ожидаемым (или
  /// ожидаемый неизвестен, тогда просто проверяем наличие).
  Future<File?> getCached(Event event) async {
    if (kIsWeb) return null;
    final url = event.attachmentOrThumbnailMxcUrl();
    if (url == null) return null;
    final dir = await _ensureDir();
    final file = File('${dir.path}/${_cacheKey(url)}.mp4');
    if (await file.exists()) {
      final expectedSize = event.content
          .tryGetMap<String, dynamic>('info')
          ?.tryGet<int>('size');
      final stat = await file.stat();
      if (expectedSize == null || stat.size >= expectedSize) return file;
    }
    return null;
  }

  /// Путь для записи нового файла в кэш (атомарная запись: tmp → rename).
  Future<(File target, File tmp)> _cacheFiles(Uri mxcUri) async {
    final dir = await _ensureDir();
    final key = _cacheKey(mxcUri);
    final target = File('${dir.path}/$key.mp4');
    final tmp = File('${dir.path}/$key.mp4.tmp');
    return (target, tmp);
  }

  /// Сохранить скачанные байты в кэш. Атомарная запись (tmp → rename).
  Future<File> store(Event event, Uint8List bytes) async {
    final url = event.attachmentOrThumbnailMxcUrl();
    if (url == null) throw ArgumentError('Event has no mxc URL');
    final (target, tmp) = await _cacheFiles(url);
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(target.path);
    await _evictIfNeeded();
    return target;
  }

  /// LRU eviction: удаляет старые файлы пока размер кэша > [maxCacheBytes].
  Future<void> _evictIfNeeded() async {
    final dir = await _ensureDir();
    final files = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.mp4'))
        .cast<File>()
        .toList();

    var totalSize = 0;
    final stats = <File, FileStat>{};
    for (final f in files) {
      final s = await f.stat();
      stats[f] = s;
      totalSize += s.size;
    }

    if (totalSize <= maxCacheBytes) return;

    // Сортировать по дате доступа (oldest first)
    files.sort(
      (a, b) => stats[a]!.accessed.compareTo(stats[b]!.accessed),
    );

    for (final f in files) {
      if (totalSize <= maxCacheBytes) break;
      totalSize -= stats[f]!.size;
      try {
        await f.delete();
      } catch (_) {}
    }
  }

  /// Стоит ли prefetch-ить это видео.
  static bool shouldPrefetch(Event event) {
    if (kIsWeb) return false;
    if (event.isAttachmentEncrypted) return false;
    if (!event.status.isSent) return false;
    final info = event.content.tryGetMap<String, dynamic>('info');
    final size = info?.tryGet<int>('size');
    if (size == null || size > maxPrefetchFileSize) return false;
    if (size <= 0) return false;
    return true;
  }
}
