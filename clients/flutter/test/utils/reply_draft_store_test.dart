// Страж регрессии (ledger:RL-reply-draft-persist): при переключении чата текст
// ответа сохранялся как черновик, но сам reply (на какое событие отвечаем)
// слетал — потому что replyEvent жил только в state ChatController, а не в
// хранилище рядом с текстовым черновиком. ReplyDraftStore персистит связку.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/utils/reply_draft_store.dart';

void main() {
  const roomId = '!room:example.invalid';
  const eventId = '\$reply-target:example.invalid';

  late SharedPreferences prefs;
  late ReplyDraftStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    store = ReplyDraftStore(prefs);
  });

  test('ключ черновика ответа привязан к комнате', () {
    expect(ReplyDraftStore.keyFor(roomId), 'draft_reply_$roomId');
  });

  test('сохранение и чтение восстанавливает eventId ответа '
      '[ledger:RL-reply-draft-persist]', () async {
    expect(store.read(roomId), isNull);

    await store.save(roomId, eventId);

    // Симулируем переключение чата: новый ChatController → новый store поверх
    // тех же SharedPreferences.
    final reopened = ReplyDraftStore(prefs);
    expect(reopened.read(roomId), eventId);
  });

  test('save(null) и clear снимают черновик ответа', () async {
    await store.save(roomId, eventId);
    expect(store.read(roomId), eventId);

    await store.save(roomId, null);
    expect(store.read(roomId), isNull);

    await store.save(roomId, eventId);
    await store.clear(roomId);
    expect(store.read(roomId), isNull);
  });

  test('пустой eventId трактуется как отсутствие черновика', () async {
    await store.save(roomId, '');
    expect(prefs.getString(ReplyDraftStore.keyFor(roomId)), isNull);
    expect(store.read(roomId), isNull);
  });

  test('черновики разных комнат не пересекаются', () async {
    const otherRoom = '!other:example.invalid';
    await store.save(roomId, eventId);

    expect(store.read(otherRoom), isNull);
    expect(store.read(roomId), eventId);
  });
}
