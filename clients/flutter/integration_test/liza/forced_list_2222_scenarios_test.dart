// LABA-2222 (жалоба Нади, сборка 3699): сквозной РЕНДЕР-тест на Android/локальном
// стеке. Актор testuser2 засевает в свежий DM ровно те структуры событий, что
// приходят от старых сборок/внешних клиентов (с навязанным <ul><li></li></ul> в
// formatted_body) — по 4 сценариям заказчика + смешанный. UI testuser (сборка с
// фиксом) открывает комнату; проверяем, что «•» НЕТ, а «+»/«-»/текст видны.
//
// Запуск (эмулятор + adb reverse tcp:8008): см. scripts/e2e/run-android.sh, но с
// этим файлом. make local-up && make local-seed-e2e должны быть выполнены.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/main.dart' as app;
import 'package:liza/pages/chat/chat_view.dart';

import 'e2e_actor.dart';
import 'e2e_config.dart';
import 'liza_flows.dart';

const _bullet = '<ul>\n<li></li>\n</ul>\n';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LABA-2222: 4 сценария «+/-» рендерятся литералом, без «•»',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'chat.fluffy.show_no_google': false,
    });

    final actorA = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userA);
    final actorB = await E2eActor.login(E2eConfig.homeserver, E2eConfig.userB);
    // Чистим накопленные e2e-комнаты у обоих (иначе список рендерит битые
    // аватарки старых комнат → MxcImage-исключения роняют тест).
    for (final actor in [actorA, actorB]) {
      final sync = await actor.api.sync();
      for (final r in (sync.rooms?.join?.keys.toList() ?? <String>[])) {
        try {
          await actor.api.leaveRoom(r);
          await actor.api.forgetRoom(r);
        } catch (_) {}
      }
    }
    final roomId = await actorB.createDirectChat(actorA.userId);
    await actorA.joinRoom(roomId);

    final b = actorB.userId;
    Future<String> send(Map<String, Object?> content) => actorB.api.sendMessage(
          roomId,
          'm.room.message',
          'e2e-${DateTime.now().microsecondsSinceEpoch}',
          content,
        );
    Map<String, Object?> marker(String body) =>
        {'msgtype': 'm.text', 'body': body, 'format': 'org.matrix.custom.html',
          'formatted_body': _bullet};
    Map<String, Object?> reply(String sign, String origId) => {
          'msgtype': 'm.text',
          'body': '> <$b> $sign\n\n$sign',
          'format': 'org.matrix.custom.html',
          'formatted_body':
              '<mx-reply><blockquote>$sign</blockquote></mx-reply>$_bullet',
          'm.relates_to': {
            'm.in_reply_to': {'event_id': origId},
          },
        };

    // (1) единичный «+», затем единичный «-»
    final idPlus = await send(marker('+'));
    await send(marker('-'));
    // (2) ответ «+» на первое сообщение; ответ «-» на другое
    await send(reply('+', idPlus));
    final idForMinus = await send(marker('=опора='));
    await send(reply('-', idForMinus));
    // (3) два минуса по строкам в одном сообщении
    await send({'msgtype': 'm.text', 'body': '-\n-',
      'format': 'org.matrix.custom.html',
      'formatted_body': '<ul>\n<li></li>\n<li></li>\n</ul>\n'});
    // (4) два плюса по строкам в одном сообщении
    await send({'msgtype': 'm.text', 'body': '+\n+',
      'format': 'org.matrix.custom.html',
      'formatted_body': '<ul>\n<li></li>\n<li></li>\n</ul>\n'});
    // смешанный (дыра, найденная у Нади): список + пояснительная строка
    await send({'msgtype': 'm.text', 'body': '+ пункт 1\n+ пункт 2\nЭто два плюса',
      'format': 'org.matrix.custom.html',
      'formatted_body':
          '<ul><li>пункт 1</li><li>пункт 2</li></ul>\n<p>Это два плюса</p>'});
    // маячок для поиска тайла комнаты (последнее сообщение)
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final open = 'e2e-open-$stamp';
    await send({'msgtype': 'm.text', 'body': open});

    app.main();
    await tester.ensureLizaHome();

    final tile = find.textContaining(open);
    await tester.waitUntil(tile, timeout: const Duration(seconds: 60));
    // Тап по тайлу; если ChatView не открылся — повтор (первый sync бывает
    // медленным, тайл мог перерисоваться).
    for (var attempt = 0; attempt < 3; attempt++) {
      await tester.tap(tile.first, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 500));
      final end = DateTime.now().add(const Duration(seconds: 20));
      while (find.byType(ChatView).evaluate().isEmpty &&
          DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      if (find.byType(ChatView).evaluate().isNotEmpty) break;
    }
    await tester.waitUntil(find.byType(ChatView),
        timeout: const Duration(seconds: 10));
    // Дать таймлайну прогрузиться.
    await tester.waitUntil(
      find.textContaining('Это два плюса', findRichText: true),
      timeout: const Duration(seconds: 40),
    );
    await tester.pump(const Duration(seconds: 1));

    // ГЛАВНОЕ: ни одного буллета «•» в чате.
    expect(find.textContaining('•', findRichText: true), findsNothing,
        reason: 'форс-списки «+/-» не должны рендериться буллетом');
    expect(find.textContaining('•'), findsNothing);
    // Позитив: литералы на месте.
    expect(find.textContaining('пункт 1', findRichText: true), findsWidgets);
    expect(find.textContaining('Это два плюса', findRichText: true), findsWidgets);
  });
}
