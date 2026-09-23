// ledger:RL-push-tap-stories-opens-viewer
// AC:RL-push-tap-stories-opens-viewer/1 AC:RL-push-tap-stories-opens-viewer/2
// AC:RL-push-tap-stories-opens-viewer/3 AC:RL-push-tap-stories-opens-viewer/4
// AC:RL-push-tap-stories-opens-viewer/5 AC:RL-push-tap-stories-opens-viewer/6
// AC:RL-push-tap-stories-opens-viewer/8
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/push_tap_target.dart';

const _story = '!story:example.invalid';
const _story2 = '!story2:example.invalid';
const _event = '\$evt:example.invalid';

void main() {
  group('pushTapTargetFor — классификация цели тапа', () {
    test('AC-3: обычная комната → RoomTapTarget(/rooms/\$roomId)', () {
      final t = pushTapTargetFor(
        roomId: '!chat:example.invalid',
        roomExists: true,
        isInvite: false,
        isStoryRoom: false,
        isJoined: true,
        activeQueueIds: const [],
        eventId: _event,
      );
      expect(
        t,
        const RoomTapTarget('/rooms/!chat:example.invalid'),
        reason: 'обычный чат из пуша открывает чат, не вьюер (регресс-защита)',
      );
    });

    test('AC-4: invite-комната → RoomTapTarget(/rooms)', () {
      final t = pushTapTargetFor(
        roomId: '!inv:example.invalid',
        roomExists: true,
        isInvite: true,
        isStoryRoom: false,
        isJoined: false,
        activeQueueIds: const [],
        eventId: _event,
      );
      expect(t, const RoomTapTarget('/rooms'));
    });

    test('комнаты нет (не доехала в sync) → RoomTapTarget(/rooms)', () {
      final t = pushTapTargetFor(
        roomId: '!gone:example.invalid',
        roomExists: false,
        isInvite: false,
        isStoryRoom: false,
        isJoined: false,
        activeQueueIds: const [],
        eventId: _event,
      );
      expect(t, const RoomTapTarget('/rooms'));
    });

    test('AC-1: сторис-комната + прогретый кэш → StoryTapTarget, '
        'INV-1 roomIds[initialIndex]==roomId', () {
      final t = pushTapTargetFor(
        roomId: _story,
        roomExists: true,
        isInvite: false,
        isStoryRoom: true,
        isJoined: true,
        activeQueueIds: const [_story2, _story], // автор из пуша — второй
        eventId: _event,
      );
      expect(t, isA<StoryTapTarget>());
      final s = t as StoryTapTarget;
      expect(s.roomIds, [_story2, _story]);
      expect(s.initialIndex, 1);
      // INV-1: кликнутая сторис-комната стоит на initialIndex.
      expect(s.roomIds[s.initialIndex], _story);
      expect(s.initialEventId, _event);
    });

    test('AC-2: initialEventId == payload.eventId при валидном eventId', () {
      final s = pushTapTargetFor(
        roomId: _story,
        roomExists: true,
        isInvite: false,
        isStoryRoom: true,
        isJoined: true,
        activeQueueIds: const [_story],
        eventId: _event,
      ) as StoryTapTarget;
      expect(s.initialEventId, _event);
    });

    test('AC-2: eventId=="null" (Dart null сериализован литералом) → null', () {
      final s = pushTapTargetFor(
        roomId: _story,
        roomExists: true,
        isInvite: false,
        isStoryRoom: true,
        isJoined: true,
        activeQueueIds: const [_story],
        eventId: 'null',
      ) as StoryTapTarget;
      expect(s.initialEventId, isNull,
          reason: 'без санитайза "null" не совпал бы ни с каким сегментом');
    });

    test('AC-2: eventId пустой/null → initialEventId null', () {
      for (final raw in <String?>['', null]) {
        final s = pushTapTargetFor(
          roomId: _story,
          roomExists: true,
          isInvite: false,
          isStoryRoom: true,
          isJoined: true,
          activeQueueIds: const [_story],
          eventId: raw,
        ) as StoryTapTarget;
        expect(s.initialEventId, isNull);
      }
    });

    test('AC-5: cold-start (кэш пуст) → деградация [roomId], initialIndex 0, '
        'INV-1 держится', () {
      final s = pushTapTargetFor(
        roomId: _story,
        roomExists: true,
        isInvite: false,
        isStoryRoom: true,
        isJoined: true,
        activeQueueIds: const [], // бар не смонтирован — очередь пуста
        eventId: _event,
      ) as StoryTapTarget;
      expect(s.roomIds, [_story]);
      expect(s.initialIndex, 0);
      expect(s.roomIds[s.initialIndex], _story);
      expect(s.initialEventId, _event);
    });

    test('AC-5: сторис-комната есть, но её нет в прогретой очереди '
        '(протухла у бара) → деградация [roomId]', () {
      final s = pushTapTargetFor(
        roomId: _story,
        roomExists: true,
        isInvite: false,
        isStoryRoom: true,
        isJoined: true,
        activeQueueIds: const [_story2], // чужая комната активна, нашей нет
        eventId: _event,
      ) as StoryTapTarget;
      expect(s.roomIds, [_story]);
      expect(s.initialIndex, 0);
      expect(s.roomIds[s.initialIndex], _story);
    });

    test('AC-8: сторис-комната, но пользователь вышел/забанен (не join) → '
        'RoomTapTarget(/rooms), НЕ мигающий вьюер', () {
      // Вышел (leave): activeStoriesWithTimeline вернул бы null → вьюер мигнул
      // бы и закрылся. Ведём в список.
      final left = pushTapTargetFor(
        roomId: _story,
        roomExists: true,
        isInvite: false,
        isStoryRoom: true,
        isJoined: false,
        activeQueueIds: const [_story],
        eventId: _event,
      );
      expect(left, const RoomTapTarget('/rooms'),
          reason: 'leave/ban сторис-комнаты → список, не StoryViewer');
    });
  });

  group('sanitizePushEventId', () {
    test('валидный id проходит', () {
      expect(sanitizePushEventId(_event), _event);
    });
    test('"null"/пусто/null → null', () {
      expect(sanitizePushEventId('null'), isNull);
      expect(sanitizePushEventId(''), isNull);
      expect(sanitizePushEventId(null), isNull);
    });
  });
}
