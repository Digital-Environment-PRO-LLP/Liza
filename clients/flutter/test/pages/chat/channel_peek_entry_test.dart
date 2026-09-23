// ledger:RL-channel-peek-live-feed
// AC:RL-channel-peek-live-feed/1
// AC:RL-channel-peek-live-feed/2
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('вход в канал без подписки', () {
    test('ChatPage при отсутствии комнаты пробует peek, а не заглушку', () {
      final source = File(
        'lib/pages/chat/chat.dart',
      ).readAsStringSync();

      // Окно проверки режем по СТРУКТУРЕ, а не `substring` фиксированной
      // длины: прежние 900 символов ехали от пары добавленных строк и молча
      // начинали смотреть не на тот код. Приём — как в
      // test/pages/channel/channel_link_peek_test.dart.
      final classIndex = source.indexOf('class ChatPage extends StatelessWidget');
      expect(classIndex, greaterThan(0), reason: 'не нашли класс ChatPage');
      final buildMatch = RegExp(r'Widget build\(BuildContext context\) \{')
          .firstMatch(source.substring(classIndex));
      expect(buildMatch, isNotNull, reason: 'не нашли build у ChatPage');
      final start = classIndex + buildMatch!.start;

      // Конец метода — первая строка `  }` с отступом в 2 пробела: это
      // закрывающая скобка метода класса (у тела функции верхнего уровня она
      // была бы без отступа).
      final endMatch = RegExp(r'\n  \}').firstMatch(source.substring(start));
      expect(endMatch, isNotNull, reason: 'не нашли конец тела ChatPage.build');
      final body = source.substring(start, start + endMatch!.end);

      expect(
        body.contains('ChannelPeekPage'),
        isTrue,
        reason: 'при room == null экран обязан пробовать peek-режим',
      );
      expect(
        body.contains('PublicRoomDialog(') || body.contains('showAdaptiveDialog'),
        isFalse,
        reason: 'вход в канал идёт сразу в ленту, без диалога-превью (AC-1)',
      );
    });

    test('заглушка закрытой комнаты осталась в peek-экране (AC-9)', () {
      // Текст заглушки переехал из ChatPage в ChannelPeekPage: развилка
      // теперь пробует peek ВСЕГДА, а прежний фолбэк рисуется по факту
      // отказа. Проверяем, что его не потеряли при переезде.
      final source = File('lib/pages/chat/chat.dart').readAsStringSync();
      final peekIndex = source.indexOf('class _ChannelPeekPageState');
      expect(peekIndex, greaterThan(0), reason: 'не нашли _ChannelPeekPageState');

      expect(
        source
            .substring(peekIndex)
            .contains('youAreNoLongerParticipatingInThisChat'),
        isTrue,
        reason: 'закрытая комната обязана давать прежнюю заглушку (AC-9)',
      );
    });

    test('peek-режим не регистрирует комнату в client.rooms', () {
      final source = File('lib/utils/channel_peek.dart').readAsStringSync();
      expect(
        source.contains('client.rooms.add'),
        isFalse,
        reason: 'регистрация комнаты вернула бы канал в список чатов',
      );
    });
  });
}
