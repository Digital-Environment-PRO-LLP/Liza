import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/matrix_sdk_extensions/event_extension.dart';

/// ledger:RL-media-http-error-gate
///
/// LABA-2361: сервер отдал НЕ медиа, а ошибку (404/error-page) на download
/// воспроизводимого вложения. Раньше клиент не проверял HTTP-статус → тело
/// ошибки (`{"errcode":…}`) для НЕшифрованного медиа писалось в кэш как «аудио»
/// и уходило в плеер немым `(0) Source error`. Здесь защищаем решающие ЧИСТЫЕ
/// правила гейта и детектора отравленного кэша — реальные функции, не реплики.
void main() {
  group('mediaDownloadGate — решение гейта доставки медиа', () {
    // AC:RL-media-http-error-gate/5
    test('404 + m.audio → бросаем (осиротевший media)', () {
      final e = mediaDownloadGate(
        msgtype: 'm.audio',
        statusCode: 404,
        contentType: 'application/json',
      );
      expect(e, isA<MediaDownloadException>());
      expect(e!.statusCode, 404);
    });

    // AC:RL-media-http-error-gate/4  — Range/206 НЕ гейтим (порог >=400, не !=200)
    test('206 Partial Content + m.audio → НЕ гейтим', () {
      expect(
        mediaDownloadGate(
          msgtype: 'm.audio',
          statusCode: 206,
          contentType: 'audio/mp4',
        ),
        isNull,
      );
    });

    test('200 + валидный media content-type → НЕ гейтим', () {
      expect(
        mediaDownloadGate(
          msgtype: 'm.image',
          statusCode: 200,
          contentType: 'image/jpeg',
        ),
        isNull,
      );
    });

    // AC:RL-media-http-error-gate/6  — error-page-200 только для media-msgtype
    test('200 + application/json + m.audio → бросаем (error-page)', () {
      expect(
        mediaDownloadGate(
          msgtype: 'm.audio',
          statusCode: 200,
          contentType: 'application/json; charset=utf-8',
        ),
        isA<MediaDownloadException>(),
      );
    });

    test('200 + application/json + m.file → НЕ гейтим (легитимный JSON-файл)', () {
      expect(
        mediaDownloadGate(
          msgtype: 'm.file',
          statusCode: 200,
          contentType: 'application/json',
        ),
        isNull,
      );
      // и 404 для m.file тоже не гейтим — только audio/video/image
      expect(
        mediaDownloadGate(
          msgtype: 'm.file',
          statusCode: 404,
          contentType: 'application/json',
        ),
        isNull,
      );
    });

    test('m.video и m.image гейтятся так же, как m.audio', () {
      expect(
        mediaDownloadGate(msgtype: 'm.video', statusCode: 502, contentType: null),
        isA<MediaDownloadException>(),
      );
      expect(
        mediaDownloadGate(msgtype: 'm.image', statusCode: 403, contentType: null),
        isA<MediaDownloadException>(),
      );
    });
  });

  group('looksLikeMediaErrorBody — детект отравленного кэша', () {
    Uint8List b(List<int> x) => Uint8List.fromList(x);

    // AC:RL-media-http-error-gate/1
    test('Matrix JSON-ошибка → true', () {
      final body = '{"errcode":"M_NOT_FOUND","error":"Not found"}'.codeUnits;
      expect(looksLikeMediaErrorBody(b(body)), isTrue);
    });

    // AC:RL-media-http-error-gate/3
    test('HTML error-page → true', () {
      expect(
        looksLikeMediaErrorBody(b('<!DOCTYPE html><html>502</html>'.codeUnits)),
        isTrue,
      );
      expect(looksLikeMediaErrorBody(b('  <html>'.codeUnits)), isTrue);
    });

    // AC:RL-media-http-error-gate/2  — валидное медиа НИКОГДА не error-body
    test('валидные media-magic → false (ноль ложных срабатываний)', () {
      expect(looksLikeMediaErrorBody(b([0xFF, 0xD8, 0xFF, 0xE0])), isFalse); // JPEG
      expect(
        looksLikeMediaErrorBody(b([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])),
        isFalse,
      ); // PNG
      expect(looksLikeMediaErrorBody(b('OggS'.codeUnits)), isFalse); // OGG/Opus
      expect(looksLikeMediaErrorBody(b('GIF89a'.codeUnits)), isFalse); // GIF
      // MP4/M4A: 00 00 00 18 'ftyp'...
      expect(
        looksLikeMediaErrorBody(
          b([0, 0, 0, 0x18, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20]),
        ),
        isFalse,
      );
    });

    test('пустые байты → false', () {
      expect(looksLikeMediaErrorBody(b([])), isFalse);
    });

    test('JSON без errcode (легитимный JSON-файл) → false', () {
      expect(
        looksLikeMediaErrorBody(b('{"foo":1,"bar":[2,3]}'.codeUnits)),
        isFalse,
      );
    });
  });

  group('E2EE self-heal не задет новым типом ошибки', () {
    // AC:RL-media-http-error-gate/7
    test('MediaDownloadException НЕ считается healable decrypt-fail', () {
      expect(
        isHealableDecryptFailure(const MediaDownloadException(statusCode: 404)),
        isFalse,
      );
      // контроль: настоящий decrypt-fail по-прежнему healable
      expect(isHealableDecryptFailure(kDecryptFailure), isTrue);
    });
  });
}
