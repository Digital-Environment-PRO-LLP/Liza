import 'package:matrix/matrix.dart';
// TimelineChunk не реэкспортируется из `package:matrix/matrix.dart`, хотя
// сам обязателен в конструкторе Timeline — обычные ленты строит
// `room.getTimeline()`, а peek-ленту собираем сами. Прецедент импорта
// внутренностей SDK уже есть (safe_database_api.dart).
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';

/// Механика чтения канала БЕЗ вступления в него (Liza-модель).
///
/// Прежнее допущение «держать Timeline без join Matrix не даёт» неверно для
/// нашего форка: `notifier.py:867-877` разрешает `/events` для комнат с
/// history_visibility=world_readable. Проверено на проде — пост владельца
/// прилетает в long-poll аккаунту, не состоящему в канале.

/// Типы событий, которые имеет смысл держать в ленте канала.
///
/// `peekEvents` отдаёт ВСЁ, что видно неучастнику, включая `m.presence` —
/// его в таймлайне быть не должно.
///
/// `m.reaction` держим в наборе, чтобы `Timeline` АГРЕГИРОВАЛ счётчики реакций
/// на постах (подписчик и читатель без подписки видят число реакций — их у
/// автора не было видно, п.4 жалобы). Сам чип-строкой реакция не рисуется:
/// `filterByVisibleInGui` в `ChannelPeekPage` вычищает `EventTypes.Reaction` из
/// РЕНДЕРА, оставляя их в таймлайне для агрегации.
const _feedEventTypes = {
  EventTypes.Message,
  EventTypes.Sticker,
  EventTypes.Encrypted,
  EventTypes.RoomCreate,
  EventTypes.Reaction,
};

/// Безопасный разбор ответа `/events` (peek long-poll) в `PeekEventsResponse`.
///
/// ⚠️ Корень краша `type 'Null' is not a subtype of type 'String'`: Synapse в
/// ответ `/events` подмешивает `m.presence` (`handlers/events.py`) — у них нет
/// ни `sender`, ни `event_id`, а `MatrixEvent.fromJson`/`BasicEventWithSender.
/// fromJson` в pub.dev-пакете `matrix` (НЕ форк — править нельзя) делают жёсткий
/// `json['sender'] as String`. Штатный `_feedEventTypes`-фильтр применяется
/// ПОЗЖЕ — до него десериализация уже падает, и живой хвост ленты навсегда
/// мёртв (цикл ловит исключение и спинит вхолостую).
///
/// Поэтому чистим СЫРОЙ JSON: выкидываем элементы chunk без `event_id`/`sender`
/// ДО `PeekEventsResponse.fromJson`. Чистая функция — тестируется без сети.
PeekEventsResponse sanitizePeekEventsJson(Map<String, Object?> json) {
  final rawChunk = json['chunk'];
  if (rawChunk is! List) return PeekEventsResponse.fromJson(json);
  final safeChunk = rawChunk
      .where(
        (e) => e is Map && e['event_id'] is String && e['sender'] is String,
      )
      .toList();
  return PeekEventsResponse.fromJson({...json, 'chunk': safeChunk});
}

/// Сырой long-poll `/events` с safe-разбором (см. [sanitizePeekEventsJson]).
///
/// `client.peekEvents` звать нельзя: краш происходит ВНУТРИ его
/// `PeekEventsResponse.fromJson`, перехватить сырой JSON там невозможно.
/// `client.request` возвращает уже декодированный Map (auth/base-url/429 внутри)
/// — его и чистим.
Future<PeekEventsResponse> safePeekFetch(
  Client client,
  String? from,
  String roomId,
) async {
  final json = await client.request(
    RequestType.GET,
    '/client/v3/events',
    query: {
      if (from != null) 'from': from,
      'timeout': '30000',
      'room_id': roomId,
    },
  );
  return sanitizePeekEventsJson(json);
}

/// Снимок ленты: события, токен для live-хвоста и комната, к которой они
/// привязаны.
///
/// [room] отдаётся наружу намеренно: в ней уже проставлен state канала
/// ([fillPeekRoomState]), и экран ОБЯЗАН рисовать ленту именно на ней.
/// Собери он свою через [buildPeekRoom] — получил бы пустую комнату, где
/// `isChannel`/`hasComments` ложны, то есть ровно тот баг, который чиним.
class ChannelPeekSnapshot {
  final List<Event> events;
  final String? nextToken;
  final Room room;

  const ChannelPeekSnapshot({
    required this.events,
    required this.nextToken,
    required this.room,
  });
}

/// Комната для peek-режима.
///
/// НЕ регистрируется в `client.rooms`: канал не должен попадать в список
/// чатов до явной подписки. `membership: leave` выбран намеренно — при нём
/// `Timeline.canRequestHistory` разрешает пагинацию вглубь
/// (`timeline.dart:81-83`).
Room buildPeekRoom(Client client, String roomId) =>
    Room(id: roomId, client: client, membership: Membership.leave);

/// Приводит сырые события API к SDK-шным `Event`, привязанным к комнате.
///
/// `getRoomEvents`/`peekEvents` отдают `MatrixEvent` — у него нет ни `room`,
/// ни `body`, а `Message`/`MessageContent` без них не рендерятся.
List<Event> peekEventsToTimeline(List<MatrixEvent> raw, Room room) => raw
    .where((e) => _feedEventTypes.contains(e.type))
    .map((e) => Event.fromMatrixEvent(e, room))
    .toList();

/// Наполняет state синтетической комнаты реальным состоянием канала.
///
/// БЕЗ этого комната пуста, и весь клиент считает канал ОБЫЧНЫМ чатом:
/// `isChannel` читает `m.room.create` (`chat_topology.dart`), `hasComments` —
/// `com.liza.channel.discussion`, имя в шапке — `m.room.name`, защита от
/// копирования — `com.liza.channel.no_forwards`, а `ownMessage` без
/// `isChannelPost` рисует посты владельца справа синими.
///
/// Источник — `GET /rooms/{id}/state`, а НЕ `state` из `/messages`: при
/// lazy_load_members последний отдаёт неучастнику только `m.room.member`
/// (проверено на проде: 1 событие против 19 у `/state`).
///
/// Возвращает `false`, если состояние получить не удалось: peek при этом
/// обязан продолжиться деградированно (лента важнее оформления).
Future<bool> fillPeekRoomState(Client client, Room room) async {
  final List<MatrixEvent> state;
  try {
    state = await client.getRoomState(room.id);
  } catch (e, s) {
    Logs().w('ChannelPeek: состояние ${room.id} недоступно', e, s);
    return false;
  }
  for (final event in state) {
    // setState роняет ассерт на события без stateKey, а `/state` формально
    // может отдать что угодно — фильтруем на входе.
    if (event.stateKey == null) continue;
    room.setState(Event.fromMatrixEvent(event, room));
  }
  return true;
}

/// Разовый снимок ленты канала.
///
/// Возвращает `null`, если читать нельзя (закрытый канал, нет доступа) — в
/// этом случае экран обязан показать прежнюю заглушку, а не пустую ленту.
Future<ChannelPeekSnapshot?> loadChannelPeekSnapshot(
  Client client,
  String roomId, {
  int limit = 100,
}) async {
  final room = buildPeekRoom(client, roomId);
  // Оба запроса независимы, поэтому идут ПАРАЛЛЕЛЬНО: последовательно экран
  // ждал бы сумму задержек до первого кадра. `Future.wait` тут безопасен —
  // отказ каждой ветки погашен внутри неё (`null` / `false`), наружу
  // исключение не летит и второй запрос не отменяется.
  //
  // try охватывает ТОЛЬКО сетевой вызов: `null` тут означает «читать нельзя»,
  // и экран по нему рисует заглушку. Накрой мы и конвертацию — ошибка в
  // peekEventsToTimeline выглядела бы как закрытый канал, и баг рендера
  // молча превратился бы в «вы больше не участвуете в чате».
  Future<GetRoomEventsResponse?> loadEvents() async {
    try {
      return await client.getRoomEvents(roomId, Direction.b, limit: limit);
    } catch (e, s) {
      Logs().w('ChannelPeek: снимок ленты $roomId недоступен', e, s);
      return null;
    }
  }

  final (response, _) = await (
    loadEvents(),
    fillPeekRoomState(client, room),
  ).wait;
  if (response == null) return null;
  return ChannelPeekSnapshot(
    events: peekEventsToTimeline(response.chunk, room),
    nextToken: response.end,
    room: room,
  );
}

/// Таймлайн поверх peek-снимка.
///
/// `nextBatch` ОБЯЗАН быть пустым: при непустом `Timeline` считает себя
/// фрагментированным и выставляет `allowNewEvent = false`
/// (`timeline.dart:360-362`) — живой хвост long-poll перестал бы доезжать до
/// ленты, и смысл peek-режима потерялся бы.
///
/// Конструктор подписывается на клиентские стримы sync, которые для
/// не-joined комнаты никогда не выстрелят: события в ленту вставляет сам
/// экран из `ChannelPeekStream`. Поэтому `onUpdate` и не нужен — но подписки
/// всё равно заводятся (пять штук, `timeline.dart:332-351`), и вызывающий
/// ОБЯЗАН звать `cancelSubscriptions()` перед пересборкой и в `dispose()`.
Timeline buildPeekTimeline(Room room, List<Event> events) => Timeline(
  room: room,
  chunk: TimelineChunk(events: events, nextBatch: ''),
);

/// Сетевой вызов long-poll. Отдельным типом — чтобы тест проверял ЦИКЛ,
/// не поднимая HTTP.
typedef PeekFetch =
    Future<PeekEventsResponse> Function(String? from, String roomId);

/// Живой хвост ленты канала для читателя без подписки.
///
/// Держит серверный long-poll `/events?room_id=…` (30 с). Это НЕ polling:
/// сервер отвечает сразу по событию, поэтому задержка близка к нулю при
/// ~2 запросах в минуту. Polling через `/messages` дал бы 12-20 запросов и
/// заметное отставание.
///
/// Ловушка: долгий peek держит читателя в presence ONLINE
/// (`handlers/events.py:75-80`) — осознанная цена живой ленты.
///
/// `dispose()` — кооперативная остановка, а не отмена: она выставляет флаг
/// `_stopped`, но не прерывает физически ни висящий HTTP-запрос `_fetch`, ни
/// уже начавшийся `Future.delayed(retryDelay)`. Текущий виток долетает до
/// проверки `if (_stopped) return` и просто игнорируется — новый не
/// стартует. Значит `dispose()` может подождать до 30 с (таймаут long-poll)
/// или до `retryDelay`, прежде чем цикл реально затихнет.
///
/// Поток ПЕРЕИСПОЛЬЗУЕМ: пара `dispose()`/`start()` — это «ушли в фон /
/// вернулись», а не финальное закрытие. `start()` сбрасывает `_stopped`, а
/// счётчик `_generation` гарантирует, что доживающий виток прошлого цикла не
/// подмешает события в новый (иначе на возврате из фона могли бы крутиться
/// два цикла разом и дважды продвигать `token`).
class ChannelPeekStream {
  final Client client;
  final String roomId;
  final Room room;
  final void Function(List<Event>) onEvents;
  final Duration retryDelay;
  final PeekFetch _fetch;

  String? token;
  bool _stopped = false;
  int _generation = 0;
  Future<void>? _loop;

  ChannelPeekStream({
    required this.client,
    required this.roomId,
    required this.room,
    required this.onEvents,
    String? from,
    PeekFetch? fetch,
    this.retryDelay = const Duration(seconds: 3),
  }) : token = from,
       _fetch = fetch ?? ((f, id) => safePeekFetch(client, f, id));

  /// Запускает (или ВОЗОБНОВЛЯЕТ после `dispose()`) живой хвост.
  ///
  /// Сброс `_stopped` обязателен: экран зовёт `dispose()` на уходе в фон и
  /// `start()` на возврате, а без сброса `_run()` вышел бы на первой же
  /// проверке `while (!_stopped)` — лента замерзала бы навсегда после
  /// первого сворачивания приложения.
  void start() {
    if (_loop != null) return;
    _stopped = false;
    _loop = _run();
  }

  Future<void> _run() async {
    // Каждый виток сверяется со СВОИМ поколением: `dispose()` инкрементит
    // `_generation`, поэтому «хвост» прошлого цикла, доживающий висящий
    // long-poll (до 30 с), не подмешает события и не продвинет токен уже
    // после того, как экран запустил новый поток.
    final generation = _generation;
    while (!_stopped && generation == _generation) {
      try {
        final response = await _fetch(token, roomId);
        if (_stopped || generation != _generation) return;
        token = response.end ?? token;
        final events = peekEventsToTimeline(response.chunk ?? const [], room);
        if (events.isNotEmpty) onEvents(events);
      } catch (e, s) {
        if (_stopped || generation != _generation) return;
        Logs().w('ChannelPeek: long-poll $roomId прервался', e, s);
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  /// Кооперативная остановка: см. docstring класса. Поток ПЕРЕИСПОЛЬЗУЕМ —
  /// после `dispose()` его оживляет `start()`.
  Future<void> dispose() async {
    _stopped = true;
    _generation++;
    _loop = null;
  }
}
