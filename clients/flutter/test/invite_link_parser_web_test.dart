// ledger:RL-user-handles AC:RL-user-handles/12
import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/invite_link_parser.dart';

void main() {
  test('веб-путь /s/<code> распознаётся как сторис', () {
    expect(
      parseWebStoryCode(Uri.parse('https://web.liza.ru/s/abc123')),
      'abc123',
    );
  });

  test('веб-путь /c/<ник> распознаётся как канал', () {
    expect(
      parseWebChannelHandle(Uri.parse('https://web.liza.ru/c/mychannel')),
      'mychannel',
    );
  });

  test('невалидный ник канала не распознаётся', () {
    expect(
      parseWebChannelHandle(Uri.parse('https://web.liza.ru/c/xx')),
      isNull,
    );
  });

  test('веб-путь /u/<ник> распознаётся как профиль', () {
    expect(
      parseWebUserHandle(Uri.parse('https://web.liza.ru/u/rozental')),
      'rozental',
    );
  });

  test('невалидный ник профиля не распознаётся', () {
    expect(
      parseWebUserHandle(Uri.parse('https://web.liza.ru/u/xx')),
      isNull,
    );
  });

  test('чужой путь не распознаётся как сторис', () {
    expect(
      parseWebStoryCode(Uri.parse('https://web.liza.ru/rooms/!abc')),
      isNull,
    );
  });
}
