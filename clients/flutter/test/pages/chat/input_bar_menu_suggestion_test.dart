import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/pages/chat/input_bar.dart';
import '../../utils/test_client.dart';

// LABA-2201: в диалоге с BotFather при вводе «/» первой подсказкой должна идти
// выделенная команда /menu (лёгкий способ вернуться к стартовому меню). В
// обычных чатах её нет. Тестируем чистый botFatherMenuCommandSuggestion, чтобы
// не монтировать виджет (Matrix-клиент + widget-tester фейк-таймеры вешают
// testWidgets). Страж — ledger:RL-botfather-menu-command.
void main() {
  Future<(Client, Room, Room)> prepareRooms() async {
    final client = await prepareTestClient(loggedIn: true);
    client.rooms.clear();
    const bfDm = '!bf:example.invalid';
    const userDm = '!bob:example.invalid';
    client.rooms.addAll([
      Room(id: bfDm, client: client),
      Room(id: userDm, client: client),
    ]);
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        '@botfather:bots.liza.ru': [bfDm],
        '@bob:example.invalid': [userDm],
      },
    );
    return (client, client.getRoomById(bfDm)!, client.getRoomById(userDm)!);
  }

  group('botFatherMenuCommandSuggestion [ledger:RL-botfather-menu-command]', () {
    test('BotFather-чат: /menu выделенной подсказкой при вводе / и его префиксах',
        () async {
      final (client, bfRoom, _) = await prepareRooms();

      // Пустой ввод «/», а также префиксы «m», «me», «men», «menu».
      for (final search in ['', 'm', 'me', 'men', 'menu']) {
        final s = botFatherMenuCommandSuggestion(bfRoom, search);
        expect(s, isNotNull, reason: 'для «/$search» ожидаем подсказку /menu');
        expect(s!['type'], 'command');
        expect(s['name'], 'menu');
        expect(s['highlight'], 'true');
      }

      // Строка, не являющаяся префиксом «menu» — подсказки нет.
      expect(botFatherMenuCommandSuggestion(bfRoom, 'xyz'), isNull);

      await client.dispose(closeDatabase: true);
    });

    test('Обычный чат: /menu не предлагается ни при каком вводе', () async {
      final (client, _, userRoom) = await prepareRooms();

      for (final search in ['', 'm', 'menu']) {
        expect(botFatherMenuCommandSuggestion(userRoom, search), isNull,
            reason: 'вне BotFather команды /menu быть не должно');
      }

      await client.dispose(closeDatabase: true);
    });
  });
}
