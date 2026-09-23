import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' show ClientException;
import 'package:matrix/matrix.dart';

/// Классификация ошибок ЗАГРУЗКИ медиа: терминальная (повтор бессмысленен) или
/// транзиентная (повтор осмыслен). Чистые функции без Flutter/BuildContext —
/// тестируются `dart test` (страж `RL-upload-terminal-error-no-retry`).
///
/// Зачем: SDK `room.sendFileEvent` (matrix 4.1.0) в цикле `while` ретраит
/// заливку каждую 1с до `sendTimelineEventTimeout` на ЛЮБОЙ НЕ-`MatrixException`
/// ошибке. Терминальный ответ сервера с не-JSON/пустым телом (413 от nginx,
/// обрезанный ответ MMR) НЕ распознаётся как `MatrixException` → уходит в
/// retry-ветку → «шторм» бессмысленных повторов. [parseUploadError] превращает
/// такой ответ в `MatrixException`, чтобы SDK трактовал его терминально.
enum UploadErrorKind { terminal, transient }

/// Прочитанные для заливки байты оказались пусты при ненулевом размере файла.
/// На Web `xfile.readAsBytes()` (FileReader.readAsArrayBuffer) грузит файл в
/// память вкладки целиком; на очень крупном файле вкладка Chrome упирается в
/// лимит кучи → OOM → возвращается пустой буфер БЕЗ исключения. Без гейта клиент
/// молча слал `0` байт, сервер сохранял `media_length=0`, а событие рекламировало
/// реальный размер → фантомное медиа, не воспроизводимое НИ У КОГО (инцидент
/// 2026-09-01, спека …-web-upload-zero-byte). Терминальна (повтор не поможет).
class EmptyMediaBytesException implements Exception {
  /// Заявленный размер файла (метаданные), при котором прочитано 0 байт.
  final int declaredSize;
  const EmptyMediaBytesException(this.declaredSize);
  @override
  String toString() =>
      'EmptyMediaBytesException(declaredSize=$declaredSize, read 0 bytes)';
}

/// Терминальные upstream-статусы upload, на которых повтор бессмысленен:
/// `403` (квота/доступ) и `413` (файл слишком большой). НЕ включает `429`
/// (`M_LIMIT_EXCEEDED` — rate-limit, ждём `retry_after_ms` и повторяем сами) и
/// НЕ включает `5xx` (временный сбой сервера — повтор осмыслен).
bool isTerminalUploadStatus(int statusCode) =>
    statusCode == 403 || statusCode == 413;

/// Для терминального upload-статуса ([isTerminalUploadStatus]) вернуть
/// `MatrixException`, чтобы SDK-цикл заливки трактовал ответ терминально (одна
/// попытка, `EventStatus.error`), а не ретраил минуту. Если тело — валидный
/// Matrix-JSON (`{"errcode":...}`), парсим его (сохраняя `retry_after_ms` и пр.);
/// иначе синтезируем по статусу (`413→M_TOO_LARGE`, `403→M_FORBIDDEN`).
///
/// Возвращает `null` для НЕ-терминальных статусов — вызывающий тогда возвращает
/// ответ нетронутым (SDK сам решит: `2xx` — успех, `5xx`/`429` — своя ветка).
MatrixException? parseUploadError(int statusCode, Uint8List body) {
  if (!isTerminalUploadStatus(statusCode)) return null;
  try {
    final decoded = jsonDecode(utf8.decode(body));
    if (decoded is Map<String, Object?> && decoded.containsKey('errcode')) {
      return MatrixException.fromJson(decoded);
    }
  } catch (_) {
    // тело не JSON (HTML/пустое) — синтезируем ниже
  }
  return MatrixException.fromJson({
    'errcode': statusCode == 413 ? 'M_TOO_LARGE' : 'M_FORBIDDEN',
    'error': 'Upload rejected by server (HTTP $statusCode)',
  });
}

/// Классифицировать пойманную при отправке ошибку.
///
/// - `MatrixException` (кроме `M_LIMIT_EXCEEDED`) и `FileTooBigMatrixException`
///   → **terminal** (показать причину, не ретраить).
/// - `M_LIMIT_EXCEEDED` (429 rate-limit) → **transient** (ветка ожидания
///   `retry_after_ms` в `send_file_dialog` повторяет сама).
/// - `ClientException` (оборачивает `SocketException`/broken-pipe), сырой
///   `SocketException`/`TlsException`/`HandshakeException` (сеть в кейсе
///   Алексея: `Connection attempt cancelled`, DNS `errno=7`) и
///   `TimeoutException` → **transient** (сетевой сбой — повтор осмыслен).
/// - `FileSystemException` (диск переполнен/битый файл, ENOSPC) → **terminal**:
///   возврат связи места на диске не добавит.
UploadErrorKind classifyUploadError(Object e) {
  if (e is EmptyMediaBytesException) return UploadErrorKind.terminal;
  if (e is FileTooBigMatrixException) return UploadErrorKind.terminal;
  if (e is MatrixException) {
    if (e.error == MatrixError.M_LIMIT_EXCEEDED) {
      return UploadErrorKind.transient;
    }
    return UploadErrorKind.terminal;
  }
  // Дисковая/файловая ошибка — ДО общей сетевой ветки: FileSystemException
  // is IOException, и без явной проверки провалилась бы в сеть (ложно
  // transient → бесполезный ретрай при полном диске).
  if (e is FileSystemException) return UploadErrorKind.terminal;
  if (e is ClientException ||
      e is SocketException ||
      e is TlsException ||
      e is TimeoutException) {
    return UploadErrorKind.transient;
  }
  // Неизвестное исключение — не ретраим вслепую (как прежний
  // `_isTransientUploadError`, возвращавший false для всего, кроме сети).
  return UploadErrorKind.terminal;
}

/// Класс причины сбоя ОТПРАВКИ для причинно-конкретного сообщения пользователю
/// (Дыра 3): сеть / сервер / диск. Отдельно от [UploadErrorKind]
/// (terminal/transient — решение «ретраить»), потому что для СООБЩЕНИЯ важно
/// РАЗЛИЧАТЬ сервер и диск (оба terminal), иначе диск-переполнение лживо
/// показывается как «нет соединения» (`localized_exception_extension` без этой
/// ветки клал `FileSystemException` в `IOException`→«нет сети»).
///
/// Чистая функция без `BuildContext` — тестируется `dart test`.
enum SendErrorCause { network, server, disk, unknown }

SendErrorCause classifySendErrorCause(Object e) {
  // Диск — ПЕРВЫМ: FileSystemException is IOException, иначе ушёл бы в network.
  if (e is FileSystemException) return SendErrorCause.disk;
  // Пустой прочитанный буфер — клиентская причина (браузер не осилил файл), не
  // сеть и не сервер.
  if (e is EmptyMediaBytesException) return SendErrorCause.unknown;
  if (e is FileTooBigMatrixException) return SendErrorCause.server;
  if (e is MatrixException) return SendErrorCause.server;
  if (e is ClientException ||
      e is SocketException ||
      e is TlsException ||
      e is TimeoutException) {
    return SendErrorCause.network;
  }
  return SendErrorCause.unknown;
}
