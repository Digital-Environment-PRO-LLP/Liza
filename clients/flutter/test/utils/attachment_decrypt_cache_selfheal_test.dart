import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/matrix_sdk_extensions/event_extension.dart';

/// ledger:RL-attachment-decrypt-cache-selfheal
///
/// Регрессия: во время переезда медиа на MMR (2026-07-26) сервер мог отдать
/// не-тот-контент с `200 OK`, и SDK записал его в дисковый файл-кэш БЕЗ
/// валидации. На кэш-хите расшифровка вложения падает навсегда (sha256-mismatch
/// → голый `throw 'Unable to decrypt file'` в matrix-4.1.0 `event.dart:811`),
/// `storeFile` существующий файл не перезаписывает, `clearCache` файл-стор не
/// трогает → голосовые/видео/файлы перестают открываться (лог Максима, 21×
/// «Unable to decrypt file» из `AudioPlayerState._downloadAndPlay`).
///
/// Фикс — обёртка `event.downloadAndDecryptAttachmentHealed`: поймать РОВНО эту
/// ошибку → `deleteFile(mxc)` + перекачать свежее один раз за сессию. Здесь
/// защищаем самый хрупкий узел (по вердикту прокурора, BLOCKER-2): матчинг
/// ошибки. SDK бросает голую `String` — любая опечатка/локализация/смена версии
/// молча превратила бы self-heal в no-op без красного теста. Соседние голые
/// строки SDK и любые `Exception` лечить нельзя (перекачка их не чинит).
///
/// Полная оркестрация (retry ровно раз, гейт на `bool deleteFile`, one-shot Set,
/// проброс `downloadCallback`) + девайс-реплей отравленного кэша — ручной
/// пред-релизный чек (см. `tests/registry/RL-attachment-decrypt-cache-selfheal.md`),
/// т.к. реальный путь требует E2EE-клиента с vodozemac и фейка media-download с
/// совпадающим sha256 — как и у родственного `RL-mxc-image-cache-selfheal`.
void main() {
  group('isHealableDecryptFailure — лечим ТОЛЬКО sha256-mismatch кэша', () {
    test('точный литерал SDK → лечим', () {
      expect(isHealableDecryptFailure('Unable to decrypt file'), isTrue);
      // Литерал-константа обёртки не должна разойтись с матчем.
      expect(isHealableDecryptFailure(kDecryptFailure), isTrue);
    });

    group('соседние голые строки SDK → НЕ лечим (перекачка не поможет)', () {
      test('сетевой обрыв / нет локального файла', () {
        expect(
          isHealableDecryptFailure('Unable to download file from local store.'),
          isFalse,
        );
      });
      test('нет права decrypt в ключе', () {
        expect(
          isHealableDecryptFailure("Missing 'decrypt' in 'key_ops'."),
          isFalse,
        );
      });
      test('шифрование не включено', () {
        expect(
          isHealableDecryptFailure('Encryption is not enabled in your Client.'),
          isFalse,
        );
      });
    });

    group('похожие-но-другие строки → НЕ лечим', () {
      test('иная пунктуация/регистр', () {
        expect(isHealableDecryptFailure('unable to decrypt file'), isFalse);
        expect(isHealableDecryptFailure('Unable to decrypt file.'), isFalse);
        expect(isHealableDecryptFailure('Unable to decrypt file '), isFalse);
      });
      test('подстрока в большем тексте', () {
        expect(
          isHealableDecryptFailure('Error: Unable to decrypt file (retry)'),
          isFalse,
        );
      });
    });

    group('не-String → НЕ лечим', () {
      test('Exception с тем же текстом', () {
        expect(
          isHealableDecryptFailure(Exception('Unable to decrypt file')),
          isFalse,
        );
      });
      test('произвольный объект', () {
        expect(isHealableDecryptFailure(FormatException('boom')), isFalse);
        expect(isHealableDecryptFailure(42), isFalse);
      });
    });
  });
}
