import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/chat_topology.dart';

void main() {
  group('canInteractWithReactionsAt', () {
    // ledger:RL-channel-peek-live-feed
    test('читатель канала без подписки реакции НЕ ставит', () {
      // Peek-лента строится на комнате с Membership.leave, где порог
      // m.reaction = 0: без этого гейта тап улетел бы на сервер и получил
      // M_FORBIDDEN, успев мигнуть «поставлено».
      expect(
        canInteractWithReactionsAt(membership: Membership.leave),
        isFalse,
      );
    });

    test('подписчик реакции ставит', () {
      expect(canInteractWithReactionsAt(membership: Membership.join), isTrue);
    });

    test('приглашённый (ещё не вступил) реакции не ставит', () {
      expect(
        canInteractWithReactionsAt(membership: Membership.invite),
        isFalse,
      );
    });
  });

  group('canReactAt', () {
    test('подписчик канала реагировать МОЖЕТ', () {
      // Регресс 2026-07-28: канал создаётся с events_default:100, гейт стоял
      // на canSendDefaultMessages → строка реакций пропадала у всех, кроме
      // владельца. Порог m.reaction при этом остаётся 0.
      expect(canReactAt(ownPowerLevel: 0, reactionThreshold: 0), isTrue);
    });

    test('владелец канала реагировать может', () {
      expect(canReactAt(ownPowerLevel: 100, reactionThreshold: 0), isTrue);
    });

    test('поднятый порог реакций отсекает обычного участника', () {
      expect(canReactAt(ownPowerLevel: 0, reactionThreshold: 50), isFalse);
    });

    test('ровно на пороге — можно', () {
      expect(canReactAt(ownPowerLevel: 50, reactionThreshold: 50), isTrue);
    });
  });
}
