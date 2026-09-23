import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/access_admin_service.dart';

void main() {
  group('AccessDossier.fromJson', () {
    test('разбирает группу bots', () {
      final dossier = AccessDossier.fromJson({
        'is_local': true,
        'server': {'name': 'liza.ru'},
        'spaces': [],
        'channels': [],
        'chats': [],
        'bots': [
          {'room_id': '!b:liza.ru', 'name': 'Лиза', 'level': 'user'},
        ],
      });
      expect(dossier.bots.length, 1);
      expect(dossier.bots.first.name, 'Лиза');
    });

    test('без ключа bots даёт пустой список', () {
      final dossier = AccessDossier.fromJson({
        'is_local': true,
        'server': {'name': 'liza.ru'},
        'spaces': [],
        'channels': [],
        'chats': [],
      });
      expect(dossier.bots, isEmpty);
    });

    test('name=null сохраняется как null', () {
      final dossier = AccessDossier.fromJson({
        'is_local': true,
        'server': {'name': 'liza.ru'},
        'spaces': [],
        'channels': [],
        'chats': [
          {'room_id': '!x:liza.ru', 'name': null, 'level': 'user'},
        ],
        'bots': [],
      });
      expect(dossier.chats.first.name, isNull);
    });
  });

  group('SpaceMember.fromJson', () {
    test('membership_in_space=null сохраняется', () {
      final member = SpaceMember.fromJson({
        'user_id': '@petr:liza.ru',
        'membership_in_space': null,
        'max_power_level': 0,
        'elevated_rooms': [],
      });
      expect(member.membershipInSpace, isNull);
      expect(member.userId, '@petr:liza.ru');
    });

    test('разбирает elevated_rooms', () {
      final member = SpaceMember.fromJson({
        'user_id': '@ivan:liza.ru',
        'membership_in_space': 'join',
        'max_power_level': 100,
        'elevated_rooms': [
          {
            'room_id': '!a:liza.ru',
            'name': 'Разработка',
            'power_level': 100,
            'group': 'chat',
          },
        ],
      });
      expect(member.elevatedRooms.length, 1);
      expect(member.elevatedRooms.first.group, 'chat');
      expect(member.maxPowerLevel, 100);
    });
  });
}
