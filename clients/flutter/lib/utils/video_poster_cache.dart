import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';

/// Disk-кеш для постеров (первого кадра) видео без серверного thumbnail.
///
/// Зачем это (`m.video` от desktop/Web без `info.thumbnail_url`,
/// `VideoCompress.getByteThumbnail()` только на mobile, MMR на dev ещё
/// не поднят) — подробно в `plans/media-pipeline.md` §2.6 / §2.8.
///
/// Класс владеет только тремя вещами:
/// 1. **Диск.** `{tempDir}/liza_video_posters/{eventId}.jpg` — JPEG-постера.
///    Запись атомарная (tmp → rename).
/// 2. **Concurrency limit.** Глобальный semaphore: одновременно может идти
///    только одна экстракция (libmpv-инстанс тяжёлый, на mid-range без
///    лимита ListView с N видео сразу запустит N плееров).
/// 3. **Negative cache.** Если экстракция упала или вернула пустой кадр,
///    в этой сессии не пробуем снова (иначе scroll туда-обратно спамил бы
///    failure-логи).
///
/// **Сам Player и `screenshot()` теперь живут в виджете `_VideoPosterImage`
/// в `pages/chat/events/video_player.dart`**: media_kit `screenshot-raw video`
/// в headless-режиме на macOS отдаёт пустой буфер — VO mpv заполняется
/// только когда `Video`-виджет реально в дереве и Flutter compositor тикает
/// render-callback. Прошлая версия класса вызывала `Player.screenshot()`
/// сама и стабильно получала чёрный JPEG 42614 байт на любой настройке
/// (HW/SW accel, разные задержки — байт-в-байт одна и та же заглушка).
class VideoPosterCache {
  VideoPosterCache._();
  static final VideoPosterCache instance = VideoPosterCache._();

  Directory? _dir;
  final Set<String> _negative = {};

  // Глобальный semaphore на 1 экстракцию. Каждый виджет, готовый запускать
  // libmpv, дёргает `acquireSlot`, ждёт пока освободится прошлый, после
  // screenshot вызывает `release()` на полученном токене.
  Future<void> _tail = Future.value();

  Future<Directory> _ensureDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final tmp = await getTemporaryDirectory();
    final d = Directory('${tmp.path}/liza_video_posters');
    if (!await d.exists()) {
      await d.create(recursive: true);
    }
    _dir = d;
    return d;
  }

  /// Поддерживает ли платформа/событие экстракцию вообще.
  /// Web и E2EE — нет: ради одного кадра пришлось бы качать+расшифровывать
  /// весь blob. Sending-события — пока нет mxc URL, попробуем позже,
  /// после sync (виджет переподпишется через didUpdateWidget).
  bool isSupported(Event event) {
    if (kIsWeb) return false;
    if (event.isAttachmentEncrypted) return false;
    if (!event.status.isSent) return false;
    return true;
  }

  /// Возвращает файл-постер с диска, если он уже был извлечён в эту или
  /// прошлую сессию. `null` если не на диске.
  Future<File?> getCached(Event event) async {
    if (kIsWeb || event.isAttachmentEncrypted) return null;
    final id = _safeId(event.eventId);
    final dir = await _ensureDir();
    final file = File('${dir.path}/$id.jpg');
    if (await file.exists()) return file;
    return null;
  }

  bool isNegative(Event event) => _negative.contains(_safeId(event.eventId));

  void markNegative(Event event) {
    _negative.add(_safeId(event.eventId));
  }

  /// Снимает negative-метку — для ручного retry постера (`_VideoPosterImage`).
  /// Без сброса повторная попытка немедленно вернулась бы из `_bootstrap` по
  /// негативному guard'у (no-op). Возвращает `true`, если метка была снята.
  bool clearNegative(Event event) => _negative.remove(_safeId(event.eventId));

  /// Атомарно сохраняет байты на диск, возвращает результирующий файл.
  Future<File> storeBytes(Event event, Uint8List bytes) =>
      storeBytesForId(event.eventId, bytes);

  /// То же, но по «сырому» id события. Нужен при ОТПРАВКЕ: постер уже добыт из
  /// локального файла, а событие в этот момент — пре-эмитнутый placeholder с
  /// `eventId == txid`. Положив кадр сюда, мы даём `_VideoPosterImage` показать
  /// его сразу: `_bootstrap` спрашивает [getCached] ПЕРВЫМ шагом, ещё до гейта
  /// [isSupported], который отсекает sending-события.
  Future<File> storeBytesForId(String eventId, Uint8List bytes) async {
    // Симметрично isSupported/getCached: на Web нет ни path_provider, ни
    // файловой системы — без гарда здесь летел MissingPluginException.
    if (kIsWeb) {
      throw UnsupportedError('VideoPosterCache: на Web диска нет');
    }
    final id = _safeId(eventId);
    final dir = await _ensureDir();
    final file = File('${dir.path}/$id.jpg');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
    return file;
  }

  /// [storeBytesForId] для пути ОТПРАВКИ: кэш постера — только оптимизация
  /// пре-эмит-пузыря, поэтому его сбой (Web, полный диск, нет прав) не имеет
  /// права срывать отправку видео. `false` — постер не сохранён.
  /// LABA-2625: безусловная запись роняла отправку любого видео в Web.
  Future<bool> storeBytesForIdBestEffort(
    String eventId,
    Uint8List bytes,
  ) async {
    if (kIsWeb) return false;
    try {
      await storeBytesForId(eventId, bytes);
      return true;
    } catch (e, s) {
      Logs().w('Video poster cache: запись для $eventId не удалась', e, s);
      return false;
    }
  }

  /// Резервирует слот в semaphore. Caller должен вызвать `release()` на
  /// возвращённом токене (через try/finally), иначе очередь встанет.
  ///
  /// Если виджет успел dispos-нуться пока ждал слот, всё равно надо
  /// release-нуть — это разблокирует следующего в очереди.
  Future<VideoPosterSlot> acquireSlot() async {
    final prev = _tail;
    final completer = Completer<void>();
    _tail = completer.future;
    await prev;
    return VideoPosterSlot._(completer);
  }

  /// EventId начинается с `$` и может содержать `:` / `/` / `+` —
  /// `Uri.encodeComponent` даёт безопасное имя файла.
  static String _safeId(String eventId) {
    return Uri.encodeComponent(eventId);
  }
}

/// Токен слота в `VideoPosterCache._tail`-семафоре. Освобождать **строго
/// один раз** через [release] (повторный вызов безопасен — completer
/// проверяет isCompleted).
class VideoPosterSlot {
  VideoPosterSlot._(this._completer);
  final Completer<void> _completer;

  void release() {
    if (!_completer.isCompleted) _completer.complete();
  }
}
