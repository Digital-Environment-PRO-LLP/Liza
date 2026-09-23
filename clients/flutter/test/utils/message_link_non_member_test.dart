// Страж РЕГРЕССИИ (ledger:RL-message-link-non-member-no-join): открытие
// matrix.to-ссылки на сообщение НЕ должно превращаться в предложение вступить
// в чат у не-участника (LABA-2217). Решение о поведении вынесено в чистую
// функцию `matrixToOpenAction`, чтобы инвариант можно было проверить без
// Matrix-клиента и навигатора (виджет-тест с реальным Client вешается).
//
// Инвариант: `!roomId` у не-участника (комнаты нет локально) → инфо-экран,
// НИКОГДА не openRoom/publicPreview (т.е. никакого joinRoom). Известная
// комната (участник ИЛИ приглашённый — `getRoomById` возвращает и invited) →
// openRoom. `#alias` не-участника → превью из directory.
//
// Параллельно сторожим `roomEventPath`: путь к событию строится через Uri
// (энкодинг `:`/`$` в eventId), одинаково для перехода из ссылки и после входа
// в PublicRoomDialog — иначе скролл к сообщению молча ломается.

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/message_link.dart';

void main() {
  group('matrixToOpenAction — инвариант LABA-2217', () {
    test('!roomId у не-участника → инфо-экран, НЕ вступление', () {
      expect(
        matrixToOpenAction(roomKnownLocally: false, sigil: '!'),
        MatrixToOpenAction.notMemberInfo,
      );
    });

    test('#alias у не-участника → превью публичной комнаты', () {
      expect(
        matrixToOpenAction(roomKnownLocally: false, sigil: '#'),
        MatrixToOpenAction.publicPreview,
      );
    });

    test('известная комната (участник или приглашённый) → открыть', () {
      // getRoomById возвращает и join-, и invite-комнаты → обе ведут в чат
      // (для invited там экран принятия приглашения), а не в инфо-тупик.
      expect(
        matrixToOpenAction(roomKnownLocally: true, sigil: '!'),
        MatrixToOpenAction.openRoom,
      );
      expect(
        matrixToOpenAction(roomKnownLocally: true, sigil: '#'),
        MatrixToOpenAction.openRoom,
      );
    });

    test('не-участник по !roomId никогда не получает join-путь', () {
      // Явная фиксация сути тикета: для raw room-id без членства действие —
      // только информирование.
      final action = matrixToOpenAction(roomKnownLocally: false, sigil: '!');
      expect(action, isNot(MatrixToOpenAction.openRoom));
      expect(action, isNot(MatrixToOpenAction.publicPreview));
    });
  });

  group('roomEventPath — сохранение eventId в навигации', () {
    const roomId = '!abcRoom:liza.example.org';
    const eventId = r'$someEvent123:liza.example.org';

    test('без события → путь к комнате', () {
      expect(roomEventPath(roomId), '/rooms/$roomId');
    });

    test('с событием → query event, символы :/\$ закодированы через Uri', () {
      final path = roomEventPath(roomId, eventId);
      expect(path, startsWith('/rooms/'));
      expect(path, contains('?event='));
      // Uri-энкодинг: eventId не должен попасть в путь сырым (сырой `$`/`:`
      // ломает разбор go_router).
      final parsed = Uri.parse(path);
      expect(parsed.queryParameters['event'], eventId);
      expect(parsed.pathSegments, ['rooms', roomId]);
    });
  });
}
