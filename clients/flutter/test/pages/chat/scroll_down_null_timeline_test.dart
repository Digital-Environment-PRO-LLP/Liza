// ledger:RL-own-action-scrolls-to-bottom
// AC:RL-own-action-scrolls-to-bottom/7
//
// GlitchTip #2042 (сборка 3762, iOS): `ChatController.scrollDown()` делал
// `timeline!.allowNewEvent` и падал «Null check operator used on a null value»,
// когда своё echo приходило в момент перезагрузки ленты (сам scrollDown()
// обнуляет timeline на время перезагрузки с исторического контекста, а SDK на
// одну отправку файла шлёт несколько echo `sending`). Тот же null возможен на
// post-frame прыжке из updateView, если scrollToEventId успел обнулить ленту.
//
// Страж зовёт РЕАЛЬНЫЙ ChatController.scrollDown (не реплику): _FakeChatController
// перекрывает только room, initState не вызывается (образец
// archive_back_button_test). `scrollDown` — `void … async`: до фикса синхронный
// `timeline!` превращался в unhandled async error и ронял тест.

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/pages/chat/chat.dart';

import '../../utils/test_client.dart';

class _FakeChatController extends ChatController {
  _FakeChatController(this._fakeRoom);

  final Room _fakeRoom;

  @override
  Room get room => _fakeRoom;
}

void main() {
  late Client client;

  setUpAll(() async {
    client = await prepareTestClient(loggedIn: true);
  });

  tearDownAll(() async {
    await client.dispose(closeDatabase: true);
  });

  test(
    'AC-7: scrollDown() при timeline == null (лента грузится/перезагружается) '
    'не падает и не трогает контроллер без клиентов',
    () async {
      final room = Room(
        id: '!scrolldown:fakeServer.notExisting',
        client: client,
      );
      final controller = _FakeChatController(room);
      expect(controller.timeline, isNull);

      controller.scrollDown();
      // Дать async-функции завершиться: до фикса ошибка всплывала именно тут.
      await Future<void>.delayed(Duration.zero);

      expect(controller.timeline, isNull, reason: 'перезагрузку не запускаем');
      expect(controller.scrollController.hasClients, isFalse);
    },
  );
}
