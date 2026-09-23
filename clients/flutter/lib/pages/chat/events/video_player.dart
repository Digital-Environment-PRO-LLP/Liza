import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/chat_topology.dart';
import 'package:liza/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:liza/utils/monitoring.dart';
import 'package:liza/utils/mpv_property.dart';
import 'package:liza/utils/platform_infos.dart';
import 'package:liza/utils/upload_progress_tracker.dart';
import 'package:liza/utils/video_poster_cache.dart';
import 'package:liza/widgets/blur_hash.dart';
import 'package:liza/widgets/mxc_image.dart';
import '../../image_viewer/image_viewer.dart';

/// Inline-превью видео в ленте без серверного thumbnail-а
/// (`info.thumbnail_url` отсутствует — типично для отправок с desktop/Web,
/// где `VideoCompress.getByteThumbnail()` не работает).
///
/// Виджет САМ владеет `Player + VideoController` и **монтирует `Video`
/// в дерево** под BlurHash. Это критично: media_kit `Player.screenshot()`
/// в headless-режиме (без `Video`-виджета в дереве) на macOS отдаёт
/// канонический пустой буфер — Flutter compositor не тикает mpv
/// render-callback → VO mpv не заполняется реальным кадром →
/// `screenshot-raw video` возвращает «чёрный JPEG 42614 байт» на каждом
/// видео независимо от настроек. С Video в дереве (даже скрытым под
/// BlurHash) compositor рендерит текстуру, mpv VO получает кадры,
/// screenshot отдаёт настоящий первый кадр.
///
/// Кеш ([VideoPosterCache]) теперь только disk-файл, concurrency
/// semaphore (1 экстракция за раз) и negative cache на сессию.
class _VideoPosterImage extends StatefulWidget {
  final Event event;
  final double width;
  final double height;
  final String blurHash;

  const _VideoPosterImage({
    required this.event,
    required this.width,
    required this.height,
    required this.blurHash,
  });

  @override
  State<_VideoPosterImage> createState() => _VideoPosterImageState();
}

class _VideoPosterImageState extends State<_VideoPosterImage> {
  File? _poster;
  Player? _player;
  VideoController? _controller;
  bool _disposed = false;
  // Единый владелец dispose извлекающего Player: и dispose() виджета, и finally
  // _bootstrap хотят освободить один и тот же Player. При смерти виджета во время
  // 20s-ожидания первого кадра оба срабатывали → ДВОЙНОЙ dispose (лишний
  // dispose-стек в логе, #19). Флаг гарантирует ровно один dispose, без утечки.
  bool _posterPlayerDisposed = false;

  Future<void> _disposePosterPlayer(Player? p) async {
    if (p == null || _posterPlayerDisposed) return;
    _posterPlayerDisposed = true;
    await p.dispose();
  }
  bool _bootstrapStarted = false;

  /// Экстракция постера упала терминально (таймаут/ошибка/чёрный кадр) — вместо
  /// НЕМОГО BlurHash показываем видимый значок + разовый retry. Раньше сбой был
  /// молчаливым (`markNegative` без UI/сигнала) — «то не подгружает» без следа.
  bool _posterFailed = false;
  // Лимит 1 ручная попытка: retry упрётся в те же 20с/8 MiB — ценность в
  // ВИДИМОСТИ и телеметрии, не в бесконечных ретраях (RISK-6).
  bool _retried = false;

  /// Единая точка терминального провала постера: разовая телеметрия
  /// `[video-fail] reason=poster-extract-fail` (ДО `markNegative` — после него
  /// `isNegative` уже true), negative-метка, видимый error-state. Секретов в
  /// сигнал НЕ кладём (пин `RL-mediadiag-no-secret`): только префикс/reason/host.
  void _markPosterFailed(Event event) {
    if (!VideoPosterCache.instance.isNegative(event)) {
      Monitoring.reportVideoIssue(
        prefix: Monitoring.videoFailurePrefix,
        reason: 'poster-extract-fail',
        host: event.room.client.homeserver?.host,
      );
    }
    VideoPosterCache.instance.markNegative(event);
    if (mounted) setState(() => _posterFailed = true);
  }

  /// Ручной retry постера (тап по значку). Сбрасывает negative-метку и
  /// `_bootstrapStarted` ПЕРЕД повторным `_bootstrap` — иначе тот вернулся бы
  /// сразу по guard'у. Один раз (`_retried`).
  void _retryPoster() {
    if (_retried) return;
    _retried = true;
    VideoPosterCache.instance.clearNegative(widget.event);
    setState(() {
      _posterFailed = false;
      _bootstrapStarted = false;
    });
    _bootstrap();
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void didUpdateWidget(_VideoPosterImage old) {
    super.didUpdateWidget(old);
    // Родитель пересобрал виджет с обновлённым Event (sending → synced).
    // Постера ещё нет, libmpv не запускали — пробуем сейчас.
    if (_poster == null && !_bootstrapStarted) {
      _bootstrap();
    }
  }

  Future<void> _bootstrap() async {
    if (_bootstrapStarted) return;
    _bootstrapStarted = true;
    final event = widget.event;
    final eventId = event.eventId;

    // 1. Disk-cache hit?
    final cached = await VideoPosterCache.instance.getCached(event);
    if (!mounted) return;
    if (cached != null) {
      setState(() => _poster = cached);
      return;
    }

    if (!VideoPosterCache.instance.isSupported(event)) {
      // E2EE / Web / sending. Без negative cache, при пересборке попробуем
      // снова (sending → synced).
      _bootstrapStarted = false;
      return;
    }
    if (VideoPosterCache.instance.isNegative(event)) return;

    // 2. URL получаем ДО слота — это пустяковая операция, semaphore
    //    держать рано.
    final url = await event.getAttachmentUri();
    if (!mounted || _disposed) return;
    if (url == null) {
      Logs().w('Video poster[$eventId]: getAttachmentUri null');
      return;
    }
    final token = event.room.client.accessToken;
    final headers = <String, String>{
      if (token != null) 'Authorization': 'Bearer $token',
    };

    // 3. Ждём свой слот в semaphore (одна экстракция глобально за раз).
    Logs().i('Video poster[$eventId]: awaiting slot');
    final slot = await VideoPosterCache.instance.acquireSlot();
    if (_disposed) {
      slot.release();
      return;
    }
    Logs().i('Video poster[$eventId]: slot acquired');

    final player = Player(
      configuration: const PlayerConfiguration(
        logLevel: MPVLogLevel.error,
        muted: true,
      ),
    );
    final controller = VideoController(player);

    // setState ДО открытия Media: build() поставит `Video`-виджет в дерево,
    // Flutter compositor начнёт рендерить текстуру, mpv render-callback
    // будет тикать, VO заполнится настоящим кадром. Только после этого
    // `Player.screenshot()` вернёт что-то осмысленное (а не пустой буфер
    // 42614 байт прошлой headless-реализации).
    if (mounted) {
      setState(() {
        _player = player;
        _controller = controller;
      });
    }

    try {
      await controller.platform.future.timeout(const Duration(seconds: 5));
      Logs().i('Video poster[$eventId]: controller platform ready');

      // Постеру нужен лишь первый кадр: ограничиваем демуксер 8 MiB
      // (заведомо хватает для типичных битрейтов), не тянем весь файл.
      // После MMR-cutover сервер отдаёт Range нативно, но постер-путь всё
      // равно читает только голову — дальний seek тут не нужен.
      await setMpvProperty(player, 'cache', 'yes');
      await setMpvProperty(player, 'demuxer-max-bytes', '8388608');
      await setMpvProperty(player, 'demuxer-max-back-bytes', '0');

      Logs().i('Video poster[$eventId]: opening $url');
      await player.open(
        Media(url.toString(), httpHeaders: headers),
        play: true,
      );

      Logs().i('Video poster[$eventId]: awaiting first frame rendered');
      await controller.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 20),
      );

      // `waitUntilFirstFrameRendered` срабатывает на Resize-event от
      // native side (libmpv узнал размеры через демуксер). Но реально
      // декодированный кадр в VO mpv может появиться чуть позже,
      // плюс у видео часто 1-2 чёрных кадра fade-in. 500 мс настоящего
      // playback гарантируют, что в VO лежит честная картинка.
      await Future.delayed(const Duration(milliseconds: 500));
      if (_disposed) return;

      final bytes = await player.screenshot(format: 'image/jpeg');
      // Защита от регрессии прошлой версии: «канонический чёрный буфер»
      // в headless-режиме был ровно 42614 байт. Настоящий 1920x800
      // first-frame JPEG идёт в десятки-сотни KB. Меньше 8 KB —
      // подозрительно (либо чёрный, либо ошибка), на диск не пишем,
      // negative cache, BlurHash остаётся.
      if (bytes == null || bytes.length < 8192) {
        Logs().w(
          'Video poster[$eventId]: suspicious screenshot '
          '(bytes=${bytes?.length}), marking negative',
        );
        _markPosterFailed(event);
        return;
      }

      final file = await VideoPosterCache.instance.storeBytes(event, bytes);
      Logs().i(
        'Video poster[$eventId]: saved ${bytes.length} bytes '
        'to ${file.path}',
      );
      if (!mounted) return;
      setState(() => _poster = file);
    } catch (e, s) {
      Logs().w('Video poster[$eventId]: extraction failed: $e', e, s);
      _markPosterFailed(event);
    } finally {
      // Снимаем `Video`-виджет ДО dispose-а Player, иначе VideoController
      // может ругаться на использование уже мёртвой текстуры.
      if (mounted) {
        setState(() {
          _player = null;
          _controller = null;
        });
      }
      await _disposePosterPlayer(player);
      slot.release();
      Logs().i('Video poster[$eventId]: slot released');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Если виджет умер посередине экстракции, _bootstrap dispose-нет
    // Player в finally, но у нас уже не будет setState — нормально.
    // А если виджет умер ПОСЛЕ setState(_player=...), но ДО finally,
    // надо вручную dispose-нуть, иначе libmpv продолжит тянуть stream.
    final p = _player;
    _player = null;
    _controller = null;
    // Через единый владелец: если finally _bootstrap уже освободил этот Player —
    // повторно не трогаем (флаг), иначе освобождаем сейчас (fire-and-forget:
    // dispose() виджета синхронный, ждать нельзя).
    unawaited(_disposePosterPlayer(p));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final poster = _poster;
    if (poster != null) {
      return Image.file(
        poster,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.cover,
        // Если файл удалят между read и build — откатываемся к BlurHash,
        // а не показываем сломанную картинку.
        errorBuilder: (_, _, _) => BlurHash(
          blurhash: widget.blurHash,
          width: widget.width,
          height: widget.height,
          fit: BoxFit.cover,
        ),
      );
    }

    // Идёт экстракция (есть VideoController) или ещё не стартовала.
    // Если есть controller — монтируем Video под BlurHash: compositor
    // рендерит текстуру, mpv VO заполняется, screenshot отдаст
    // настоящий кадр. BlurHash полноразмерный сверху прячет «голый»
    // Video-виджет от пользователя.
    final ctrl = _controller;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (ctrl != null)
            Video(
              controller: ctrl,
              fit: BoxFit.cover,
              controls: NoVideoControls,
            ),
          BlurHash(
            blurhash: widget.blurHash,
            width: widget.width,
            height: widget.height,
            fit: BoxFit.cover,
          ),
          // Терминальный провал экстракции постера: видимый значок в углу
          // вместо немого BlurHash. Тап по значку — разовый retry (свой
          // GestureDetector перехватывает тап, не открывая плеер). После
          // исчерпания — неинтерактивный «broken image». Плитка целиком
          // по-прежнему тапается для воспроизведения (play-кнопка в центре).
          if (_posterFailed && ctrl == null)
            Positioned(
              right: 6,
              bottom: 6,
              child: GestureDetector(
                onTap: _retried ? null : _retryPoster,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _retried ? Icons.broken_image_outlined : Icons.refresh,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class EventVideoPlayer extends StatelessWidget {
  final Event event;
  final Timeline? timeline;
  final Color? textColor;
  final Color? linkColor;

  /// Плашка времени (Liza-стиль) — в правом нижнем углу поверх превью,
  /// напротив бейджа длительности (тот в левом нижнем).
  final Widget? timeOverlay;

  const EventVideoPlayer(
    this.event, {
    this.timeline,
    this.textColor,
    this.linkColor,
    this.timeOverlay,
    super.key,
  });

  static const String fallbackBlurHash = 'L5H2EC=PM+yV0g-mq.wG9c010J}I';

  @override
  Widget build(BuildContext context) {
    final supportsVideoPlayer = PlatformInfos.supportsVideoPlayer;

    final blurHash =
        (event.infoMap as Map<String, dynamic>).tryGet<String>(
          'xyz.amorgan.blurhash',
        ) ??
        fallbackBlurHash;
    const maxDimension = 300.0;
    final infoMap = event.content.tryGetMap<String, Object?>('info');
    final videoWidth = infoMap?.tryGet<int>('w') ?? maxDimension;
    final videoHeight = infoMap?.tryGet<int>('h') ?? maxDimension;

    final modifier = max(videoWidth, videoHeight) / maxDimension;
    final width = videoWidth / modifier;
    final height = videoHeight / modifier;

    final durationInt = infoMap?.tryGet<int>('duration');
    final duration = durationInt == null
        ? null
        : Duration(milliseconds: durationInt);

    // Если для этого события идёт upload (txid == event.eventId до того,
    // как сервер вернул real eventId) — показываем overlay прогресса.
    final uploadNotifier = UploadProgressTracker.instance.byId(event.eventId);

    return Material(
      color: Colors.black,
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      child: InkWell(
        // Если плеер поддерживается — тап только ВОСПРОИЗВОДИТ видео во
        // встроенном просмотрщике (не гейтится). Fallback-ветка (плеер не
        // поддерживается платформой) — это явное сохранение файла на
        // устройство, и в защищённом канале мы его не даём.
        onTap: () {
          if (supportsVideoPlayer) {
            showDialog<void>(
              context: context,
              builder: (_) =>
                  ImageViewer(event, timeline: timeline, outerContext: context),
            );
          } else if (!event.room.isContentProtected) {
            event.saveFile(context);
          }
        },
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        child: SizedBox(
          width: width,
          height: height,
          child: Hero(
            tag: event.eventId,
            child: Stack(
              children: [
                if (event.hasThumbnail)
                  MxcImage(
                    event: event,
                    isThumbnail: true,
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    placeholder: (context) => BlurHash(
                      blurhash: blurHash,
                      width: width,
                      height: height,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  _VideoPosterImage(
                    event: event,
                    width: width,
                    height: height,
                    blurHash: blurHash,
                  ),
                if (event.status.isError)
                  _UploadRetryOverlay(event: event)
                else if (uploadNotifier != null)
                  _UploadOverlay(notifier: uploadNotifier, event: event)
                else
                  Center(
                    child: CircleAvatar(
                      child: supportsVideoPlayer
                          ? const Icon(Icons.play_arrow_outlined)
                          : const Icon(Icons.file_download_outlined),
                    ),
                  ),
                if (duration != null)
                  Positioned(
                    bottom: 8,
                    left: 16,
                    child: Text(
                      '${duration.inMinutes.toString().padLeft(2, '0')}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: Colors.white,
                        backgroundColor: Colors.black.withAlpha(32),
                      ),
                    ),
                  ),
                if (timeOverlay != null)
                  Positioned(bottom: 8, right: 8, child: timeOverlay!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Полупрозрачный overlay поверх превью видео: кольцо прогресса вокруг
/// тёмного круга с крестиком (Liza-style). Тап по крестику отменяет
/// загрузку этого видео. Подписывается на [ValueNotifier] из
/// [UploadProgressTracker] и перерисовывает только индикатор — окружающий
/// Stack не пересоздаётся.
class _UploadOverlay extends StatelessWidget {
  final ValueNotifier<double> notifier;
  final Event event;

  const _UploadOverlay({required this.notifier, required this.event});

  /// Отмена: ставим флаг (его на ближайшем чанке тела читает
  /// `UploadProgressHttpClient` и обрывает отдачу) и сразу убираем
  /// pending-событие из ленты. `cancelSend` может бросить, если событие уже
  /// удалено/отправлено — гасим.
  void _cancel() {
    UploadProgressTracker.instance.requestCancel(event.eventId);
    // ignore: discarded_futures
    event.cancelSend().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final cancelLabel = L10n.of(context).cancel;
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black54,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: notifier,
                      builder: (context, value, _) => SizedBox(
                        width: 64,
                        height: 64,
                        child: CircularProgressIndicator(
                          value: value <= 0 ? null : value,
                          strokeWidth: 4,
                          backgroundColor: Colors.white24,
                          valueColor: const AlwaysStoppedAnimation(
                            Colors.white,
                          ),
                        ),
                      ),
                    ),
                    Semantics(
                      button: true,
                      label: cancelLabel,
                      child: Tooltip(
                        message: cancelLabel,
                        child: Material(
                          type: MaterialType.circle,
                          color: Colors.black54,
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: _cancel,
                            child: const SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _UploadPhaseLabel(event: event, notifier: notifier),
            ],
          ),
        ),
      ),
    );
  }
}

/// Подпись этапа отправки под кольцом прогресса.
///
/// Этап обязателен, а не украшение: шкала НЕ сквозная (у сжатия и у отдачи
/// свои 0..100), и без подписи переход «100%» → «3%» читается как «зависло и
/// откатилось». С подписью это «Сжатие 100%» → «Отправка 3%» — очевидная смена
/// этапа.
class _UploadPhaseLabel extends StatelessWidget {
  final Event event;
  final ValueNotifier<double> notifier;

  const _UploadPhaseLabel({required this.event, required this.notifier});

  static const _style = TextStyle(
    color: Colors.white,
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final phaseNotifier = UploadProgressTracker.instance.phaseFor(
      event.eventId,
    );

    Widget labelFor(UploadPhase phase) => ValueListenableBuilder<double>(
      valueListenable: notifier,
      builder: (context, value, _) {
        final name = switch (phase) {
          UploadPhase.preparing => l10n.uploadPhasePreparing,
          UploadPhase.compressing => l10n.uploadPhaseCompressing,
          UploadPhase.uploading => l10n.uploadPhaseUploading,
        };
        // В «Подготовке» мерить нечего (чтение файла, HEIC, постер) — кольцо
        // крутится неопределённым, процент не выдумываем.
        if (phase == UploadPhase.preparing || value <= 0) {
          return Text(name, style: _style);
        }
        return Text('$name ~${(value * 100).round()}%', style: _style);
      },
    );

    if (phaseNotifier == null) return labelFor(UploadPhase.uploading);
    return ValueListenableBuilder<UploadPhase>(
      valueListenable: phaseNotifier,
      builder: (context, phase, _) => labelFor(phase),
    );
  }
}

/// Overlay поверх превью видео, когда отправка провалилась
/// (`EventStatus.error`). Авто-ретрая нет — пользователь сам тапает по
/// значку повтора, и `Event.sendAgain()` перезапускает отправку
/// (matrix-dart-sdk перезаливает сохранённый файл целиком — докачки в
/// Matrix Media API нет).
class _UploadRetryOverlay extends StatelessWidget {
  final Event event;

  const _UploadRetryOverlay({required this.event});

  @override
  Widget build(BuildContext context) {
    final reason = UploadProgressTracker.instance.errorFor(event.eventId);
    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: InkWell(
          onTap: () {
            // Ручной повтор снимает устаревший класс ошибки (D-3), иначе
            // прошлый terminal навсегда блокировал бы авто-ретрай события.
            UploadProgressTracker.instance.clearErrorKind(event.eventId);
            event.sendAgain();
          },
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.refresh, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  L10n.of(context).tryToSendAgain,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (reason != null) ...[
                  const SizedBox(height: 4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      reason,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
