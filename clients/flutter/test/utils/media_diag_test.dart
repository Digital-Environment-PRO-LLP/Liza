import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/matrix_sdk_extensions/event_extension.dart';

/// ledger:RL-mediadiag-no-secret
///
/// Диагностика `[MediaDiag]` пишет на сбое медиа-загрузки одну структурную строку
/// (лог, который присылает Максим), чтобы ОДНОЗНАЧНО классифицировать причину
/// (усечение / порча / error-page-200 / сеть / отравленный кэш / gzip). Здесь
/// защищаем два инварианта, которые нельзя сломать:
///  1. БЕЗОПАСНОСТЬ: строка НЕ содержит секретов (ключ расшифровки `key.k`, `iv`,
///     Bearer-токен) — `buildMediaDiagLine` СТРУКТУРНО их не принимает.
///  2. КЛАССИФИКАЦИЯ: решающее правило (в т.ч. gzip-исключение усечения) даёт
///     верный класс — иначе по логу назовём не ту причину.
void main() {
  group('classifyMediaDiag — решающее правило причины', () {
    test('кэш-хит (callback не звался) → отравленный кэш, приоритет №1', () {
      // wasFromCache перекрывает всё остальное.
      expect(
        classifyMediaDiag(
          wasFromCache: true,
          statusCode: 200,
          contentLength: 100,
          receivedBytes: 50,
        ),
        MediaDiagClass.poisonedCache,
      );
    });

    test('нет HTTP-ответа + сетевое исключение → networkError', () {
      expect(
        classifyMediaDiag(
          wasFromCache: false,
          statusCode: null,
          errorType: 'SocketException',
        ),
        MediaDiagClass.networkError,
      );
    });

    test('HTTP не-200 → httpError', () {
      expect(
        classifyMediaDiag(wasFromCache: false, statusCode: 404),
        MediaDiagClass.httpError,
      );
    });

    test('200 + text/html на медиа → error-page-200', () {
      expect(
        classifyMediaDiag(
          wasFromCache: false,
          statusCode: 200,
          msgtype: 'm.audio',
          contentType: 'text/html; charset=utf-8',
        ),
        MediaDiagClass.errorPage200,
      );
    });

    test('получено < Content-Length БЕЗ content-encoding → усечение', () {
      expect(
        classifyMediaDiag(
          wasFromCache: false,
          statusCode: 200,
          msgtype: 'm.audio',
          contentType: 'application/octet-stream',
          contentLength: 100000,
          receivedBytes: 40000,
        ),
        MediaDiagClass.truncated,
      );
    });

    test('gzip: получено > Content-Length → НЕ усечение (страж MAJOR-5)', () {
      // Распакованные байты больше сжатого Content-Length — сравнение невалидно.
      expect(
        classifyMediaDiag(
          wasFromCache: false,
          statusCode: 200,
          msgtype: 'm.file',
          contentEncoding: 'gzip',
          contentLength: 40000,
          receivedBytes: 100000,
        ),
        isNot(MediaDiagClass.truncated),
      );
    });

    test('gzip + получено < Content-Length → всё равно НЕ усечение', () {
      // Даже при received<contentLength при gzip сравнение отключено.
      final cls = classifyMediaDiag(
        wasFromCache: false,
        statusCode: 200,
        msgtype: 'm.file',
        contentEncoding: 'gzip',
        contentLength: 100000,
        receivedBytes: 40000,
        expectedCiphertextSha: 'AAA',
        actualCiphertextSha: 'AAA',
      );
      expect(cls, isNot(MediaDiagClass.truncated));
    });

    test('полный размер, sha шифртекста не сошёлся → порча', () {
      expect(
        classifyMediaDiag(
          wasFromCache: false,
          statusCode: 200,
          msgtype: 'm.audio',
          contentType: 'application/octet-stream',
          contentLength: 1000,
          receivedBytes: 1000,
          expectedCiphertextSha: 'EXPECTED',
          actualCiphertextSha: 'DIFFERENT',
        ),
        MediaDiagClass.corrupted,
      );
    });

    test('всё сошлось / нет дискриминатора → unknown', () {
      expect(
        classifyMediaDiag(
          wasFromCache: false,
          statusCode: 200,
          msgtype: 'm.audio',
          contentLength: 1000,
          receivedBytes: 1000,
          expectedCiphertextSha: 'SAME',
          actualCiphertextSha: 'SAME',
        ),
        MediaDiagClass.unknown,
      );
    });
  });

  group('buildMediaDiagLine — формат + БЕЗ секретов', () {
    test('строка несёт класс+phase и НЕ содержит секретов', () {
      // Даже если попытаться протащить секреты — сигнатура их не принимает.
      // Проверяем, что в выводе нет полей key/iv/Bearer/token и нет значений
      // ключа/токена (их сюда физически не передать).
      final line = buildMediaDiagLine(
        phase: 'initial',
        wasFromCache: false,
        initialWasCache: false,
        mxc: 'mxc://liza.cyber-agro.ru/AbCdEf',
        msgtype: 'm.audio',
        declaredSize: 12345,
        receivedBytes: 40000,
        contentLength: 100000,
        contentEncoding: null,
        statusCode: 200,
        contentType: 'application/octet-stream',
        expectedCiphertextSha: 'EXPECTEDSHA',
        actualCiphertextSha: 'ACTUALSHA',
        first16: 'de ad be ef',
        errorType: 'Unable to decrypt file',
      );
      expect(line, startsWith('[MediaDiag] '));
      expect(line, contains('class=truncated'));
      expect(line, contains('phase=initial'));
      expect(line, contains('mxc=mxc://liza.cyber-agro.ru/AbCdEf'));
      // Секрет-именованных полей быть не должно ни при каких входах.
      for (final banned in ['key=', ' iv=', 'Bearer', 'authorization', 'token=']) {
        expect(line.toLowerCase(), isNot(contains(banned.toLowerCase())),
            reason: 'диаг-строка не должна нести $banned');
      }
    });

    test('кэш-хит: wasFromCache=true, класс poisonedCache, sha/http опущены', () {
      final line = buildMediaDiagLine(
        phase: 'initial',
        wasFromCache: true,
        initialWasCache: true,
        mxc: 'mxc://x/y',
        msgtype: 'm.audio',
      );
      expect(line, contains('class=poisonedCache'));
      expect(line, contains('wasFromCache=true'));
      expect(line, isNot(contains('status=')));
      expect(line, isNot(contains('actualSha=')));
    });
  });

  group('sha256B64Unpadded — формат SDK (base64 без паддинга)', () {
    test('совпадает с ручным base64(sha256) без «=»', () {
      final data = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final expected =
          base64.encode(crypto.sha256.convert(data).bytes).replaceAll('=', '');
      expect(sha256B64Unpadded(data), expected);
      expect(sha256B64Unpadded(data), isNot(contains('=')));
    });
  });

  group('mediaDiagFirst16Hex — ≤16 байт hex', () {
    test('ровно 16 байт из длинного тела', () {
      final data = Uint8List.fromList(List<int>.generate(100, (i) => i));
      final hex = mediaDiagFirst16Hex(data);
      expect(hex.split(' ').length, 16);
      expect(hex.startsWith('00 01 02 03'), isTrue);
    });
    test('короткое тело — сколько есть', () {
      expect(mediaDiagFirst16Hex(Uint8List.fromList([0xff, 0x00])), 'ff 00');
    });
  });
}
