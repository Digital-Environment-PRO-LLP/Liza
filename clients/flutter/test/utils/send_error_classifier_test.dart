import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:matrix/matrix.dart';

import 'package:liza/utils/upload_error_classifier.dart';

/// Страж `RL-send-error-cause-classifier`: причинно-конкретная классификация
/// сбоя ОТПРАВКИ (Дыра 3) — сеть / сервер / диск. Ключевой red-proof: диск
/// (`FileSystemException`, ENOSPC) НЕ должен выдаваться за «нет сети» (он is
/// `IOException` и без явной disk-ветки провалился бы в network). Чистые
/// функции, без Flutter-среды.
void main() {
  group('classifySendErrorCause', () {
    // ledger:RL-send-error-cause-classifier
    test('AC:RL-send-error-cause-classifier/8 — сеть → network', () {
      expect(
        classifySendErrorCause(const SocketException('Connection cancelled')),
        SendErrorCause.network,
      );
      expect(
        classifySendErrorCause(ClientException('socket exception')),
        SendErrorCause.network,
      );
      expect(
        classifySendErrorCause(TimeoutException('timeout')),
        SendErrorCause.network,
      );
    });

    test('AC:RL-send-error-cause-classifier/9 — сервер (413/Matrix) → server',
        () {
      expect(
        classifySendErrorCause(FileTooBigMatrixException(11, 10)),
        SendErrorCause.server,
      );
      expect(
        classifySendErrorCause(
          MatrixException.fromJson(
            {'errcode': 'M_FORBIDDEN', 'error': 'no'},
          ),
        ),
        SendErrorCause.server,
      );
    });

    test(
        'AC:RL-send-error-cause-classifier/10 — диск (FileSystemException/ENOSPC) '
        '→ disk, НЕ network (red-proof: is IOException)', () {
      final diskFull = FileSystemException(
        'No space left on device',
        '/data/voice.ogg',
        OSError('No space left on device', 28),
      );
      expect(classifySendErrorCause(diskFull), SendErrorCause.disk);
      // Именно этот класс НЕ равен network — иначе диск лжёт «нет сети».
      expect(
        classifySendErrorCause(diskFull) == SendErrorCause.network,
        isFalse,
      );
    });
  });

  group('classifyUploadError (гейт авто-ретрая)', () {
    // ledger:RL-send-error-cause-classifier
    test(
        'AC:RL-send-error-cause-classifier/11 — диск = terminal (возврат связи '
        'места не добавит), сеть = transient, 413 = terminal', () {
      final diskFull = FileSystemException(
        'No space left on device',
        '',
        OSError('No space left on device', 28),
      );
      expect(classifyUploadError(diskFull), UploadErrorKind.terminal);
      expect(
        classifyUploadError(const SocketException('cancelled')),
        UploadErrorKind.transient,
      );
      expect(
        classifyUploadError(FileTooBigMatrixException(11, 10)),
        UploadErrorKind.terminal,
      );
    });
  });
}
