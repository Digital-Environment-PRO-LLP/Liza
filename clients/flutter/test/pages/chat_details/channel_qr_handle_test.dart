// ledger:RL-channel-qr-me-liza-ru
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat_details/chat_details.dart';
import 'package:liza/widgets/qr_code_viewer.dart';

void main() {
  group('домен для резолва ника канала', () {
    test('берётся из room_id, а не из аккаунта пользователя', () {
      // AC:RL-channel-qr-me-liza-ru/1
      expect(
        serverNameForRoom('!imFpwmDxzbZyFMaFtN:nadezhda.liza.ru'),
        'nadezhda.liza.ru',
      );
    });

    test('room_id с портом сохраняет порт', () {
      // AC:RL-channel-qr-me-liza-ru/1
      expect(
        serverNameForRoom('!abc:localhost:8448'),
        'localhost:8448',
      );
    });

    test('битый room_id даёт null, а не пустую строку', () {
      // AC:RL-channel-qr-me-liza-ru/1
      expect(serverNameForRoom('!broken'), isNull);
    });
  });

  group('ссылка QR', () {
    test('с ником канала — me.liza.ru, без matrix.to', () {
      final link = qrLink(
        content: '#тест_названия:nadezhda.liza.ru',
        inviteLink: 'https://me.liza.ru/c/test',
      );
      // AC:RL-channel-qr-me-liza-ru/2
      expect(link, 'https://me.liza.ru/c/test');
      // AC:RL-channel-qr-me-liza-ru/2
      expect(link, isNot(contains('matrix.to')));
    });
  });
}
