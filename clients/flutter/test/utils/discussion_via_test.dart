import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/channel_discussion.dart';

void main() {
  group('discussionViaServers', () {
    test('домен обсуждения идёт первым', () {
      expect(
        discussionViaServers(
          '!disc:nadezhda.liza.ru',
          '!chan:nadezhda.liza.ru',
        ),
        ['nadezhda.liza.ru'],
      );
    });

    test('федеративный случай: оба домена, обсуждение первым', () {
      // Прод 2026-07-28: гость @daniel.furman:synapse.liza… состоит в канале
      // на nadezhda.liza.ru. Без via join чата-обсуждения невозможен.
      expect(
        discussionViaServers(
          '!disc:nadezhda.liza.ru',
          '!chan:synapse.liza.laba.prodamus.tech',
        ),
        ['nadezhda.liza.ru', 'synapse.liza.laba.prodamus.tech'],
      );
    });

    test('дубли не повторяются', () {
      expect(
        discussionViaServers('!a:one.tld', '!b:one.tld'),
        ['one.tld'],
      );
    });

    test('битый room_id без двоеточия не роняет и не даёт пустых доменов', () {
      expect(discussionViaServers('!broken', '!chan:one.tld'), ['one.tld']);
    });

    test('порт в имени сервера сохраняется целиком', () {
      expect(
        discussionViaServers('!disc:local.tld:8448', '!chan:local.tld:8448'),
        ['local.tld:8448'],
      );
    });
  });
}
