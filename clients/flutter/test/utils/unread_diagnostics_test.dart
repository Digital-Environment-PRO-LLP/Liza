// Тест чистого предиката диагностики UnreadDiagnostics.looksReadButUnreceipted —
// «комната выглядит прочитанной, хотя моя квитанция не на последнем чужом
// сообщении». Временная диагностика бага «свежий чат без индикатора
// непрочитанного» (инцидент 2026-07-29). Снять вместе с самим хелпером.

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/unread_diagnostics.dart';

void main() {
  bool call({
    bool isUnread = false,
    bool hasNewMessages = false,
    bool lastEventFromOther = true,
    bool lastEventIsPreviewType = true,
    String lastEventId = r'$last',
    String? ownReceiptEventId,
  }) =>
      UnreadDiagnostics.looksReadButUnreceipted(
        isUnread: isUnread,
        hasNewMessages: hasNewMessages,
        lastEventFromOther: lastEventFromOther,
        lastEventIsPreviewType: lastEventIsPreviewType,
        lastEventId: lastEventId,
        ownReceiptEventId: ownReceiptEventId,
      );

  test('подозрительно: квитанция на старом событии, индикатора нет', () {
    expect(call(ownReceiptEventId: r'$old'), isTrue);
  });

  test('подозрительно: своей квитанции нет вовсе', () {
    expect(call(ownReceiptEventId: null), isTrue);
  });

  test('норма: квитанция стоит на последнем сообщении', () {
    expect(call(ownReceiptEventId: r'$last'), isFalse);
  });

  test('норма: индикатор уже показан через notificationCount/markedUnread', () {
    expect(call(isUnread: true, ownReceiptEventId: r'$old'), isFalse);
  });

  test('норма: индикатор уже показан через hasNewMessages', () {
    expect(call(hasNewMessages: true, ownReceiptEventId: r'$old'), isFalse);
  });

  test('не наш случай: последнее событие — своё', () {
    expect(call(lastEventFromOther: false, ownReceiptEventId: r'$old'), isFalse);
  });

  test('не наш случай: последнее событие не превью-тип (напр. reaction)', () {
    expect(
      call(lastEventIsPreviewType: false, ownReceiptEventId: r'$old'),
      isFalse,
    );
  });
}
