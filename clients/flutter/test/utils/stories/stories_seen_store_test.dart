import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liza/utils/stories/stories_seen_store.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('eventId не просмотрен по умолчанию', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = StoriesSeenStore(prefs);
    expect(store.isSeen(r'$evt1'), isFalse);
  });

  test('markSeen помечает eventId как просмотренный', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = StoriesSeenStore(prefs);
    await store.markSeen(r'$evt1');
    expect(store.isSeen(r'$evt1'), isTrue);
  });

  test('hasUnseen=true, если хотя бы один не просмотрен', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = StoriesSeenStore(prefs);
    await store.markSeen(r'$a');
    expect(store.hasUnseen([r'$a', r'$b']), isTrue);
  });

  test('hasUnseen=false, если все просмотрены', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = StoriesSeenStore(prefs);
    await store.markSeen(r'$a');
    await store.markSeen(r'$b');
    expect(store.hasUnseen([r'$a', r'$b']), isFalse);
  });

  test('invalidateCache: второй инстанс видит запись первого', () async {
    final prefs = await SharedPreferences.getInstance();
    final writer = StoriesSeenStore(prefs);
    final reader = StoriesSeenStore(prefs);
    // reader прогревает кеш ДО записи (как StoriesBar при первом build)
    expect(reader.isSeen(r'$x'), isFalse);
    await writer.markSeen(r'$x');
    // без инвалидации reader держит старый кеш
    reader.invalidateCache();
    expect(reader.isSeen(r'$x'), isTrue);
  });

  test('markAllSeen помечает все переданные eventId', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = StoriesSeenStore(prefs);
    await store.markAllSeen([r'$a', r'$b', r'$c']);
    expect(store.hasUnseen([r'$a', r'$b', r'$c']), isFalse);
  });
}
