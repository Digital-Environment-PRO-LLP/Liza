import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:liza/utils/file_description.dart';
import 'package:liza/utils/upload_error_classifier.dart';
import 'package:liza/utils/upload_progress_tracker.dart';

/// Досылает упавшие голосовые/медиа-сообщения, когда связь с сервером
/// возвращается.
///
/// Проблема (кейс Алексея, 28-авг): на флапающей сети без VPN домен Synapse то
/// резолвится, то рвётся (`Failed host lookup errno=7`, `Connection attempt
/// cancelled`). Голосовое/медиа падает в `EventStatus.error`, и сегодня
/// пользователь вынужден вручную тыкать «отправить повторно» на каждом. Сервис
/// делает досыл автоматически при восстановлении sync.
///
/// Живёт на уровне `MatrixState` (НЕ `ChatController`): целевой сценарий —
/// «отправил голосовое → упало → УШЁЛ из чата → связь вернулась». Подписка,
/// привязанная к экрану чата, умерла бы вместе с ним. Событие в `error` и его
/// байты (`room.sendingFilePlaceholders`) живут на `Room` независимо от
/// открытости чата.
///
/// Логика инъектируема (поток статуса, поставщик комнат, флаг foreground,
/// debounce) — тестируется без платформы, как `NetworkRecoveryTrigger`.
class FailedSendRetryService {
  FailedSendRetryService({
    required Stream<SyncStatusUpdate> syncStatus,
    required Future<List<Event>> Function() failedMediaEvents,
    Future<void> Function(Event)? resend,
    bool Function()? isForeground,
    Duration debounce = const Duration(seconds: 3),
  })  : _syncStatus = syncStatus,
        _failedMediaEvents = failedMediaEvents,
        _resend = resend ?? ((event) => event.sendAgain()),
        _isForeground = isForeground,
        _debounce = debounce;

  /// Production-обёртка: собрать упавшее медиа со всех комнат по ключам
  /// `sendingFilePlaceholders` (= txid'ы медиа с ЖИВЫМИ байтами; по построению
  /// `!isUnresendableMissingMedia`). Переживает закрытие чата — данные на `Room`.
  static Future<List<Event>> collectFailedMediaEvents(
    List<Room> Function() rooms,
  ) async {
    final events = <Event>[];
    for (final room in rooms()) {
      for (final txid in room.sendingFilePlaceholders.keys.toList()) {
        // getEventById при отсутствии события в БД уходит в СЕТЬ
        // (client.getOneRoomEvent) — а мы зовём его сразу на возврате связи,
        // когда сеть ещё нестабильна. Необработанное исключение прервало бы
        // сбор для ВСЕХ событий; глушим по одному (D-4).
        try {
          final event = await room.getEventById(txid);
          if (event != null) events.add(event);
        } catch (_) {
          continue;
        }
      }
    }
    return events;
  }

  final Stream<SyncStatusUpdate> _syncStatus;
  final Future<List<Event>> Function() _failedMediaEvents;
  final Future<void> Function(Event) _resend;
  final bool Function()? _isForeground;
  final Duration _debounce;

  StreamSubscription<SyncStatusUpdate>? _sub;
  Timer? _debounceTimer;

  /// Была ли СЕТЕВАЯ ошибка sync с прошлого успешного цикла. Взводится ТОЛЬКО
  /// на `SyncConnectionException` (не на 4xx-sync вроде `M_UNKNOWN_TOKEN`, где
  /// возврат «связи» ретрай не оправдывает). Триггер досыла = переход
  /// error→finished, а НЕ голый `finished` (он летит каждые ~30с в норме —
  /// иначе шторм в штатном sync-цикле).
  bool _hadConnectionError = false;

  /// txid'ы, уже досланные авто-ретраем в этой сессии. Кап «1 авто-ретрай на
  /// событие»: дальше — только ручной тап. Ограничивает и дубли при флапе
  /// («PUT дошёл, ответ потерян»), и orphaned MXC-объекты (каждый `sendAgain`
  /// медиа = новый upload в хранилище).
  final Set<String> _autoRetriedTxids = {};

  /// txid'ы с in-flight авто-`sendAgain` (add перед вызовом, remove в
  /// `whenComplete`) — против повторного входа на дребезге сети.
  final Set<String> _retrying = {};

  void start() {
    _sub = _syncStatus.listen(_onStatus);
  }

  void _onStatus(SyncStatusUpdate update) {
    if (update.status == SyncStatus.error &&
        update.error?.exception is SyncConnectionException) {
      _hadConnectionError = true;
      return;
    }
    if (update.status != SyncStatus.finished) return;
    if (!_hadConnectionError) return;
    _hadConnectionError = false;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _retryNow);
  }

  Future<void> _retryNow() async {
    final isForeground = _isForeground;
    // Не досылаем в фоне/на нестабильном cold-sync после возврата из
    // background — только при resumed (mobile) / resumed|inactive (desktop),
    // как lifecycle-гейт `_sendReadMarkerNow`.
    if (isForeground != null && !isForeground()) return;
    for (final event in await _failedMediaEvents()) {
      final txid = event.eventId;
      if (_autoRetriedTxids.contains(txid)) continue;
      if (_retrying.contains(txid)) continue;
      // Синхронная проверка НЕПОСРЕДСТВЕННО перед sendAgain (не по кэшу).
      if (!canAutoResend(event)) continue;
      _autoRetriedTxids.add(txid);
      _retrying.add(txid);
      unawaited(_resend(event).whenComplete(() => _retrying.remove(txid)));
    }
  }

  void dispose() {
    _debounceTimer?.cancel();
    _sub?.cancel();
  }
}

/// Пригодно ли событие к АВТО-досылу при возврате связи. Синхронно, проверять
/// НЕПОСРЕДСТВЕННО перед `sendAgain` (не по кэшу — закрывает race-окно
/// молчаливого удаления голосового, `RL-resend-missing-media-guard`).
///
/// - `status.isError` — только упавшее (не sending/sent);
/// - `!isUnresendableMissingMedia` — байты на месте, иначе `sendAgain` вызвал
///   бы `cancelSend` и УДАЛИЛ сообщение (LABA-2239, `RL-resend-missing-media-guard`);
/// - причина НЕ `terminal` — 403/413/диск возврат связи не лечит
///   (`RL-upload-terminal-error-no-retry`); отсутствие записи kind (сетевой
///   обрыв ДО ответа сервера — самый частый кейс) трактуем как transient
///   (ретраим).
bool canAutoResend(Event event) {
  if (!event.status.isError) return false;
  if (event.isUnresendableMissingMedia) return false;
  final kind = UploadProgressTracker.instance.errorKindFor(event.eventId);
  return kind != UploadErrorKind.terminal;
}
