// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liza/utils/stories/active_stories_provider.dart';
import 'package:liza/utils/stories/stories_seen_store.dart';
import 'package:liza/widgets/story_avatar_ring.dart';
import 'test_client.dart';

const _author = '@author:example.invalid';

void main() {
  late Client client;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    client = await prepareTestClient(loggedIn: true);
    ActiveStoriesProvider.instance.clear();
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await client.dispose(closeDatabase: true);
  });

  Event msg(Room room, String id) => Event(
        eventId: id, senderId: _author,
        originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
        type: EventTypes.Message, content: const {}, room: room,
      );

  test('нет данных по userId → none', () async {
    final prefs = await SharedPreferences.getInstance();
    final seen = StoriesSeenStore(prefs);
    expect(
      ActiveStoriesProvider.instance.ringForUser(_author, client, seen),
      StoryRingState.none,
    );
  });

  test('активное событие автора → unseen', () async {
    final prefs = await SharedPreferences.getInstance();
    final seen = StoriesSeenStore(prefs);
    final room = Room(id: '!s:example.invalid', client: client);
    client.rooms.add(room);
    ActiveStoriesProvider.instance
        .setRoomActive('!s:example.invalid', _author, [msg(room, r'$e1')]);
    expect(
      ActiveStoriesProvider.instance.ringForUser(_author, client, seen),
      StoryRingState.unseen,
    );
  });

  test('все события автора просмотрены → seen [ledger:RL-stories-rings-everywhere]', () async {
    final prefs = await SharedPreferences.getInstance();
    final seen = StoriesSeenStore(prefs);
    await seen.markSeen(r'$e1');
    final room = Room(id: '!s:example.invalid', client: client);
    client.rooms.add(room);
    ActiveStoriesProvider.instance
        .setRoomActive('!s:example.invalid', _author, [msg(room, r'$e1')]);
    expect(
      ActiveStoriesProvider.instance.ringForUser(_author, client, seen),
      StoryRingState.seen,
    );
  });
}
