import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/utils/file_description.dart';
import 'package:liza/utils/upload_progress_tracker.dart';

/// Итог попытки повторить упавшее сообщение.
enum ResendOutcome {
  /// `sendAgain` запущен.
  started,

  /// Событие не в статусе ошибки — повторять нечего.
  notFailed,

  /// Байтов вложения в памяти нет (перезапуск приложения): `sendAgain` удалил
  /// бы сообщение (LABA-2239). Вызвавший показывает тост и оставляет событие.
  missingMedia,

  /// Повтор этого события уже идёт (двойной тап по ↻).
  alreadyInFlight,

  /// Событием владеет идущая серия отправки альбома — дошлёт сама.
  ownedBySeries,
}

/// Единая точка РУЧНОГО и авто-повтора упавшего сообщения.
///
/// Раньше каждый вызывающий звал `event.sendAgain()` сам, и гард LABA-2239
/// стоял не везде: ↻ на пузыре видео удалял сообщение после перезапуска
/// приложения. Здесь собраны все условия: гард потери байтов, анти-дабл-тап
/// (виджет держит устаревший `Event` в статусе error, и проверка статуса
/// внутри SDK второй тап не отсекает), владение серии и сброс устаревшего
/// класса ошибки (иначе прошлый terminal навсегда блокирует авто-досыл).
class FailedMediaResender {
  FailedMediaResender._();

  static final Set<String> _inFlight = {};

  /// Идёт ли сейчас повтор этого события.
  static bool isInFlight(String eventId) => _inFlight.contains(eventId);

  /// Повторить отправку [event]. Сама отправка идёт в фоне; результат —
  /// только решение, запущена ли она.
  static ResendOutcome resend(Event event) {
    final outcome = _claim(event);
    if (outcome != ResendOutcome.started) return outcome;
    unawaited(_run(event));
    return outcome;
  }

  /// То же, что [resend], но дожидается окончания отправки (авто-досыл и
  /// последовательный повтор).
  static Future<ResendOutcome> resendAndWait(Event event) async {
    final outcome = _claim(event);
    if (outcome == ResendOutcome.started) await _run(event);
    return outcome;
  }

  static ResendOutcome _claim(Event event) {
    if (!event.status.isError) return ResendOutcome.notFailed;
    if (event.isUnresendableMissingMedia) return ResendOutcome.missingMedia;
    final id = event.eventId;
    if (UploadProgressTracker.instance.isOwnedBySeries(id)) {
      return ResendOutcome.ownedBySeries;
    }
    if (!_inFlight.add(id)) return ResendOutcome.alreadyInFlight;
    UploadProgressTracker.instance.clearErrorKind(id);
    return ResendOutcome.started;
  }

  static Future<void> _run(Event event) async {
    try {
      await event.sendAgain();
    } catch (e) {
      Logs().w('[resend] повтор ${event.eventId} не удался: ${e.runtimeType}');
    } finally {
      _inFlight.remove(event.eventId);
    }
  }

  /// Повторить несколько событий СТРОГО по очереди: параллельно K заливок
  /// держали бы K копий файла в памяти, а трекер прогресса знает только один
  /// активный txid. Возвращает число запущенных повторов.
  static Future<int> resendSequentially(Iterable<Event> events) async {
    var started = 0;
    for (final event in events.toList()) {
      if (await resendAndWait(event) == ResendOutcome.started) started++;
    }
    return started;
  }

  /// Для тестов: пометить повтор события как идущий (двойной тап).
  @visibleForTesting
  static void markInFlightForTest(String eventId) => _inFlight.add(eventId);

  /// Для тестов: сбросить множество повторов в полёте.
  @visibleForTesting
  static void resetForTest() => _inFlight.clear();
}
