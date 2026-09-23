// ignore_for_file: avoid_print

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:matrix/matrix.dart';

import 'utils/test_client.dart';

void main() {
  testWidgets('preview/reply/push body for "+" bullet', (tester) async {
    // l10n.yaml включает use-deferred-loading → load() дергает настоящий
    // loadLibrary(). Под fakeAsync внутри testWidgets такой Future не
    // резолвится никогда, и тест висел до 10-минутного таймаута, роняя весь
    // `flutter test`. Реальное время даёт только runAsync.
    late final L10n l10n;
    await tester.runAsync(() async {
      l10n = await L10n.delegate.load(const Locale('ru'));
    });
    final locals = MatrixLocals(l10n);
    // Раньше клиент собирался вручную с `MatrixSdkDatabase.init(database: null)`
    // и падал на «You must provide a Database sqfliteDatabase». В остальных
    // тестах для этого есть общий хелпер.
    late final Client client;
    await tester.runAsync(() async {
      client = await prepareTestClient();
    });
    final room = Room(id: '!r:x', client: client);
    final ev = Event(
      type: EventTypes.Message,
      content: {
        'msgtype': 'm.text',
        'body': '+',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<ul>\n<li></li>\n</ul>\n',
      },
      eventId: '\$1',
      senderId: '@a:x',
      originServerTs: DateTime.now(),
      room: room,
    );

    final reply = ev.calcLocalizedBodyFallback(locals,
        withSenderNamePrefix: false, hideReply: true, plaintextBody: true);
    print('REPLY  => [$reply]');

    final list = ev.calcLocalizedBodyFallback(locals,
        hideReply: true, hideEdit: true, plaintextBody: true,
        removeMarkdown: true, withSenderNamePrefix: false);
    print('LIST/PUSH => [$list]');
  });
}
