import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/bandwidth_estimator.dart';
import 'package:liza/utils/video_prefetch_cache.dart';

/// Фоновая предзагрузка малых видео (< 5 МБ) из активной комнаты.
///
/// При получении `m.video` event через /sync начинает фоновую загрузку
/// целиком, чтобы при тапе на play воспроизведение начиналось мгновенно
/// из кэша. Крупные видео (> 5 МБ) НЕ загружаются — они стримятся
/// через libmpv Range/206.
///
/// Инициализация: `VideoPrefetchManager.instance.init(client)` в
/// `MatrixState.initState()`. Активная комната задаётся через
/// `setActiveRoom()` / `clearActiveRoom()` из `chat.dart`.
class VideoPrefetchManager {
  static final VideoPrefetchManager instance = VideoPrefetchManager._();
  VideoPrefetchManager._();

  static const _maxConcurrentPrefetch = 2;

  StreamSubscription<SyncUpdate>? _syncSub;
  Room? _activeRoom;

  final _queue = Queue<Event>();
  final _activeDownloads = <String>{};
  bool _processing = false;

  void init(Client client) {
    if (kIsWeb) return;
    _syncSub?.cancel();
    _syncSub = client.onSync.stream.listen(_onSync);
  }

  void setActiveRoom(Room room) => _activeRoom = room;
  void clearActiveRoom() => _activeRoom = null;

  void _onSync(SyncUpdate sync) {
    final room = _activeRoom;
    if (room == null) return;

    // Ищем m.video события в текущем sync-ответе для активной комнаты
    final roomUpdate = sync.rooms?.join?[room.id];
    if (roomUpdate == null) return;

    final events = roomUpdate.timeline?.events;
    if (events == null || events.isEmpty) return;

    for (final matrixEvent in events) {
      if (matrixEvent.type != EventTypes.Message) continue;
      final msgtype = matrixEvent.content.tryGet<String>('msgtype');
      if (msgtype != MessageTypes.Video) continue;

      final event = Event.fromMatrixEvent(matrixEvent, room);
      if (!VideoPrefetchCache.shouldPrefetch(event)) continue;

      // Не добавлять если уже в кэше или в очереди/загрузке
      final mxc = event.attachmentOrThumbnailMxcUrl()?.toString();
      if (mxc == null) continue;
      if (_activeDownloads.contains(mxc)) continue;

      _queue.add(event);
    }

    _processQueue();
  }

  Future<void> _processQueue() async {
    if (_processing) return;
    _processing = true;

    try {
      while (_queue.isNotEmpty &&
          _activeDownloads.length < _maxConcurrentPrefetch) {
        final event = _queue.removeFirst();
        final mxc = event.attachmentOrThumbnailMxcUrl()?.toString();
        if (mxc == null) continue;
        if (_activeDownloads.contains(mxc)) continue;

        // Проверяем кэш перед загрузкой
        final cached = await VideoPrefetchCache.instance.getCached(event);
        if (cached != null) continue;

        _activeDownloads.add(mxc);
        // Не await — загрузка идёт параллельно
        _downloadInBackground(event, mxc);
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _downloadInBackground(Event event, String mxc) async {
    final sw = Stopwatch()..start();
    try {
      Logs().v('VideoPrefetch: начало загрузки $mxc');
      final videoFile = await event.downloadAndDecryptAttachment();
      sw.stop();

      BandwidthEstimator.instance.addTimedSample(
        videoFile.bytes.length,
        sw.elapsed,
      );

      await VideoPrefetchCache.instance.store(event, videoFile.bytes);
      Logs().v('VideoPrefetch: загружено $mxc '
          '(${videoFile.bytes.length} bytes, '
          '${sw.elapsed.inMilliseconds} ms)');
    } catch (e) {
      Logs().w('VideoPrefetch: ошибка загрузки $mxc: $e');
    } finally {
      _activeDownloads.remove(mxc);
      // Может быть ещё что-то в очереди
      _processQueue();
    }
  }

  void dispose() {
    _syncSub?.cancel();
    _syncSub = null;
    _queue.clear();
    _activeDownloads.clear();
  }
}
