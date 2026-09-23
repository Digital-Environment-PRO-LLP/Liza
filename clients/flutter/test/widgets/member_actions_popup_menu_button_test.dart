import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/widgets/member_action_scope.dart';

// Регресс: меню участника компании-пространства показывало «права в
// чате» / «исключить из чата» вместо «в компании» — заказчик потребовал
// разные формулировки для компании и суб-пространства (LABA task-11).
void main() {
  group('scopedMemberActionLabel', () {
    test('канал → channel (даже если формально isSpace/isCompany true)', () {
      final result = scopedMemberActionLabel<String>(
        isChannel: true,
        isSpace: true,
        isCompany: true,
        chat: 'chat',
        channel: 'channel',
        company: 'company',
        space: 'space',
      );
      expect(result, 'channel');
    });

    test('обычный чат (не space, не канал) → chat', () {
      final result = scopedMemberActionLabel<String>(
        isChannel: false,
        isSpace: false,
        isCompany: false,
        chat: 'chat',
        channel: 'channel',
        company: 'company',
        space: 'space',
      );
      expect(result, 'chat');
    });

    test('корневая компания (isSpace + isCompany) → company', () {
      final result = scopedMemberActionLabel<String>(
        isChannel: false,
        isSpace: true,
        isCompany: true,
        chat: 'chat',
        channel: 'channel',
        company: 'company',
        space: 'space',
      );
      expect(result, 'company');
    });

    test('суб-пространство (isSpace, НЕ isCompany) → space, не company', () {
      final result = scopedMemberActionLabel<String>(
        isChannel: false,
        isSpace: true,
        isCompany: false,
        chat: 'chat',
        channel: 'channel',
        company: 'company',
        space: 'space',
      );
      expect(result, 'space');
    });
  });

  // Проверка отсутствия запрещённого API — это не логика ветвления (та уже
  // покрыта юнитом выше), а гарантия, что виджет не откатили обратно на
  // ненадёжный room.spaceParents (см. utils/chat_topology.dart).
  test(
    'виджет использует isCompanySpace из chat_topology, а не room.spaceParents',
    () {
      final code = File(
        'lib/widgets/member_actions_popup_menu_button.dart',
      ).readAsStringSync();
      expect(
        code.contains('isCompanySpace('),
        isTrue,
        reason: 'должен переиспользовать готовый хелпер Task 9, '
            'а не изобретать свою проверку компании',
      );
      expect(
        code.contains('spaceParents'),
        isFalse,
        reason: 'room.spaceParents ненадёжен для суб-пространств '
            '(см. chat_topology.dart)',
      );
    },
  );
}
