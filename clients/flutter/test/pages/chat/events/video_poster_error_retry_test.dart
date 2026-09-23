// Host-страж видимости провала видео-ПОСТЕРА в ленте (`_VideoPosterImage`).
// Раньше сбой экстракции молча `markNegative` → немой BlurHash, 0 сигнала.
// Теперь: retry сбрасывает negative-метку (`clearNegative`) + разовая
// телеметрия `[video-fail] reason=poster-extract-fail` БЕЗ секретов.
// Рендер значка/тапа — device/manual (libmpv на host недетерминирован).
//
// ledger:RL-video-poster-error-retry

// ignore_for_file: depend_on_referenced_packages

import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/monitoring.dart';
import 'package:liza/utils/video_poster_cache.dart';

import '../../../utils/test_client.dart';

Event _imageEvent(Room room, String id) => Event(
      type: 'm.room.message',
      eventId: id,
      senderId: '@a:example.invalid',
      originServerTs: DateTime.now(),
      content: const {'msgtype': 'm.video', 'body': 'clip.mp4'},
      room: room,
    );

void main() {
  test(
    'AC:RL-video-poster-error-retry/5 AC:RL-mediadiag-no-secret/poster-fail — '
    'title постера не несёт секретов, содержит reason',
    () {
      final title = Monitoring.videoIssueTitle(
        Monitoring.videoFailurePrefix,
        'poster-extract-fail',
        'synapse.example.tech',
      );
      expect(title, contains('reason=poster-extract-fail'));
      for (final secret in ['mxc://', 'Bearer', 'token=', 'key=', 'iv=', '@']) {
        expect(title, isNot(contains(secret)),
            reason: 'в сигнал не должен попасть локатор/секрет: $secret');
      }
    },
  );

  group('VideoPosterCache.clearNegative', () {
    late Client client;
    late Room room;

    setUp(() async {
      client = await prepareTestClient(loggedIn: true);
      room = Room(id: '!poster:example.invalid', client: client);
    });

    tearDown(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await client.dispose(closeDatabase: true);
    });

    test(
      'AC:RL-video-poster-error-retry/4 — clearNegative снимает метку '
      '(retry снова пойдёт на сеть); без сброса — no-op',
      () {
        final ev = _imageEvent(room, '\$poster-retry-1:example.invalid');
        // Изолируем от других тестов процесса.
        VideoPosterCache.instance.clearNegative(ev);

        expect(VideoPosterCache.instance.isNegative(ev), isFalse);
        VideoPosterCache.instance.markNegative(ev);
        expect(VideoPosterCache.instance.isNegative(ev), isTrue,
            reason: 'после провала событие в negative-кэше');

        // red-proof: без clearNegative повторный _bootstrap вернулся бы сразу
        // (isNegative==true). clearNegative делает retry осмысленным.
        final removed = VideoPosterCache.instance.clearNegative(ev);
        expect(removed, isTrue, reason: 'метка была и снялась');
        expect(VideoPosterCache.instance.isNegative(ev), isFalse,
            reason: 'после clearNegative retry снова пойдёт на экстракцию');
      },
    );
  });
}
