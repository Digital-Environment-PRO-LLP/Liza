import 'package:matrix/matrix.dart';

/// Пре-эмит pending-события вложения в ленту — ДО тяжёлой подготовки файла.
///
/// **Зачем.** `room.sendFileEvent` (SDK `matrix`) первым же действием кладёт
/// placeholder в ленту через `_handleFakeSync` — это и есть «пузырь появился».
/// Но принимает он УЖЕ ГОТОВЫЙ `MatrixFile` с байтами в памяти. Поэтому на
/// mobile пузырь возникал только после извлечения постера + полного транскода
/// 720p + `readAsBytes()`: замерено покадрово 6.9 с от тапа «Прислать», из них
/// 6.3 с экран без единого индикатора. Отправитель считал, что отправка не
/// сработала.
///
/// **Как.** Мы эмитим ТОТ ЖЕ самый placeholder сами и заранее, с тем же `txid`.
/// Когда через несколько секунд SDK эмитнет свой, `Timeline._findEvent` матчит
/// по `event_id` **или** `transaction_id` и заменяет событие НА МЕСТЕ — второго
/// пузыря не возникает по построению, а не «потому что мы аккуратно сняли
/// первый». Лента (`chat_event_list.dart`) не трогается вообще: для неё это
/// обычное событие таймлайна, со штатными галереей, тредами, фильтрами и
/// аватарками прочтения.
///
/// **Инвариант:** [buildPendingAttachmentSync] обязан оставаться ЗЕРКАЛОМ
/// `SyncUpdate` из `room.sendFileEvent`. Меняется только момент времени, не
/// поведение. Расхождение здесь = расхождение пузыря до и после замены.

/// Ключ статуса отправки в `unsigned` — тот же, что использует SDK
/// (`room.dart`, `messageSendingStatusKey`). Импортируется из пакета.
SyncUpdate buildPendingAttachmentSync({
  required String roomId,
  required String senderId,
  required String txid,
  required String msgtype,
  required String name,
  required Map<String, dynamic> info,
  Map<String, dynamic>? extraContent,
  int? shrinkImageMaxDimension,
  String? threadRootEventId,
  String? threadLastEventId,
}) {
  return SyncUpdate(
    nextBatch: '',
    rooms: RoomsUpdate(
      join: {
        roomId: JoinedRoomUpdate(
          timeline: TimelineUpdate(
            events: [
              MatrixEvent(
                content: {
                  'msgtype': msgtype,
                  'body': name,
                  'filename': name,
                  'info': info,
                  if (extraContent != null) ...extraContent,
                  // Тред-связь по формуле SDK (`room.dart`, ветка
                  // `threadRootEventId != null` внутри `sendEvent`). Сам
                  // плейсхолдер `sendFileEvent` её НЕ несёт — SDK добавляет
                  // связь позже, вторым fake-sync'ом. Нам ждать нельзя: без
                  // `m.relates_to` `filterByVisibleInGui(threadId:)`
                  // выбрасывает событие из ленты треда и оставляет в
                  // основной — то есть на всё окно подготовки пузырь виден
                  // не там, где отправляли. `in_reply_to` из диалога
                  // отправки не приходит никогда, поэтому
                  // `is_falling_back` здесь всегда true.
                  if (threadRootEventId != null)
                    'm.relates_to': {
                      'event_id': threadRootEventId,
                      'rel_type': RelationshipTypes.thread,
                      'is_falling_back': true,
                      if (threadLastEventId != null)
                        'm.in_reply_to': {'event_id': threadLastEventId},
                    },
                },
                type: EventTypes.Message,
                eventId: txid,
                senderId: senderId,
                originServerTs: DateTime.now(),
                unsigned: {
                  messageSendingStatusKey: EventStatus.sending.intValue,
                  'transaction_id': txid,
                  // Зеркало `FileSendRequestCredentials.toJson()`. Сам класс
                  // SDK НЕ экспортирует из `package:matrix/matrix.dart`
                  // (лежит в `src/utils/`), поэтому воспроизводим его форму
                  // здесь. `in_reply_to`/`edit_event_id` из диалога отправки
                  // не приходят никогда — их тут нет намеренно.
                  if (shrinkImageMaxDimension != null)
                    'shrink_image_max_dimension': shrinkImageMaxDimension,
                  if (extraContent != null) 'extra_content': extraContent,
                },
              ),
            ],
          ),
        ),
      },
    ),
  );
}

/// Кладёт пре-эмитнутое событие в ленту и БД.
///
/// Обёртка в `database.transaction` — точное зеркало приватного
/// `Room._handleFakeSync`, который делает ровно это. `Client.handleSync`
/// помечен в SDK как «для тестовых утилит», но сам SDK зовёт его в проде из
/// `Event.cancelSend()` — прецедент есть, и дрейф здесь осознанный.
Future<void> emitPendingAttachment(Room room, SyncUpdate update) =>
    room.client.database.transaction(() => room.client.handleSync(update));

/// Снимает пре-эмитнутое событие, если подготовка не дошла до `sendFileEvent`.
///
/// **Только `cancelSend()`, НИКОГДА не перевод в `EventStatus.error`.** Событие
/// в статусе error, у которого нет байтов в `room.sendingFilePlaceholders`,
/// попадает под `isUnresendableMissingMedia` → тост «файл больше недоступен»,
/// мёртвая кнопка повтора, и невидимость для `FailedSendRetryService` (тот
/// итерирует именно `sendingFilePlaceholders.keys`). Это ровно LABA-2239 и
/// страж `RL-resend-missing-media-guard`. Error-статус законен только с того
/// момента, когда байтами владеет сам `sendFileEvent`.
Future<void> withdrawPendingAttachment(Room room, String txid) async {
  try {
    final event = await room.getEventById(txid);
    if (event == null || !event.status.isSending) return;
    await event.cancelSend();
  } catch (e, s) {
    // Событие могли уже снять (крестик на бабле — тоже fire-and-forget).
    Logs().w('Не удалось снять pending-вложение $txid', e, s);
  }
}
