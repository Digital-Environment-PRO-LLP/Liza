// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/config/setting_keys.dart';
import 'package:liza/utils/news_poll.dart';

import 'test_client.dart';

/// Сервис голосов Liza News живёт в статической карте по клиенту. Выход из
/// аккаунта обязан его освободить — иначе подписки разлогиненного Client
/// копятся до конца процесса (находка ревью /mr 2026-09-21).
void main() {
  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    NewsPollService.resetForTest();
  });

  test(
    'выход из аккаунта освобождает сервис; повторный of — новый экземпляр',
    () async {
      final client = await prepareTestClient(loggedIn: true);
      final first = NewsPollService.of(client);
      expect(identical(NewsPollService.of(client), first), isTrue);

      await client.logout();
      await Future<void>.delayed(Duration.zero);

      expect(client.onLoginStateChanged.value, LoginState.loggedOut);
      expect(identical(NewsPollService.of(client), first), isFalse);
      await client.dispose(closeDatabase: true);
    },
  );
}
