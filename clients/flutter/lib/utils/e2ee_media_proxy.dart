import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
// ignore: depend_on_referenced_packages
import 'package:vodozemac/vodozemac.dart';
import 'package:matrix/encryption/utils/base64_unpadded.dart';

/// Локальный HTTP-прокси для потокового воспроизведения E2EE-вложений.
///
/// Проблема: зашифрованные видео в Matrix требуют полного скачивания и
/// расшифровки перед воспроизведением (24+ МБ в RAM). На мобильных это
/// ненадёжно — download рвётся при уходе в фон, пользователь ждёт 20+ сек.
///
/// Решение: поднимаем локальный HTTP-сервер на 127.0.0.1:0. media_kit (libmpv)
/// шлёт HTTP-запросы (в том числе Range) на localhost. Прокси:
/// 1. Скачивает зашифрованные чанки с Synapse
/// 2. Расшифровывает AES-256-CTR потоково (без загрузки всего файла в RAM)
/// 3. Отдаёт расшифрованные байты плееру
///
/// AES-CTR позволяет расшифровывать произвольный offset: counter = IV + offset/16.
/// Это даёт seek без перечитывания всего файла.
class E2eeMediaProxy {
  HttpServer? _server;
  // Гард идемпотентности: два параллельных ensureStarted() (быстрая смена видео /
  // две страницы карусели) без него оба проходили `_server != null` до завершения
  // первого bind → второй HttpServer перезаписывал _server, первый утекал (fd).
  Future<void>? _starting;
  final _sessions = <String, _ProxySession>{};

  /// Один persistent HTTP-клиент на всё время жизни прокси. Раньше
  /// [_serveDecrypted] поднимал `HttpClient()` на КАЖДЫЙ запрос и закрывал в
  /// finally — при moov-в-хвосте libmpv делает серию Range-прыжков к концу
  /// файла, и каждый прыжок = отдельный TLS-handshake к Synapse/MMR. Это и есть
  /// латентность «час по чайной ложке» на LTE. Один клиент переиспользует
  /// keep-alive соединение между Range-запросами (KILLER-2).
  HttpClient? _upstreamClient;

  /// Singleton
  static final E2eeMediaProxy instance = E2eeMediaProxy._();
  E2eeMediaProxy._();

  /// AES-CTR примитив. В проде — vodozemac (`CryptoUtils.aesCtr`). Инъектируется
  /// в тестах: реальный AES живёт в нативной либе vodozemac (в host-`flutter test`
  /// не грузится), поэтому логику стриминга/Range/counter-реконструкции
  /// (`_serveDecrypted`/[_adjustIv]) проверяем детерминированным шифром-заглушкой,
  /// а сам AES — device-flow.
  @visibleForTesting
  static Uint8List Function({
    required Uint8List input,
    required Uint8List key,
    required Uint8List iv,
  }) aesCtrImpl = CryptoUtils.aesCtr;

  /// Базовый URL прокси (напр. http://127.0.0.1:54321).
  /// null если сервер не запущен.
  String? get baseUrl {
    final s = _server;
    if (s == null) return null;
    return 'http://127.0.0.1:${s.port}';
  }

  /// Запустить прокси-сервер, если ещё не запущен. Идемпотентно и безопасно при
  /// параллельных вызовах: все ждут один и тот же bind (гард `_starting`).
  Future<void> ensureStarted() => _starting ??= _doStart();

  Future<void> _doStart() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _upstreamClient = HttpClient();
    Logs().i('E2eeMediaProxy started on port ${server.port}');
    // _handleRequest — Future<void>, а не `async void`: иначе исключение при
    // request.response.close() (клиент уже отвалился) уходит в необработанные
    // Future-ошибки зоны, минуя логи (M-5 flutter-quality). Ловим через catchError.
    server.listen(
      (req) => unawaited(_handleRequest(req).catchError((Object e, StackTrace s) {
        Logs().e('E2eeMediaProxy unhandled', e, s);
      })),
    );
  }

  /// Резолвит authenticated-media download-URI зашифрованного вложения [event].
  ///
  /// НЕ через `event.getAttachmentUri()` — тот по дизайну SDK возвращает null для
  /// `isAttachmentEncrypted` («can't url-thumbnail in encrypted rooms»,
  /// `matrix/event.dart`), из-за чего E2EE-прокси-путь раньше ВСЕГДА бросал и падал
  /// в полное скачивание (мёртвый код). `attachmentMxcUrl` для E2EE читает
  /// `content['file']['url']`; `getDownloadUri` строит authenticated
  /// `/_matrix/client/v1/media/download/…` (учитывает MMR-роутинг прод-хоста) —
  /// идентично тому, что SDK делает внутри `downloadAndDecryptAttachment`.
  @visibleForTesting
  static Future<Uri> resolveE2eeDownloadUri(Event event) async {
    final mxcUrl = event.attachmentMxcUrl;
    if (mxcUrl == null) {
      throw VideoProxyException(
        'attachmentMxcUrl is null for ${event.eventId}',
      );
    }
    return mxcUrl.getDownloadUri(event.room.client);
  }

  /// Зарегистрировать E2EE-сессию для воспроизведения.
  /// Возвращает URL вида `http://127.0.0.1:PORT/SESSION_ID`.
  Future<String> registerSession({
    required Event event,
  }) async {
    await ensureStarted();

    // URL для скачивания зашифрованного вложения (authenticated media).
    final downloadUri = await resolveE2eeDownloadUri(event);

    // Ключ/IV извлекаем через null-safe tryGet — жёсткие касты `as Map` роняли
    // прокси `TypeError`-ом на частичном/битом `content['file']` (частичный sync
    // до завершения E2EE-декрипта), минуя контролируемый VideoProxyException.
    final content = event.content;
    final fileMap = content.tryGetMap<String, Object?>('file');
    if (fileMap == null) {
      throw VideoProxyException('content["file"] missing or not a map');
    }
    final keyMap = fileMap.tryGetMap<String, Object?>('key');
    final k = keyMap?.tryGet<String>('k');
    final iv = fileMap.tryGet<String>('iv');
    if (k == null || iv == null) {
      throw VideoProxyException('E2EE key or iv missing in file map');
    }
    final info = content.tryGetMap<String, dynamic>('info');
    final fileSize = info?.tryGet<int>('size') ?? 0;
    final mimetype = info?.tryGet<String>('mimetype') ?? 'video/mp4';

    // Декодируем ключ и IV из base64url/base64
    final keyBytes = base64decodeUnpadded(base64.normalize(k));
    final ivBytes = base64decodeUnpadded(base64.normalize(iv));

    // sessionId = сам eventId (уникален). В URL кодируем через encodeComponent,
    // в map ключ — сырой eventId: `request.uri.pathSegments.first` возвращает
    // percent-ДЕКОДИРОВАННЫЙ сегмент → совпадёт с сырым ключом. Прежний
    // `eventId.hashCode.abs()` имел патологию abs(int.minValue)<0 и риск коллизии.
    final sessionId = event.eventId;
    _sessions[sessionId] = _ProxySession(
      downloadUri: downloadUri,
      accessToken: event.room.client.accessToken,
      keyBytes: keyBytes,
      ivBytes: ivBytes,
      fileSize: fileSize,
      mimetype: mimetype,
    );

    final url = '$baseUrl/${Uri.encodeComponent(sessionId)}';
    Logs().i('E2eeMediaProxy session registered: $url '
        '(size=$fileSize, mime=$mimetype)');
    return url;
  }

  /// Удалить сессию (при dispose плеера).
  void removeSession(String sessionId) {
    _sessions.remove(sessionId);
  }

  /// Тест-only: зарегистрировать сессию напрямую из явных параметров (в обход
  /// [Event]/`getDownloadUri`), чтобы прогнать AES-CTR стрим-путь
  /// [_serveDecrypted]/[_adjustIv] против фейкового upstream. Возвращает
  /// прокси-URL. Прод-код этот метод не использует.
  @visibleForTesting
  String registerRawSessionForTest({
    required Uri downloadUri,
    required Uint8List keyBytes,
    required Uint8List ivBytes,
    required int fileSize,
    String? accessToken,
    String mimetype = 'video/mp4',
    String sessionId = 'test-session',
  }) {
    _sessions[sessionId] = _ProxySession(
      downloadUri: downloadUri,
      accessToken: accessToken,
      keyBytes: keyBytes,
      ivBytes: ivBytes,
      fileSize: fileSize,
      mimetype: mimetype,
    );
    return '$baseUrl/${Uri.encodeComponent(sessionId)}';
  }

  /// Остановить прокси.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _starting = null; // разрешить повторный ensureStarted после остановки
    _upstreamClient?.close(force: true);
    _upstreamClient = null;
    _sessions.clear();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      final sessionId = request.uri.pathSegments.isNotEmpty
          ? request.uri.pathSegments.first
          : '';
      final session = _sessions[sessionId];

      if (session == null) {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('Unknown session');
        await request.response.close();
        return;
      }

      await _serveDecrypted(request, session);
    } catch (e, s) {
      Logs().e('E2eeMediaProxy error', e, s);
      try {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      } catch (_) {}
    }
  }

  Future<void> _serveDecrypted(
    HttpRequest request,
    _ProxySession session,
  ) async {
    final fileSize = session.fileSize;

    // Парсим Range header от libmpv
    var rangeStart = 0;
    var rangeEnd = fileSize > 0 ? fileSize - 1 : 0;
    var isRange = false;

    final rangeHeader = request.headers.value('range');
    if (rangeHeader != null && fileSize > 0) {
      final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
      if (match != null) {
        isRange = true;
        rangeStart = int.parse(match.group(1)!);
        final endStr = match.group(2);
        if (endStr != null && endStr.isNotEmpty) {
          rangeEnd = int.parse(endStr);
        }
      }
    }

    // Настраиваем response headers
    final response = request.response;
    response.headers.contentType =
        ContentType.parse(session.mimetype);

    if (fileSize > 0) {
      response.headers.set('accept-ranges', 'bytes');
      if (isRange) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          'content-range',
          'bytes $rangeStart-$rangeEnd/$fileSize',
        );
        response.contentLength = rangeEnd - rangeStart + 1;
      } else {
        response.statusCode = HttpStatus.ok;
        response.contentLength = fileSize;
      }
    } else {
      response.statusCode = HttpStatus.ok;
    }

    // AES-CTR: зашифрованные и расшифрованные байты имеют одинаковый offset
    // (потоковый шифр без padding). Но расшифровка работает в 16-байтных блоках,
    // поэтому при невыровненном rangeStart выравниваем Range-запрос к Synapse
    // вниз до границы блока и отбрасываем лишние байты из начала ответа.
    final alignedStart = rangeStart - (rangeStart % 16);

    // Persistent-клиент (keep-alive между Range-прыжками). Fallback на
    // разовый клиент, если прокси уже остановлен (edge-гонка с stop()).
    final httpClient = _upstreamClient;
    final ephemeral = httpClient == null ? HttpClient() : null;
    final client = httpClient ?? ephemeral!;
    // Хвост Range-запроса: известный размер → до rangeEnd, иначе открытый
    // (`bytes=N-`). Один формат и для первого запроса, и для resume-переоткрытий.
    final rangeEndHeader = fileSize > 0 ? '$rangeEnd' : '';
    var loggedFirst = false;
    try {
      // Резумируемый upstream: при обрыве соединения (Synapse/MMR / мобильный NAT
      // рвёт TCP) переоткрывает GET с Range от места разрыва, а НЕ рестартит с 0.
      // Это ядро фикса 2026-08-31 — 169МБ E2EE докачивается на флаки-мобиле
      // (лог Романа: `Connection closed while receiving data` повторяясь минутами
      // = прежний рестарт-с-нуля). AES-CTR counter в decryptCtrStream считается по
      // позиции в непрерывном потоке — переподключения ему прозрачны.
      final encryptedStream = _resumableUpstream(
        client: client,
        session: session,
        startOffset: alignedStart,
        rangeEndHeader: rangeEndHeader,
      );
      // Диагностика β vs γ: первые 16 РАСШИФРОВАННЫХ байт. Валидный `ftyp…`
      // (ASCII 4-8) → декрипт корректен, «Reading plaintext playlist» = γ
      // (moov-в-хвосте). Мусор → β (неверный counter). НЕ логируем ключ/iv.
      await for (final out in decryptCtrStream(
        encryptedBody: encryptedStream,
        keyBytes: session.keyBytes,
        baseIv: session.ivBytes,
        rangeStart: rangeStart,
      )) {
        if (!loggedFirst && out.isNotEmpty) {
          loggedFirst = true;
          final probe = out.take(16).toList();
          final ascii = String.fromCharCodes(
            probe.map((b) => (b >= 0x20 && b < 0x7f) ? b : 0x2e),
          );
          Logs().i(
            'E2eeMediaProxy first-bytes[${session.mimetype}]: '
            'rangeStart=$rangeStart first16=$probe ascii="$ascii"',
          );
        }
        response.add(out);
      }
      await response.close();
    } on SocketException {
      // mpv закрыл соединение к прокси (seek / смена видео / dispose viewer) —
      // штатно, НЕ ошибка. Отмена await-for отменяет генератор _resumableUpstream
      // вместе с подпиской на upstream → сокет закрывается, не течёт (фикс C-1).
      // Исчерпание resume-ретраев прилетает как VideoProxyException (не Socket) и
      // пройдёт наверх в _handleRequest → терминальная 500 (не глушится здесь).
      Logs().v('E2eeMediaProxy: client closed connection (seek/dispose)');
    } finally {
      ephemeral?.close();
    }
  }

  /// Максимум ПОДРЯД-неудачных переоткрытий upstream (без прогресса) до
  /// терминальной ошибки. Обрыв на мобиле recoverable, но не бесконечно: при
  /// перманентном 404/500/refused цикл не должен крутиться вечно. Счётчик
  /// сбрасывается на каждом полученном байте — реальная докачка 169МБ переживает
  /// сколько угодно resets, пока идёт прогресс.
  static const _maxUpstreamRetries = 6;

  /// Резумируемый поток зашифрованных байт от [startOffset] до конца диапазона
  /// ([rangeEndHeader] — хвост `bytes=N-<end>`). При обрыве чтения upstream
  /// (HttpException/SocketException со стороны Synapse/MMR) переоткрывает GET с
  /// Range от места разрыва (byte-exact) и продолжает БЕЗ рестарта с нуля →
  /// consumer видит непрерывный поток, AES-CTR counter остаётся верным. После
  /// [_maxUpstreamRetries] неудач ПОДРЯД (без прогресса) бросает
  /// VideoProxyException (терминал, не бесконечный цикл). Отмена генератора
  /// (mpv закрыл прокси) отменяет подписку на upstream — сокет закрывается.
  Stream<List<int>> _resumableUpstream({
    required HttpClient client,
    required _ProxySession session,
    required int startOffset,
    required String rangeEndHeader,
  }) async* {
    var pos = startOffset;
    var retries = 0;
    while (true) {
      try {
        final req = await client.getUrl(session.downloadUri);
        if (session.accessToken != null) {
          req.headers.set('authorization', 'Bearer ${session.accessToken}');
        }
        req.headers.set('range', 'bytes=$pos-$rangeEndHeader');
        final upstream = await req.close();
        await for (final chunk in upstream) {
          pos += chunk.length;
          retries = 0; // есть прогресс → обнуляем счётчик подряд-неудач
          yield chunk;
        }
        return; // upstream дочитан штатно
      } catch (e) {
        // Только сетевые обрывы upstream ретраим; прочее (в т.ч. отмена
        // генератора) — наверх. VideoProxyException терминальна.
        if (e is! HttpException && e is! SocketException) rethrow;
        if (++retries > _maxUpstreamRetries) {
          throw VideoProxyException(
            'upstream exhausted after $_maxUpstreamRetries retries at byte $pos: $e',
          );
        }
        Logs().w(
          'E2eeMediaProxy upstream reconnect at byte $pos (retry $retries): $e',
        );
        await Future<void>.delayed(Duration(milliseconds: 200 * retries));
      }
    }
  }

  /// Потоковая AES-CTR расшифровка [encryptedBody] — ответа upstream,
  /// начинающегося с байта, выровненного вниз до 16-байтной границы от
  /// [rangeStart]. Выдаёт расшифрованные байты, начиная ИМЕННО с [rangeStart]
  /// (обрезая `byteOffset` из первого блока). Вынесена из [_serveDecrypted] и
  /// не зависит от HTTP — тестируется без сети (в host-`flutter test` реальный
  /// HttpClient замокан). Правильность counter/выравнивания критична (R1):
  /// ошибка на один блок = мусор с середины файла.
  @visibleForTesting
  static Stream<List<int>> decryptCtrStream({
    required Stream<List<int>> encryptedBody,
    required Uint8List keyBytes,
    required Uint8List baseIv,
    required int rangeStart,
  }) async* {
    final blockOffset = rangeStart ~/ 16;
    final byteOffset = rangeStart % 16;
    // IV для первого выданного блока: baseIv + blockOffset (позиция в файле).
    final adjustedIv = _adjustIv(baseIv, blockOffset);

    // Счётчик обработанных ЗАШИФРОВАННЫХ байт — для пересчёта counter. Именно
    // encrypted (не output), чтобы counter корректно инкрементировался.
    var encryptedProcessed = 0;
    var pending = <int>[];
    var isFirstChunk = true;

    await for (final chunk in encryptedBody) {
      pending.addAll(chunk);

      final alignedLen = (pending.length ~/ 16) * 16;
      if (alignedLen == 0) continue;

      final toDecrypt = Uint8List.fromList(pending.sublist(0, alignedLen));
      pending = pending.sublist(alignedLen);

      final chunkIv = _adjustIv(adjustedIv, encryptedProcessed ~/ 16);
      final decrypted = aesCtrImpl(
        input: toDecrypt,
        key: keyBytes,
        iv: chunkIv,
      );
      encryptedProcessed += toDecrypt.length;

      yield (isFirstChunk && byteOffset > 0)
          ? decrypted.sublist(byteOffset)
          : decrypted;
      isFirstChunk = false;
    }

    // Последний неполный блок (< 16 байт).
    if (pending.isNotEmpty) {
      final toDecrypt = Uint8List.fromList(pending);
      final chunkIv = _adjustIv(adjustedIv, encryptedProcessed ~/ 16);
      final decrypted = aesCtrImpl(
        input: toDecrypt,
        key: keyBytes,
        iv: chunkIv,
      );
      yield (isFirstChunk && byteOffset > 0)
          ? decrypted.sublist(byteOffset)
          : decrypted;
    }
  }

  /// Вычислить IV с добавленным block offset для AES-CTR.
  ///
  /// Matrix spec: IV — 16 байт = 8 байт random + 8 байт counter (big-endian).
  /// Counter начинает с 0 и увеличивается на 1 для каждого 16-байтного блока.
  /// Для seek на offset N: counter = N / 16.
  @visibleForTesting
  static Uint8List adjustIvForTest(Uint8List baseIv, int blockOffset) =>
      _adjustIv(baseIv, blockOffset);

  static Uint8List _adjustIv(Uint8List baseIv, int blockOffset) {
    if (blockOffset == 0) return baseIv;

    final adjusted = Uint8List.fromList(baseIv);
    // Прибавляем blockOffset к 64-bit counter в байтах 8-15 (big-endian)
    var carry = blockOffset;
    for (var i = 15; i >= 8 && carry > 0; i--) {
      final sum = adjusted[i] + (carry & 0xFF);
      adjusted[i] = sum & 0xFF;
      carry = (carry >> 8) + (sum >> 8);
    }
    return adjusted;
  }
}

class _ProxySession {
  final Uri downloadUri;
  final String? accessToken;
  final Uint8List keyBytes;
  final Uint8List ivBytes;
  final int fileSize;
  final String mimetype;

  _ProxySession({
    required this.downloadUri,
    required this.accessToken,
    required this.keyBytes,
    required this.ivBytes,
    required this.fileSize,
    required this.mimetype,
  });
}

class VideoProxyException implements Exception {
  final String message;
  VideoProxyException(this.message);
  @override
  String toString() => 'VideoProxyException: $message';
}
