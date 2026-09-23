// ledger:RL-chat-list-phone-search-invite
// AC:RL-chat-list-phone-search-invite/4 AC:RL-chat-list-phone-search-invite/5
//
// Unit-страж функции completePhoneOrNull (guard.render:pure-function).
// AC-4: частичный ввод (< 10 цифр) → null, lookup не шлётся.
// AC-5: полные номера в любой форме → non-null.
// AC-1/2/3 (lookup→Profile в _search) — device/manual residual, требуют
// полного ChatListController + мок HTTP (см. RL).
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/phone_number.dart';

void main() {
  group('completePhoneOrNull', () {
    // AC-5: полные номера в разных форматах → non-null (не null, не lookup-блок).
    group('полный номер (≥10 цифр) → non-null', () {
      // AC:RL-chat-list-phone-search-invite/5
      test('+7 999 123-45-67 → non-null', () {
        expect(completePhoneOrNull('+7 999 123-45-67'), isNotNull);
      });

      test('89991234567 → non-null', () {
        // AC:RL-chat-list-phone-search-invite/5
        expect(completePhoneOrNull('89991234567'), isNotNull);
      });

      test('79991234567 → non-null', () {
        // AC:RL-chat-list-phone-search-invite/5
        expect(completePhoneOrNull('79991234567'), isNotNull);
      });

      test('+79991234567 → non-null', () {
        // AC:RL-chat-list-phone-search-invite/5
        expect(completePhoneOrNull('+79991234567'), isNotNull);
      });

      test('номер с пробелами и скобками → non-null', () {
        // AC:RL-chat-list-phone-search-invite/5
        expect(completePhoneOrNull('+7 (999) 123-45-67'), isNotNull);
      });

      test('минимально допустимый: ровно 10 цифр → non-null', () {
        // AC:RL-chat-list-phone-search-invite/5
        expect(completePhoneOrNull('1234567890'), isNotNull);
      });

      test('возвращает trimmed-строку, не нормализует E.164', () {
        // Серверный матчинг сам нормализует — клиент только «полный/нет».
        // AC:RL-chat-list-phone-search-invite/5
        const raw = '  +7 999 123-45-67  ';
        final result = completePhoneOrNull(raw);
        expect(result, isNotNull);
        expect(result, '+7 999 123-45-67'); // trimmed, не stripped до цифр
      });
    });

    // AC-4: частичный ввод (< 10 цифр) → null, lookup не шлётся.
    group('частичный ввод (< 10 цифр) → null', () {
      test('8999 → null', () {
        // AC:RL-chat-list-phone-search-invite/4
        expect(completePhoneOrNull('8999'), isNull);
      });

      test('+7 999 → null', () {
        // AC:RL-chat-list-phone-search-invite/4
        expect(completePhoneOrNull('+7 999'), isNull);
      });

      test('9 цифр → null (граница)', () {
        // AC:RL-chat-list-phone-search-invite/4
        expect(completePhoneOrNull('123456789'), isNull);
      });

      test('пустая строка → null', () {
        // AC:RL-chat-list-phone-search-invite/4
        expect(completePhoneOrNull(''), isNull);
      });

      test('строка из пробелов → null', () {
        // AC:RL-chat-list-phone-search-invite/4
        expect(completePhoneOrNull('   '), isNull);
      });
    });

    // Не-номерные строки → null (lookup не шлётся на произвольный текст).
    group('не-номерные строки → null', () {
      test('текст без цифр → null', () {
        // AC:RL-chat-list-phone-search-invite/4
        expect(completePhoneOrNull('привет'), isNull);
      });

      test('mxid → null', () {
        // AC:RL-chat-list-phone-search-invite/4
        expect(completePhoneOrNull('@user:hs'), isNull);
      });

      test('email → null', () {
        // AC:RL-chat-list-phone-search-invite/4
        expect(completePhoneOrNull('user@example.com'), isNull);
      });
    });
  });
}
