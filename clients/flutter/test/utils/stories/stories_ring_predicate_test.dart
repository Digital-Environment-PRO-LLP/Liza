// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liza/utils/stories/stories_extension.dart';
import 'package:liza/utils/stories/stories_seen_store.dart';
import 'package:liza/widgets/story_avatar_ring.dart';
import 'test_client.dart';

const _author = '@author:example.invalid';

void main() {
  late Client client;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    client = await prepareTestClient(loggedIn: true);
  });
  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await client.dispose(closeDatabase: true);
  });

  StoryRingState ringFor(Room room, List<Event> active, StoriesSeenStore seen) =>
      client.ringStateFromActive(room, active, seen);

  test('нет активных событий → none', () async {
    final prefs = await SharedPreferences.getInstance();
    final seen = StoriesSeenStore(prefs);
    final room = Room(id: '!empty:example.invalid', client: client);
    expect(ringFor(room, const [], seen), StoryRingState.none);
  });

  test('есть непросмотренный → unseen', () async {
    final prefs = await SharedPreferences.getInstance();
    final seen = StoriesSeenStore(prefs);
    final room = Room(id: '!s:example.invalid', client: client);
    final e = Event(
      eventId: r'$e1', senderId: _author,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
      type: EventTypes.Message, content: const {}, room: room,
    );
    expect(ringFor(room, [e], seen), StoryRingState.unseen);
  });

  test('все просмотрены → seen [ledger:RL-stories-seen-author]', () async {
    final prefs = await SharedPreferences.getInstance();
    final seen = StoriesSeenStore(prefs);
    await seen.markSeen(r'$e1');
    final room = Room(id: '!s:example.invalid', client: client);
    final e = Event(
      eventId: r'$e1', senderId: _author,
      originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
      type: EventTypes.Message, content: const {}, room: room,
    );
    expect(ringFor(room, [e], seen), StoryRingState.seen);
  });
}
