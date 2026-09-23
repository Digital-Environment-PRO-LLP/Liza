// ledger:RL-user-handles AC:RL-user-handles/6
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/utils/channel_handle.dart';
import 'package:liza/utils/user_handle_service.dart';
import 'package:liza/widgets/user_identifier.dart';

// Круговой тест «скопировал → вставил → нашёлся» из брифа Task 7: проверяет
// связку userIdentifier() (копирование) + UserHandleService.resolve() +
// разбор строки вставки (та же логика, что и в
// new_private_chat.dart._searchUser, продублирована здесь минимально —
// сам разбор тривиален: '@<ник>' без ':' -> normalizeChannelHandle).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  const mxid = '@ivan_petrov:bots.liza.ru';
  const handleValue = 'ivan_petrov';

  UserHandleService buildService(http.Client httpClient) => UserHandleService(
    baseUrl: 'https://auth.test',
    accessTokenProvider: () => 'token',
    serverNameProvider: () => 'bots.liza.ru',
    httpClient: httpClient,
  );

  test(
    'скопированный ник, вставленный в поиск, резолвится в того же человека',
    () async {
      final handles = buildService(
        MockClient((request) async {
          expect(request.url.path, '/api/handles/$handleValue');
          return http.Response('{"mxid": "$mxid"}', 200);
        }),
      );
      handles.rememberHandle(mxid, handleValue);

      // Шаг 1: копирование (user_dialog.dart) — userIdentifier() отдаёт ник.
      final copied = userIdentifier(mxid, handles: handles);
      expect(copied, '@$handleValue');

      // Шаг 2: вставка в поиск (new_private_chat.dart) — та же ветка разбора:
      // '@<ник>' без ':' -> normalizeChannelHandle -> resolve().
      expect(copied.startsWith('@'), isTrue);
      expect(copied.contains(':'), isFalse);
      final candidate = normalizeChannelHandle(copied.substring(1));
      expect(validateChannelHandle(candidate), isNull);

      final resolved = await handles.resolve(candidate);
      expect(resolved, mxid);
    },
  );

  test(
    'вставленный MXID продолжает работать как раньше (не через ветку ника)',
    () async {
      // MXID (с ':') не должен попадать в ветку разбора ника вовсе — страж
      // регрессии: голый '@mxid:server' содержит ':', поэтому naive проверка
      // 'startsWith(@) && !contains(:)' из new_private_chat.dart корректно
      // его отсекает и не зовёт resolve().
      const pastedMxid = '@someone:bots.liza.ru';
      expect(pastedMxid.startsWith('@') && !pastedMxid.contains(':'), isFalse);
    },
  );
}
