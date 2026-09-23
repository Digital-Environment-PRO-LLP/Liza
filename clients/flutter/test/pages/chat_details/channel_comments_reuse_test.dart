import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat_details/chat_details.dart';

// Спек 2026-07-30 §3.2: повторное включение комментариев должно вернуть
// ПРЕЖНИЙ чат обсуждения со всей историей, а не создать пустой новый.
void main() {
  Map<String, dynamic> room(String id, String type, String? parent) => {
        'room_id': id,
        'chat_type': type,
        'parent': parent,
      };

  test('находит отвязанный чат этого канала', () {
    final rooms = [
      room('!other:h', 'channel_discussion', '!another:h'),
      room('!disc:h', 'channel_discussion', '!chan:h'),
      room('!plain:h', null.toString(), null),
    ];
    expect(findDetachedDiscussion(rooms, '!chan:h'), '!disc:h');
  });

  test('чужой чат обсуждения не подходит', () {
    final rooms = [room('!other:h', 'channel_discussion', '!another:h')];
    expect(findDetachedDiscussion(rooms, '!chan:h'), isNull);
  });

  test('нет кандидатов — null (создаём новый чат)', () {
    expect(findDetachedDiscussion(const [], '!chan:h'), isNull);
  });

  // Fix round 1 (ревью task-13): findDetachedDiscussion сама НЕ проверяет
  // маркер удаления канала (`deleted: true`) — безопасность обеспечивает
  // guard идемпотентности `if (channel.discussionRoomId != null) return;`
  // ВЫШЕ по коду в enableChannelComments (см. dartdoc обеих сторон
  // инварианта в chat_details.dart). Полноценный интеграционный тест
  // недостижим без живого Matrix-клиента (Room/Client конструируются только
  // через SDK) — вместо этого структурный страж читает исходник и проверяет
  // ПОРЯДОК: guard обязан идти РАНЬШЕ вызова findDetachedDiscussion внутри
  // enableChannelComments. Мутация подтверждена вручную (см. task-13-report,
  // раздел «Fix round 1»): при перестановке guard'а ПОСЛЕ вызова
  // findDetachedDiscussion этот тест падает; после отката — снова зелёный.
  test(
    'guard идемпотентности стоит раньше findDetachedDiscussion в enableChannelComments',
    () {
      final source = File(
        'lib/pages/chat_details/chat_details.dart',
      ).readAsStringSync();

      final methodStart = source.indexOf('void enableChannelComments()');
      expect(
        methodStart,
        greaterThan(-1),
        reason: 'enableChannelComments не найден — переименован/перенесён?',
      );

      final guardIndex = source.indexOf(
        'if (channel.discussionRoomId != null) return;',
        methodStart,
      );
      final lookupIndex = source.indexOf(
        'findDetachedDiscussion(',
        methodStart,
      );

      expect(
        guardIndex,
        greaterThan(-1),
        reason:
            'guard идемпотентности пропал из enableChannelComments — '
            'findDetachedDiscussion сама не проверяет маркер deleted, '
            'см. её dartdoc',
      );
      expect(lookupIndex, greaterThan(-1));
      expect(
        guardIndex,
        lessThan(lookupIndex),
        reason:
            'guard должен идти РАНЬШЕ вызова findDetachedDiscussion: иначе '
            'канал с зависшим маркером удаления (deleted: true) тихо '
            'подхватит прежний чат обсуждения в обход guard\'а',
      );
    },
  );
}
