import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:matrix/matrix.dart';

import 'package:liza/utils/upload_error_classifier.dart';

/// Страж `RL-upload-terminal-error-no-retry`: терминальный upstream-ответ upload
/// (403 quota / 413 too-large) → одна попытка (`MatrixException`), а не минутный
/// retry-шторм SDK; при этом 5xx / сеть / 429-rate-limit / cancel — по-прежнему
/// НЕ терминальны. Чистые функции, без Flutter-среды.
void main() {
  Uint8List bytes(Object json) =>
      Uint8List.fromList(utf8.encode(jsonEncode(json)));

  group('parseUploadError', () {
    // ledger:RL-upload-terminal-error-no-retry
    test('AC:RL-upload-terminal-error-no-retry/1 — 403 с не-JSON телом → '
        'терминальный MatrixException (не обычный Exception)', () {
      final ex = parseUploadError(
        403,
        Uint8List.fromList(utf8.encode('<html>Forbidden</html>')),
      );
      expect(ex, isA<MatrixException>());
      expect(ex!.error, MatrixError.M_FORBIDDEN);
    });

    test('AC:RL-upload-terminal-error-no-retry/1 — 403 с JSON errcode → '
        'парсится, errcode сохранён', () {
      final ex = parseUploadError(
        403,
        bytes({'errcode': 'M_QUOTA_EXCEEDED', 'error': 'Quota Exceeded'}),
      );
      expect(ex, isA<MatrixException>());
      expect(ex!.errcode, 'M_QUOTA_EXCEEDED');
    });

    test('AC:RL-upload-terminal-error-no-retry/2 — 413 → терминальный '
        'M_TOO_LARGE', () {
      final ex = parseUploadError(413, Uint8List(0));
      expect(ex, isA<MatrixException>());
      expect(ex!.error, MatrixError.M_TOO_LARGE);
    });

    test('AC:RL-upload-terminal-error-no-retry/3 — 5xx → null '
        '(НЕ терминальный, SDK ретраит)', () {
      expect(parseUploadError(502, Uint8List(0)), isNull);
      expect(parseUploadError(503, Uint8List(0)), isNull);
    });

    test('AC:RL-upload-terminal-error-no-retry/4 — 429 → null '
        '(rate-limit, НЕ терминальный этим гейтом)', () {
      expect(parseUploadError(429, bytes({'errcode': 'M_LIMIT_EXCEEDED'})),
          isNull);
    });

    test('2xx → null (успех, стрим отдаём SDK нетронутым)', () {
      expect(parseUploadError(200, Uint8List(0)), isNull);
    });
  });

  group('classifyUploadError', () {
    test('AC:RL-upload-terminal-error-no-retry/1 — MatrixException → terminal',
        () {
      final ex = MatrixException.fromJson(
        {'errcode': 'M_FORBIDDEN', 'error': 'Quota Exceeded'},
      );
      expect(classifyUploadError(ex), UploadErrorKind.terminal);
    });

    test('AC:RL-upload-terminal-error-no-retry/4 — M_LIMIT_EXCEEDED → '
        'transient (ветка ожидания retryAfter жива)', () {
      final ex = MatrixException.fromJson({
        'errcode': 'M_LIMIT_EXCEEDED',
        'error': 'Too Many Requests',
        'retry_after_ms': 5000,
      });
      expect(classifyUploadError(ex), UploadErrorKind.transient);
      expect(ex.retryAfterMs, 5000);
    });

    test('AC:RL-upload-terminal-error-no-retry/6 — ClientException/Timeout → '
        'transient (сетевой обрыв — ретрай уместен)', () {
      expect(classifyUploadError(ClientException('Connection reset')),
          UploadErrorKind.transient);
      expect(classifyUploadError(TimeoutException('slow')),
          UploadErrorKind.transient);
    });
  });

  group('isTerminalUploadStatus', () {
    test('только 403 и 413 терминальны', () {
      expect(isTerminalUploadStatus(403), isTrue);
      expect(isTerminalUploadStatus(413), isTrue);
      expect(isTerminalUploadStatus(429), isFalse);
      expect(isTerminalUploadStatus(500), isFalse);
      expect(isTerminalUploadStatus(200), isFalse);
    });
  });

  // Фантомное 0-байтное медиа: пустой прочитанный буфер (Web-OOM) не должен
  // молча уходить на сервер. См. tests/registry/RL-zero-byte-media-upload-reject.md
  // ledger:RL-zero-byte-media-upload-reject
  group('EmptyMediaBytesException classification', () {
    test('AC:RL-zero-byte-media-upload-reject/1 — terminal (без ретрай-шторма)',
        () {
      expect(
        classifyUploadError(const EmptyMediaBytesException(556295632)),
        UploadErrorKind.terminal,
      );
    });

    test('AC:RL-zero-byte-media-upload-reject/2 — причина unknown (клиентская, '
        'не сеть/сервер)', () {
      expect(
        classifySendErrorCause(const EmptyMediaBytesException(556295632)),
        SendErrorCause.unknown,
      );
    });

    test('declaredSize сохранён в toString (для лога/диагностики)', () {
      expect(
        const EmptyMediaBytesException(556295632).toString(),
        contains('556295632'),
      );
    });
  });
}
