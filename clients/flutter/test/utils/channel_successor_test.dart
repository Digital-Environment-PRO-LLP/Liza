// ledger:RL-channel-sole-admin-leave
// AC:RL-channel-sole-admin-leave/1
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/chat_topology.dart';

void main() {
  group('isServiceAccountId', () {
    test('боты и поддержка — сервисные', () {
      for (final id in [
        '@liza:bots.liza.ru',
        '@gpt:bots.liza.ru',
        '@deepseek:bots.liza.ru',
        '@support:nadezhda.liza.ru',
      ]) {
        expect(isServiceAccountId(id), isTrue, reason: id);
      }
    });

    test('обычный пользователь — не сервисный', () {
      expect(isServiceAccountId('@nadezhda:nadezhda.liza.ru'), isFalse);
      expect(isServiceAccountId('@liza_fan:example.invalid'), isFalse);
    });
  });

  group('pickChannelSuccessor — выбор преемника-админа', () {
    test('приоритет — модератор с максимальным PL', () {
      final id = pickChannelSuccessor(const [
        ChannelSuccessorCandidate('@u1:x', 0),
        ChannelSuccessorCandidate('@mod50:x', 50),
        ChannelSuccessorCandidate('@mod70:x', 70),
      ]);
      expect(id, '@mod70:x');
    });

    test('нет модераторов → детерминированный первый по id', () {
      final id = pickChannelSuccessor(const [
        ChannelSuccessorCandidate('@zoe:x', 0),
        ChannelSuccessorCandidate('@amy:x', 0),
      ]);
      expect(id, '@amy:x');
    });

    test('нет кандидатов → null (канал единственного участника удаляется)', () {
      expect(pickChannelSuccessor(const []), isNull);
    });
  });
}
