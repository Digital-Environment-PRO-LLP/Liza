import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/company_membership.dart';
import 'package:liza/utils/single_space_service.dart';

void main() {
  group('CompanyEntry.fromJson', () {
    test('парсит полный объект компании', () {
      final entry = CompanyEntry.fromJson({
        'room_id': '!abc:cyber-agro.ru',
        'name': 'Cyber Agro',
        'topic': 'Agro company',
        'avatar_url': 'mxc://cyber-agro.ru/avatar',
        'num_joined_members': 42,
        'homeserver': 'cyber-agro.ru',
        'via': ['cyber-agro.ru'],
        'is_main_space': true,
      });
      expect(entry.roomId, '!abc:cyber-agro.ru');
      expect(entry.name, 'Cyber Agro');
      expect(entry.numJoinedMembers, 42);
      expect(entry.via, ['cyber-agro.ru']);
    });

    test('парсит объект без необязательных полей', () {
      final entry = CompanyEntry.fromJson({'room_id': '!x:hs'});
      expect(entry.roomId, '!x:hs');
      expect(entry.name, isNull);
      expect(entry.numJoinedMembers, 0);
      expect(entry.via, isEmpty);
    });
  });

  group('foreignCompanyKind', () {
    test('своя компания (тот же домен) -> own', () {
      expect(
        foreignCompanyKind(
          userId: '@a:acme.ru',
          roomId: '!x:acme.ru',
          isTopLevelSpace: true,
        ),
        CompanyMembershipKind.own,
      );
    });

    test('чужая компания (другой домен, top-level) -> foreign', () {
      expect(
        foreignCompanyKind(
          userId: '@a:acme.ru',
          roomId: '!x:cyber-agro.ru',
          isTopLevelSpace: true,
        ),
        CompanyMembershipKind.foreign,
      );
    });

    test('чужой домен, но не top-level -> none', () {
      expect(
        foreignCompanyKind(
          userId: '@a:acme.ru',
          roomId: '!x:cyber-agro.ru',
          isTopLevelSpace: false,
        ),
        CompanyMembershipKind.none,
      );
    });
  });
}
