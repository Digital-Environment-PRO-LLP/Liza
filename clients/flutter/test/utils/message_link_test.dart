// Страж РЕГРЕССИИ (ledger:RL-message-link): формат matrix.to-ссылки на
// сообщение должен оставаться round-trip-совместимым с SDK
// `parseIdentifierIntoParts` — именно его использует UrlLauncher.openMatrixToUrl
// для перехода к событию. Сломаем формат → «Copy Message Link» молча перестанет
// открывать сообщение (без ошибки компиляции). Поэтому тест проверяет не только
// наш tryParse, но и разбор сгенерированной ссылки самим SDK.

import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/utils/message_link.dart';

void main() {
  const roomId = '!abcRoom:liza.example.org';
  const eventId = r'$someEvent123:liza.example.org';

  group('MessageLink.url', () {
    test('строит matrix.to-ссылку на событие', () {
      const link = MessageLink(roomId: roomId, eventId: eventId);
      expect(
        link.url(),
        'https://matrix.to/#/$roomId/$eventId',
      );
    });

    test('добавляет via-сервер', () {
      const link = MessageLink(roomId: roomId, eventId: eventId);
      expect(link.url(via: 'liza.example.org'), endsWith('?via=liza.example.org'));
    });
  });

  group('round-trip через SDK parseIdentifierIntoParts', () {
    test('сгенерированная ссылка корректно парсится навигацией', () {
      const link = MessageLink(roomId: roomId, eventId: eventId);
      final parts = link.url(via: 'liza.example.org').parseIdentifierIntoParts();
      expect(parts, isNotNull);
      expect(parts!.primaryIdentifier, roomId);
      expect(parts.secondaryIdentifier, eventId);
      expect(parts.via, contains('liza.example.org'));
    });

    test('наш tryParse возвращает те же room/event', () {
      const link = MessageLink(roomId: roomId, eventId: eventId);
      final parsed = MessageLink.tryParse(link.url(via: 'liza.example.org'));
      expect(parsed, isNotNull);
      expect(parsed!.roomId, roomId);
      expect(parsed.eventId, eventId);
    });
  });

  group('MessageLink.tryParse', () {
    test('ссылка только на комнату (без события) → null', () {
      expect(
        MessageLink.tryParse('https://matrix.to/#/$roomId'),
        isNull,
      );
    });

    test('ссылка на пользователя → null', () {
      expect(
        MessageLink.tryParse('https://matrix.to/#/@user:liza.example.org'),
        isNull,
      );
    });

    test('мусор → null', () {
      expect(MessageLink.tryParse('https://example.com/foo'), isNull);
    });
  });

  group('MessageLink.firstFrom', () {
    test('извлекает ссылку из текста вокруг', () {
      const link = MessageLink(roomId: roomId, eventId: eventId);
      final text = 'смотри сюда ${link.url(via: 'liza.example.org')} это важно';
      final found = MessageLink.firstFrom(text);
      expect(found, link);
    });

    test('нет ссылки → null', () {
      expect(MessageLink.firstFrom('просто текст без ссылок'), isNull);
    });
  });

  group('MessageLink.bareLinkFrom', () {
    test('тело — только ссылка → распознаёт', () {
      const link = MessageLink(roomId: roomId, eventId: eventId);
      expect(MessageLink.bareLinkFrom('  ${link.url()}  '), link);
    });

    test('ссылка с текстом вокруг → null (не голая)', () {
      const link = MessageLink(roomId: roomId, eventId: eventId);
      expect(MessageLink.bareLinkFrom('текст ${link.url()}'), isNull);
    });
  });
}
