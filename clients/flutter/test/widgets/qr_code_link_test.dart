import 'package:flutter_test/flutter_test.dart';

import 'package:liza/widgets/qr_code_viewer.dart';

// Спек 2026-07-30 §1.5: экран QR показывал сырой #alias:server, а копировал
// matrix.to-ссылку — показываем и копируем одно и то же.
//
// Fix round 1 (Critical): дефект уцелел в fallback-ветке (inviteLink == null),
// т.к. `qrDisplayText` и `_link` строили matrix.to-URL независимо друг от
// друга. Тест ниже сравнивает `qrDisplayText` напрямую с `qrLink` — функцией,
// которой теперь пользуется и `_link` внутри QrCodeViewer. Если кто-то снова
// разведёт эти два выражения (например, вернёт в qrDisplayText свою копию
// 'https://matrix.to/#/$content'), тест упадёт.
void main() {
  test('при наличии ссылки показывается она, а не сырой идентификатор', () {
    expect(
      qrDisplayText(
        content: '#chan:liza.ru',
        inviteLink: 'https://me.liza.ru/c/mychannel',
      ),
      'https://me.liza.ru/c/mychannel',
    );
  });

  test('без ссылки показывается matrix.to-фоллбэк', () {
    expect(
      qrDisplayText(content: '#chan:liza.ru', inviteLink: null),
      'https://matrix.to/#/#chan:liza.ru',
    );
  });

  group('qrDisplayText совпадает с qrLink (тем, что кодируется/копируется)', () {
    test('когда inviteLink задан', () {
      const content = '#chan:liza.ru';
      const inviteLink = 'https://me.liza.ru/c/mychannel';
      expect(
        qrDisplayText(content: content, inviteLink: inviteLink),
        qrLink(content: content, inviteLink: inviteLink),
      );
    });

    test('когда inviteLink отсутствует (fallback-ветка)', () {
      const content = '#chan:liza.ru';
      expect(
        qrDisplayText(content: content, inviteLink: null),
        qrLink(content: content, inviteLink: null),
      );
    });
  });
}
