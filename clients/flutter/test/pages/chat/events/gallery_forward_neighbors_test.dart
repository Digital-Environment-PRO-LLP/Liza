// Host-страж пересылки альбома: `buildForwardedGalleryContents` разворачивает
// набор членов в НОВЫЙ альбом (новый id, reindex 0..N-1, n=факт, caption→i==0);
// одиночный член — СНИМАЕТ поле gallery (иначе получатель ловит фантом-спиннеры
// от старого n). Разворот из timeline (`buildForwardedContentsForEvents`) и 3
// UI-пути — device (`gallery_forward_flow_test.dart`).
//
// ledger:RL-gallery-forward-neighbors

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/pages/chat/events/gallery.dart';

import '../../../utils/test_client.dart';

void main() {
  late Client client;
  late Room room;

  setUp(() async {
    client = await prepareTestClient(loggedIn: true);
    room = Room(id: '!fwd:example.invalid', client: client);
  });

  tearDown(() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await client.dispose(closeDatabase: true);
  });

  Event member(
    int i,
    int n, {
    String gid = 'old-gallery',
    String? caption,
    String msgtype = 'm.image',
    bool withReply = false,
  }) =>
      Event(
        type: 'm.room.message',
        eventId: '\$fwd-$gid-$i:example.invalid',
        senderId: '@a:example.invalid',
        originServerTs: DateTime.now(),
        content: {
          'msgtype': msgtype,
          'body': 'album_$i',
          'url': 'mxc://example.invalid/old$i',
          if (withReply)
            'm.relates_to': {
              'm.in_reply_to': {'event_id': '\$something:example.invalid'},
            },
          galleryContentKey: {
            'id': gid,
            'i': i,
            'n': n,
            if (i == 0 && caption != null) 'caption': caption,
          },
        },
        room: room,
      );

  Map<String, Object?>? galleryOf(Map<String, Object?> c) =>
      c[galleryContentKey] as Map<String, Object?>?;

  test(
    'AC:RL-gallery-forward-neighbors/1 — форвард 2 медиа → 2 content, новый id, '
    'i=0,1, n=2, без фантомов (red-proof: старый форвард нёс n исходное)',
    () async {
      final members = [member(0, 3), member(1, 3)];
      final out = await buildForwardedGalleryContents(client, members);

      expect(out.length, 2);
      final g0 = galleryOf(out[0])!;
      final g1 = galleryOf(out[1])!;
      expect(g0['id'], isNot('old-gallery'), reason: 'новый gallery id');
      expect(g0['id'], g1['id'], reason: 'общий новый id у всех членов');
      expect([g0['i'], g1['i']], [0, 1]);
      expect(g0['n'], 2, reason: 'n = факт числа пересланных, не исходное 3');
      expect(g1['n'], 2);
    },
  );

  test(
    'AC:RL-gallery-forward-neighbors/2 — форвард 3 медиа → i=0..2 по порядку, n=3',
    () async {
      // Подаём вперемешку — билдер сортирует по galleryIndex.
      final members = [member(2, 3), member(0, 3), member(1, 3)];
      final out = await buildForwardedGalleryContents(client, members);
      expect(out.length, 3);
      expect(out.map((c) => galleryOf(c)!['i']).toList(), [0, 1, 2]);
      expect(out.every((c) => galleryOf(c)!['n'] == 3), isTrue);
    },
  );

  test(
    'AC:RL-gallery-forward-neighbors/3 — микс фото+видео сохраняет msgtype',
    () async {
      final members = [
        member(0, 2, msgtype: 'm.image'),
        member(1, 2, msgtype: 'm.video'),
      ];
      final out = await buildForwardedGalleryContents(client, members);
      expect(out.map((c) => c['msgtype']).toSet(), {'m.image', 'm.video'});
      expect(out.every((c) => galleryOf(c)!['n'] == 2), isTrue);
    },
  );

  test(
    'AC:RL-gallery-forward-neighbors/4 — единственный член → поле gallery СНЯТО '
    '(честный single, не n исходное)',
    () async {
      final out = await buildForwardedGalleryContents(client, [member(0, 3)]);
      expect(out.length, 1);
      expect(galleryOf(out[0]), isNull,
          reason: 'у одиночной пересылки не должно остаться com.liza.gallery');
    },
  );

  test(
    'AC:RL-gallery-forward-neighbors/5 — caption с исходного i==0 → на новый i==0; '
    'на прочих нет',
    () async {
      final members = [
        member(0, 2, caption: 'Саркис с объекта'),
        member(1, 2),
      ];
      final out = await buildForwardedGalleryContents(client, members);
      expect(galleryOf(out[0])!['caption'], 'Саркис с объекта');
      expect(galleryOf(out[1])!.containsKey('caption'), isFalse);
    },
  );

  test(
    'AC:RL-gallery-forward-neighbors/6 — каждый член: маркер com.liza.forwarded '
    'есть, m.relates_to снят (кросс RL-forwarded-attribution)',
    () async {
      final members = [
        member(0, 2, withReply: true),
        member(1, 2, withReply: true),
      ];
      final out = await buildForwardedGalleryContents(client, members);
      for (final c in out) {
        expect(c.containsKey('com.liza.forwarded'), isTrue);
        expect(c.containsKey('m.relates_to'), isFalse,
            reason: 'reply-связь на чужое событие должна сниматься');
      }
    },
  );
}
