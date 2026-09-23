import 'package:flutter/foundation.dart';

import 'package:liza/utils/upload_error_classifier.dart';

/// Глобальный реестр прогресса загрузки вложений, keyed по `txid`
/// (он же `event.eventId` для pending-события до того, как сервер вернёт
/// настоящий eventId).
///
/// Используется как мост между диалогом отправки (`send_file_dialog.dart`)
/// и виджетом-bubble видео-события в ленте (`pages/chat/events/
/// video_player.dart`), который рисует прогресс поверх превью.
///
/// Источников прогресса два:
/// - **реальный** — `UploadProgressHttpClient` считает отданные байты на
///   HTTP-уровне (не-Web платформы) и зовёт [reportActiveProgress];
/// - **псевдо** — `_UploadProgressReporter` в `send_file_dialog` оценивает
///   процент по времени; нужен на Web и в фазе до начала отдачи (шифрование
///   E2EE, мелкие файлы). Как только по `txid` пришёл реальный прогресс
///   ([hasRealProgress]), псевдо-источник умолкает.
/// Этап отправки вложения. Шкала прогресса НЕ сквозная: «Сжатие 100%» и
/// «Отправка 3%» — это два разных этапа с явной подписью, а не откат числа
/// назад (иначе читается как «зависло»). Внутри этапа значение монотонно.
///
/// Этап `preparing` — окно между тапом «Отправить» и началом транскода
/// (чтение файла, HEIC, извлечение постера). Раньше это окно было немым:
/// пузыря ещё не существовало, а снекбар физически не успевал отрисоваться.
enum UploadPhase { preparing, compressing, uploading }

class UploadProgressTracker {
  UploadProgressTracker._();
  static final UploadProgressTracker instance = UploadProgressTracker._();

  final Map<String, ValueNotifier<double>> _notifiers = {};

  /// Этап по `txid` — ОТДЕЛЬНЫЙ канал от `_notifiers`, чтобы не менять тип
  /// публичного `byId` (его читают бабл и стражи). SDK-шный
  /// `event.fileSendingStatus` сюда не годится: его enum
  /// (`generatingThumbnail/encrypting/uploading`) не покрывает нашу фазу ДО
  /// `sendFileEvent`, а посторонняя строка в `unsigned[fileSendingStatusKey]`
  /// молча читается как null (`singleWhereOrNull` по `.name`).
  final Map<String, ValueNotifier<UploadPhase>> _phases = {};
  final Set<String> _realProgressTxids = {};
  final Set<String> _cancelledTxids = {};
  final Map<String, String> _errorReasons = {};
  // Класс последней ошибки отправки по txid (terminal/transient). Читает
  // `FailedSendRetryService`: авто-ретрай при возврате связи досылает ТОЛЬКО
  // transient, а terminal (403/413/диск) НЕ трогает (иначе retry-шторм,
  // `RL-upload-terminal-error-no-retry`). Тот же двухфазный lifecycle, что
  // `_errorReasons`: НЕ чистится в `unregister` (читается ПОСЛЕ ухода события
  // в `EventStatus.error`), снимается на следующей попытке (`register`).
  final Map<String, UploadErrorKind> _errorKinds = {};
  String? _activeTxid;

  /// Создать notifier для указанного `txid` и положить его в реестр.
  /// Возвращает уже зарегистрированный notifier, если такой txid уже был —
  /// безопасно при повторных вызовах (например, retry на rate-limit).
  ValueNotifier<double> register(String txid) {
    // Свежая попытка по этому txid — снимаем причину прошлой ошибки, чтобы
    // не показать устаревший тултип поверх нового прогресса.
    _errorReasons.remove(txid);
    _errorKinds.remove(txid);
    _phases.putIfAbsent(
      txid,
      () => ValueNotifier<UploadPhase>(UploadPhase.preparing),
    );
    return _notifiers.putIfAbsent(txid, () => ValueNotifier<double>(0));
  }

  /// Этап по id события (`txid` до подтверждения сервером). null — отправка
  /// по этому id не идёт.
  ValueNotifier<UploadPhase>? phaseFor(String id) => _phases[id];

  /// Перевести отправку на новый этап и обнулить прогресс: шкала внутри
  /// этапа своя (см. [UploadPhase]).
  void reportPhase(String txid, UploadPhase phase) {
    final notifier = _phases[txid];
    if (notifier == null || notifier.value == phase) return;
    notifier.value = phase;
    _notifiers[txid]?.value = 0;
  }

  /// Прогресс ЭТАПА СЖАТИЯ (0..100 от `video_compress`). Отдельно от
  /// [reportActiveProgress], потому что тот принадлежит HTTP-отдаче и
  /// выставляет `_realProgressTxids` — а сжатие к отдаче отношения не имеет.
  /// Монотонность внутри этапа обязательна: назад не откатываемся.
  void reportCompressProgress(String txid, double percent) {
    if (_phases[txid]?.value != UploadPhase.compressing) return;
    final notifier = _notifiers[txid];
    if (notifier == null) return;
    final value = (percent / 100).clamp(0.0, 1.0);
    if (value < notifier.value) return;
    notifier.value = value;
  }

  /// Поднять notifier по id (`event.eventId`). Возвращает null, если
  /// загрузка не идёт.
  ValueNotifier<double>? byId(String id) => _notifiers[id];

  /// Удалить notifier (вызывается после complete/error). Disposed
  /// notifier более не используется виджетами.
  void unregister(String txid) {
    final n = _notifiers.remove(txid);
    n?.dispose();
    _phases.remove(txid)?.dispose();
    _realProgressTxids.remove(txid);
    _cancelledTxids.remove(txid);
    if (_activeTxid == txid) _activeTxid = null;
    // ВНИМАНИЕ: _errorReasons НЕ чистим здесь. `_UploadRetryOverlay`/значок
    // ошибки бабла читают причину ПОСЛЕ того, как событие ушло в
    // `EventStatus.error` (а это происходит уже после unregister в finally
    // send_file_dialog). Причина снимается на следующей попытке отправки
    // (register) — двухфазный lifecycle.
  }

  /// Сохранить человекочитаемую причину терминальной ошибки отправки по `txid`
  /// (== `event.eventId` pending-события). Читают виджеты ленты для тултипа.
  void reportError(String txid, String reason) => _errorReasons[txid] = reason;

  /// Причина последней терминальной ошибки отправки по id события, или null.
  String? errorFor(String id) => _errorReasons[id];

  /// Сохранить КЛАСС ошибки отправки (terminal/transient) по `txid`.
  /// Заполняется в точке `catchError` отправки, где исключение ещё живо
  /// (`classifyUploadError(e)`) — на самом `Event` в статусе error errcode НЕ
  /// хранится, поэтому решить «ретраить ли» позже можно только по этой записи.
  void reportErrorKind(String txid, UploadErrorKind kind) =>
      _errorKinds[txid] = kind;

  /// Класс последней ошибки отправки по id события, или null (запись не
  /// делалась — напр. сетевой обрыв ДО ответа: трактуем как transient).
  UploadErrorKind? errorKindFor(String id) => _errorKinds[id];

  /// Снять записанный класс ошибки по `txid`. Зовётся при РУЧНОМ «отправить
  /// повторно»: иначе устаревший `terminal` (напр. от 403 квоты, которую уже
  /// подняли) навсегда блокировал бы АВТО-ретрай этого события, даже если
  /// следующий сбой был сетевым (transient). После сброса kind=null → авто-
  /// ретрай снова доверяет дефолту (null=transient).
  void clearErrorKind(String txid) => _errorKinds.remove(txid);

  /// Запросить отмену загрузки по `txid`. Флаг читает
  /// [UploadProgressHttpClient]: на ближайшем чанке тела отдача обрывается
  /// `MatrixException`-ом (терминальная ошибка для retry-цикла
  /// `room.sendFileEvent` — иначе SDK повторял бы заливку до
  /// `sendTimelineEventTimeout`). Удаление самого pending-события из ленты —
  /// отдельно через `Event.cancelSend()` на стороне виджета-бабла.
  void requestCancel(String txid) => _cancelledTxids.add(txid);

  /// Запрошена ли отмена для этого `txid`.
  bool isCancelled(String txid) => _cancelledTxids.contains(txid);

  /// Запрошена ли отмена для текущего активного txid (для HTTP-клиента,
  /// который знает только про активную отдачу).
  bool get isActiveCancelled {
    final txid = _activeTxid;
    return txid != null && _cancelledTxids.contains(txid);
  }

  /// Назначить `txid`, к которому `UploadProgressHttpClient` привяжет
  /// отчёты о реальном прогрессе. Вызывается перед началом отдачи файла.
  void markActive(String? txid) => _activeTxid = txid;

  /// Реальный прогресс отдачи тела запроса (`sent`/`total` байт) для
  /// активного txid. Источник — `UploadProgressHttpClient`.
  void reportActiveProgress(int sent, int total) {
    final txid = _activeTxid;
    if (txid == null || total <= 0) return;
    final notifier = _notifiers[txid];
    if (notifier == null) return;
    _realProgressTxids.add(txid);
    // Кап 0.99: «все байты отданы в сокет» ≠ «сервер принял и подтвердил».
    // 100% показываем только фактом исчезновения overlay-я (unregister
    // после успешного ответа сервера) — иначе пользователь видит «100%»,
    // пока загрузка на деле ещё висит.
    notifier.value = (sent / total).clamp(0.0, 0.99);
  }

  /// Пришёл ли по этому txid хотя бы один отчёт реального прогресса.
  /// Если да — псевдо-прогресс по этому txid должен замолчать.
  bool hasRealProgress(String txid) => _realProgressTxids.contains(txid);
}
