// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liza/utils/stories/active_stories_provider.dart';

import 'test_client.dart';

void main() {
  late Client client;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    client = await prepareTestClient(loggedIn: true);
    ActiveStoriesProvider.instance.clear();
  });
  tearDown(() async {
    ActiveStoriesProvider.instance.clear();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await client.dispose(closeDatabase: true);
  });

  test('orderedRoomsWithActive: пусто без данных', () {
    expect(ActiveStoriesProvider.instance.orderedRoomsWithActive(client), isEmpty);
  });
}
