import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat/external_link_web_view.dart';

/// Страж безопасности встроенного webview внешних ссылок (кнопка `open_link`
/// карточки приветствия — «Стать продавцом»). URL приходит из события бота,
/// поэтому валидируем схему на границе: только `https`.
/// ledger:RL-liza-welcome-greeting
/// AC:RL-liza-welcome-greeting/4
void main() {
  test('https-URL допускается', () {
    expect(
      isSafeHttpsUrl('https://forms.yandex.ru/cloud/6a705487068ff0002aef742d'),
      isTrue,
    );
  });

  test('не-https схемы блокируются', () {
    expect(isSafeHttpsUrl('http://example.com'), isFalse);
    expect(isSafeHttpsUrl('javascript:alert(1)'), isFalse);
    expect(isSafeHttpsUrl('intent://evil'), isFalse);
    expect(isSafeHttpsUrl('mailto:a@b.c'), isFalse);
    expect(isSafeHttpsUrl('file:///etc/passwd'), isFalse);
  });

  test('пустой/битый/без хоста URL блокируется', () {
    expect(isSafeHttpsUrl(null), isFalse);
    expect(isSafeHttpsUrl(''), isFalse);
    expect(isSafeHttpsUrl('https://'), isFalse);
    expect(isSafeHttpsUrl('not a url'), isFalse);
  });
}
