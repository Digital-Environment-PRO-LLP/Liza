import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/access_admin_service.dart';

void main() {
  group('accessLevelFromCode', () {
    test('распознаёт все уровни', () {
      expect(accessLevelFromCode('admin'), AccessLevel.admin);
      expect(accessLevelFromCode('moderator'), AccessLevel.moderator);
      expect(accessLevelFromCode('user'), AccessLevel.user);
    });

    test('неизвестный код и null дают user', () {
      expect(accessLevelFromCode('нечто'), AccessLevel.user);
      expect(accessLevelFromCode(null), AccessLevel.user);
    });
  });

  group('DossierEntry.fromJson', () {
    test('разбирает полную запись', () {
      final entry = DossierEntry.fromJson({
        'room_id': '!a:srv',
        'name': 'Компания',
        'avatar': 'mxc://srv/abc',
        'level': 'admin',
      });
      expect(entry.roomId, '!a:srv');
      expect(entry.name, 'Компания');
      expect(entry.avatar, 'mxc://srv/abc');
      expect(entry.level, AccessLevel.admin);
    });

    test('переживает отсутствующий avatar', () {
      final entry = DossierEntry.fromJson({
        'room_id': '!a:srv',
        'name': 'Чат',
        'level': 'user',
      });
      expect(entry.avatar, isNull);
    });
  });

  group('AccessDossier.fromJson', () {
    Map<String, dynamic> payload() => {
          'user_id': '@u:srv',
          'display_name': 'Иван',
          'deactivated': false,
          'is_local': true,
          'server': {
            'name': 'srv',
            'role': {'code': 'user', 'label': 'Пользователь', 'color': null},
          },
          'spaces': [
            {'room_id': '!s:srv', 'name': 'Компания', 'level': 'admin'},
          ],
          'channels': [
            {'room_id': '!c:srv', 'name': 'Канал', 'level': 'moderator'},
          ],
          'chats': [
            {'room_id': '!r:srv', 'name': 'Чат', 'level': 'user'},
          ],
        };

    test('разбирает группы', () {
      final d = AccessDossier.fromJson(payload());
      expect(d.displayName, 'Иван');
      expect(d.deactivated, isFalse);
      expect(d.isLocal, isTrue);
      expect(d.serverName, 'srv');
      expect(d.roleLabel, 'Пользователь');
      expect(d.spaces.single.name, 'Компания');
      expect(d.channels.single.level, AccessLevel.moderator);
      expect(d.chats.single.level, AccessLevel.user);
    });

    test('пустые группы дают пустые списки', () {
      final json = payload()
        ..['spaces'] = []
        ..['channels'] = []
        ..['chats'] = [];
      final d = AccessDossier.fromJson(json);
      expect(d.spaces, isEmpty);
      expect(d.channels, isEmpty);
      expect(d.chats, isEmpty);
    });

    test('отсутствующие группы не роняют разбор', () {
      final d = AccessDossier.fromJson({
        'user_id': '@u:srv',
        'deactivated': true,
        'is_local': false,
        'server': {'name': 'srv', 'role': null},
      });
      expect(d.spaces, isEmpty);
      expect(d.roleLabel, isNull);
      expect(d.deactivated, isTrue);
      expect(d.isLocal, isFalse);
    });
  });
}
