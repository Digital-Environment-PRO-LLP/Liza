import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/chat_topology.dart';

void main() {
  group('canSeeMembersAt', () {
    test('в обычном чате участники видны всем', () {
      expect(
        canSeeMembersAt(isSpace: false, isChannel: false, ownPowerLevel: 0),
        isTrue,
      );
    });

    test('в пространстве обычный участник список НЕ видит', () {
      expect(
        canSeeMembersAt(isSpace: true, isChannel: false, ownPowerLevel: 0),
        isFalse,
      );
    });

    test('модератор пространства видит', () {
      expect(
        canSeeMembersAt(isSpace: true, isChannel: false, ownPowerLevel: 50),
        isTrue,
      );
    });

    test('админ пространства видит', () {
      expect(
        canSeeMembersAt(isSpace: true, isChannel: false, ownPowerLevel: 100),
        isTrue,
      );
    });

    test('49 — ещё не модератор', () {
      expect(
        canSeeMembersAt(isSpace: true, isChannel: false, ownPowerLevel: 49),
        isFalse,
      );
    });

    test('регресс: порог invite=0 не должен открывать базу юзеров', () {
      // «Компания Розенталь» на проде: {"invite": 0, "users_default": 0} —
      // приглашать может любой участник, поэтому гейт на canInvite пропускал
      // всех. Правило обязано смотреть на power level, а не на право invite.
      expect(
        canSeeMembersAt(isSpace: true, isChannel: false, ownPowerLevel: 0),
        isFalse,
      );
    });

    test('в канале подписчик поимённый список НЕ видит', () {
      expect(
        canSeeMembersAt(isSpace: false, isChannel: true, ownPowerLevel: 0),
        isFalse,
      );
    });

    test('модератор канала список видит', () {
      expect(
        canSeeMembersAt(isSpace: false, isChannel: true, ownPowerLevel: 50),
        isTrue,
      );
    });

    test('владелец канала список видит', () {
      expect(
        canSeeMembersAt(isSpace: false, isChannel: true, ownPowerLevel: 100),
        isTrue,
      );
    });
  });
}
