// Страж реестра регрессии: ledger:RL-keychain-null-bootloop (см. tests/registry/).
//
// Инвариант: null-чтение пароля БД из Keychain при существующей БД НЕ должно
// приводить к бесконечной петле перезапуска. После конечного числа подряд
// провальных загрузок политика обязана перейти к регенерации пароля
// (regenerate), а не вечно требовать retryLater. Иначе повторяется boot-loop,
// кирпичащий приложение после переподписи (TestFlight-обновление на macOS).

library;

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/cipher.dart';

void main() {
  group('decideKeychainOutcome — анти-boot-loop [ledger:RL-keychain-null-bootloop]', () {
    test('пароль прочитан -> useExisting (счётчик игнорируется)', () {
      expect(
        decideKeychainOutcome(
          passwordPresent: true,
          databaseExists: true,
          consecutiveNullBoots: 999,
        ),
        KeychainReadOutcome.useExisting,
      );
    });

    test('null + БД есть, в пределах бюджета -> retryLater (сохраняем БД)', () {
      for (final boot in [1, 2]) {
        expect(
          decideKeychainOutcome(
            passwordPresent: false,
            databaseExists: true,
            consecutiveNullBoots: boot,
            maxLockedBoots: 3,
          ),
          KeychainReadOutcome.retryLater,
          reason: 'boot $boot < 3 — транзиентная блокировка, ждём разблокировки',
        );
      }
    });

    test('null + БД есть, бюджет исчерпан -> regenerate (разрываем петлю)', () {
      // Ключевой инвариант: при достижении порога прекращаем retryLater.
      for (final boot in [3, 4, 100]) {
        expect(
          decideKeychainOutcome(
            passwordPresent: false,
            databaseExists: true,
            consecutiveNullBoots: boot,
            maxLockedBoots: 3,
          ),
          KeychainReadOutcome.regenerate,
          reason: 'boot $boot >= 3 — элемент недоступен навсегда, регенерируем',
        );
      }
    });

    test('null + БД нет -> regenerate (первый запуск)', () {
      expect(
        decideKeychainOutcome(
          passwordPresent: false,
          databaseExists: false,
          consecutiveNullBoots: 0,
        ),
        KeychainReadOutcome.regenerate,
      );
    });

    test('дефолтный порог конечен -> петля всегда разрывается', () {
      // Без явного maxLockedBoots: достаточно большого счётчика хватает,
      // чтобы выйти из retryLater. Защита от «случайно бесконечного» порога.
      expect(
        decideKeychainOutcome(
          passwordPresent: false,
          databaseExists: true,
          consecutiveNullBoots: 1000000,
        ),
        KeychainReadOutcome.regenerate,
      );
    });
  });
}
