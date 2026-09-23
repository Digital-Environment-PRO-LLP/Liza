// Страж РЕГРЕССИИ (ledger:RL-stories-bar-avatar): аватарка автора в сторис-ленте
// резолвится из УЖЕ СИНХРОНИЗИРОВАННОГО стейта комнаты (m.room.member автора →
// room.avatar) и НЕ обнуляется.
//
// Регрессия, которую ловит этот тест: аватарку автора переключили на сетевой
// `getProfileFromUserId(owner)`, который для федеративных/невалидных id падал
// `M_INVALID_PARAM`/таймаутом и возвращал Profile(avatarUrl: null) → у всех,
// кроме себя, аватарка превращалась в букву («пропали все аватарки кроме моей
// в верхней строке над чатами»). Источник аватарки обязан быть синхронным и
// безотказным — стейт комнаты, не сеть.

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/stories/stories_extension.dart';

import 'test_client.dart';

const _author = '@author:example.invalid';
const _memberAvatar = 'mxc://example.invalid/member';
const _roomAvatar = 'mxc://example.invalid/room';

void main() {
  late Client client;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await client.dispose(closeDatabase: true);
  });

  Event stateEv(
    Room room,
    String type,
    String stateKey,
    Map<String, dynamic> content,
  ) =>
      Event(
        eventId: '\$$type-$stateKey',
        senderId: _author,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        type: type,
        stateKey: stateKey,
        content: content,
        room: room,
      );

  Room buildStoryRoom({
    String? memberAvatar,
    String? roomAvatar,
  }) {
    final room = Room(id: '!story:example.invalid', client: client);
    // Автор сторис = создатель комнаты (storyOwnerOf читает m.room.create).
    room.setState(stateEv(room, EventTypes.RoomCreate, '', {'creator': _author}));
    room.setState(
      stateEv(room, EventTypes.RoomMember, _author, {
        'membership': 'join',
        if (memberAvatar != null) 'avatar_url': memberAvatar,
      }),
    );
    if (roomAvatar != null) {
      room.setState(
        stateEv(room, EventTypes.RoomAvatar, '', {'url': roomAvatar}),
      );
    }
    return room;
  }

  test('аватарка автора берётся из m.room.member (без сети)', () {
    final room = buildStoryRoom(memberAvatar: _memberAvatar);
    expect(client.storyOwnerAvatar(room)?.toString(), _memberAvatar);
  });

  test(
    'РЕГРЕССИЯ: член без avatar_url → фоллбэк на room.avatar, аватарка НЕ '
    'обнуляется [ledger:RL-stories-bar-avatar]',
    () {
      final room = buildStoryRoom(roomAvatar: _roomAvatar); // member без avatar
      final url = client.storyOwnerAvatar(room);
      expect(url, isNotNull, reason: 'не обнуляем — есть room.avatar');
      expect(url?.toString(), _roomAvatar);
    },
  );

  test('имя автора из стейта, фоллбэк — localpart', () {
    final room = buildStoryRoom(memberAvatar: _memberAvatar);
    // displayname не задан → localpart.
    expect(client.storyOwnerName(room), 'author');
  });
}
