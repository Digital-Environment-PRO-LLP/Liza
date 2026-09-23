import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/hierarchy_displayname.dart';

void main() {
  group('hierarchyDisplayname', () {
    test('DM без имени и алиаса берёт имя собеседника из клиента', () {
      expect(
        hierarchyDisplayname(
          itemName: null,
          canonicalAlias: null,
          knownRoomDisplayname: 'Дмитрий Люба',
          emptyChatFallback: 'Пустой чат',
        ),
        'Дмитрий Люба',
      );
    });

    test('пустая строка имени не считается именем', () {
      expect(
        hierarchyDisplayname(
          itemName: '',
          canonicalAlias: null,
          knownRoomDisplayname: 'Дмитрий Люба',
          emptyChatFallback: 'Пустой чат',
        ),
        'Дмитрий Люба',
      );
    });

    test('фолбэк только когда комната клиенту неизвестна', () {
      expect(
        hierarchyDisplayname(
          itemName: null,
          canonicalAlias: null,
          knownRoomDisplayname: null,
          emptyChatFallback: 'Пустой чат',
        ),
        'Пустой чат',
      );
    });

    test('явное имя комнаты имеет приоритет', () {
      expect(
        hierarchyDisplayname(
          itemName: 'Общий чат',
          canonicalAlias: '#alias:server',
          knownRoomDisplayname: 'Другое',
          emptyChatFallback: 'Пустой чат',
        ),
        'Общий чат',
      );
    });
  });
}
