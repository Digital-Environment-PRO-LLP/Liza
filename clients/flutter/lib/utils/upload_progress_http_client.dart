import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:liza/utils/upload_error_classifier.dart';
import 'package:liza/utils/upload_progress_tracker.dart';

/// HTTP-клиент, считающий реальный прогресс отдачи тела запроса при
/// загрузке медиа в Matrix (`POST /_matrix/media/.../upload`).
///
/// matrix-dart-sdk 4.1.0 не отдаёт прогресс upload (нет колбэка в
/// `Client.uploadContent`), поэтому перехватываем на HTTP-уровне:
/// оборачиваем тело запроса потоком-счётчиком.
///
/// **Важно — переразбивка тела на чанки.** `room.sendFileEvent` отдаёт
/// файл одним `Uint8List`; `BaseRequest.finalize()` эмитит его **одним
/// событием** на весь объём. Без переразбивки `.map`-счётчик сработал бы
/// один раз и прыгнул бы 0→100% мгновенно (ровно баг «показывает 100%, а
/// по факту не загрузилось»). Поэтому режем тело на чанки по 64 КБ:
/// `IOClient` тянет их со скоростью сокета (backpressure — `addStream`
/// у `IOSink` ставит источник на паузу, пока сокет не освободится), и
/// процент растёт постепенно, отражая фактическую отдачу.
///
/// Прогресс уходит в [UploadProgressTracker] для активного `txid` — его
/// выставляет `send_file_dialog` через `markActive(...)` перед отправкой.
///
/// На Web клиент в цепочку не ставится: `BrowserClient` буферизует тело
/// целиком перед XHR, счётчик мгновенно дошёл бы до 100%. Там остаётся
/// псевдо-прогресс (см. `createHTTPClient`).
class UploadProgressHttpClient extends http.BaseClient {
  UploadProgressHttpClient(this._inner);

  final http.Client _inner;

  /// Мелкие upload-ы (thumbnail видео, аватары) не трекаем — прогресс по
  /// ним только мигал бы. Порог — 1 МБ.
  static const int _minTrackedBytes = 1024 * 1024;

  /// Размер чанка переразбивки тела. 64 КБ — мелко достаточно для плавного
  /// прогресса, крупно достаточно чтобы не плодить события.
  static const int _chunkSize = 64 * 1024;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final total = request.contentLength;
    // Отмену проверяем для ЛЮБОЙ media-загрузки, даже мелкой (< _minTrackedBytes
    // не трекаем прогресс, но отменить обязаны): если крестик нажат до начала
    // отдачи — рвём терминально, не доходя до `_inner.send`.
    if (_isMediaUpload(request) &&
        UploadProgressTracker.instance.isActiveCancelled) {
      throw MatrixException.fromJson({
        'errcode': 'M_UNKNOWN',
        'error': 'Upload canceled by user',
      });
    }
    if (total == null ||
        total < _minTrackedBytes ||
        request.finalized ||
        !_isMediaUpload(request)) {
      return _sendAndGuardTerminal(request, request);
    }

    var sent = 0;
    final counted = http.ByteStream(
      _rechunk(request.finalize()).map((chunk) {
        // Пользователь нажал крестик на бабле → обрываем отдачу. Бросаем
        // именно MatrixException: retry-цикл `room.sendFileEvent` ловит её
        // как терминальную (ставит EventStatus.error и пробрасывает дальше),
        // тогда как обычное исключение он бы ретраил до
        // `sendTimelineEventTimeout`. См. UploadProgressTracker.requestCancel.
        if (UploadProgressTracker.instance.isActiveCancelled) {
          throw MatrixException.fromJson({
            'errcode': 'M_UNKNOWN',
            'error': 'Upload canceled by user',
          });
        }
        sent += chunk.length;
        UploadProgressTracker.instance.reportActiveProgress(sent, total);
        return chunk;
      }),
    );
    final proxy = _ProxyRequest(request.method, request.url, counted)
      ..headers.addAll(request.headers)
      ..followRedirects = request.followRedirects
      ..maxRedirects = request.maxRedirects
      ..persistentConnection = request.persistentConnection
      ..contentLength = total;
    return _sendAndGuardTerminal(request, proxy);
  }

  /// Отправить [toSend] и перехватить ТЕРМИНАЛЬНЫЙ upstream-ответ upload
  /// (`403`/`413`): вычитать тело, бросить `MatrixException`, чтобы SDK-цикл
  /// `sendFileEvent` ушёл в терминальную ветку (одна попытка, `EventStatus.error`),
  /// а не ретраил минуту на не-JSON/пустом теле. `2xx` и прочие статусы
  /// (`5xx`/`429`) возвращаются нетронутыми — стрим ответа читает сам SDK.
  ///
  /// broken-pipe (сокет рвётся ДО ответа) сюда не попадает: `_inner.send`
  /// бросит `ClientException` раньше — это транзиентное, ретрай уместен.
  Future<http.StreamedResponse> _sendAndGuardTerminal(
    http.BaseRequest request,
    http.BaseRequest toSend,
  ) async {
    final response = await _inner.send(toSend);
    if (_isMediaUpload(request) && isTerminalUploadStatus(response.statusCode)) {
      final body = await response.stream.toBytes();
      final matrixException = parseUploadError(response.statusCode, body);
      if (matrixException != null) throw matrixException;
    }
    return response;
  }

  @override
  void close() => _inner.close();

  /// Режет крупные чанки тела на куски по [_chunkSize]. `async*` сохраняет
  /// backpressure: когда `IOClient` приостанавливает потребление (сокет
  /// занят), генератор тоже встаёт на паузу — прогресс не убегает вперёд.
  static Stream<List<int>> _rechunk(Stream<List<int>> source) async* {
    await for (final chunk in source) {
      if (chunk.length <= _chunkSize) {
        yield chunk;
        continue;
      }
      for (var offset = 0; offset < chunk.length; offset += _chunkSize) {
        final end = offset + _chunkSize < chunk.length
            ? offset + _chunkSize
            : chunk.length;
        yield chunk.sublist(offset, end);
      }
    }
  }

  static bool _isMediaUpload(http.BaseRequest request) {
    final path = request.url.path;
    return path.contains('/_matrix/media/') &&
        (path.endsWith('/upload') || path.contains('/upload/'));
  }
}

/// `BaseRequest` с уже готовым телом: `finalize()` отдаёт переданный
/// поток-счётчик напрямую, сохраняя backpressure от потребителя.
class _ProxyRequest extends http.BaseRequest {
  _ProxyRequest(super.method, super.url, this._body);

  final http.ByteStream _body;

  @override
  http.ByteStream finalize() {
    super.finalize();
    return _body;
  }
}
