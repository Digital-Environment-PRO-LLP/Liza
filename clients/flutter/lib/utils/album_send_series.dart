import 'dart:async';

import 'package:matrix/matrix.dart';

import 'package:liza/utils/upload_error_classifier.dart';

/// Итог одного файла серии.
enum SeriesItemOutcome {
  /// Событие отправлено.
  sent,

  /// Заливка не удалась: событие в `EventStatus.error`, байты у SDK
  /// (`sendingFilePlaceholders`) — повтор ↻ законен.
  failedUpload,

  /// Подготовка не удалась (постер, транскод, размер) — пузырь снят, байтов
  /// нет, повторять нечего.
  failedPrepare,

  /// Серия сдалась до начала этого файла (сеть так и не вернулась) — пузырь
  /// снят, файл не отправлен.
  notStarted,

  /// Пользователь отменил крестиком — тихо, в неотправленные не считается.
  cancelled,
}

/// Итог всей серии.
class SeriesResult {
  final List<SeriesItemOutcome> outcomes;
  const SeriesResult(this.outcomes);

  int get total => outcomes.length;

  /// Сколько файлов не ушло (отмена крестиком — не в счёт).
  int get notSent => outcomes
      .where(
        (o) => o != SeriesItemOutcome.sent && o != SeriesItemOutcome.cancelled,
      )
      .length;

  /// Сколько неотправленных можно повторить ↻ (байты у SDK).
  int get retryable =>
      outcomes.where((o) => o == SeriesItemOutcome.failedUpload).length;
}

/// Последовательная отправка набора файлов (альбом или несколько вложений)
/// с устойчивостью к обрывам мобильной сети.
///
/// Инцидент 2026-09-25 (Александр, 23 видео): первый же провал заливки
/// `rethrow`-ом обрывал всю серию, и пузыри 17 не начатых видео снимались
/// молча. Причин провала две: мобильная сеть рвёт тело заливки
/// (`unexpected EOF` в MMR), а SDK отсчитывает свои 30 с повторов от НАЧАЛА
/// заливки (`room.dart` `timeoutDate`) — у файла, который льётся дольше, на
/// первом же обрыве повторов ноль.
///
/// Правила серии:
/// - провал ПОДГОТОВКИ снимает только свой файл; серия идёт дальше;
/// - transient-провал заливки повторяется до [maxAttempts] раз тем же txid
///   (каждый вызов `sendFileEvent` — свежее окно SDK); terminal — ни разу;
/// - после [breakerStreak] подряд упавших на сети файлов (успех или
///   terminal-отказ сервера цепочку рвут — сервер ответил) ИЛИ когда байты упавших,
///   которые держит SDK, достигли [breakerHeldBytes], новые файлы не
///   начинаются: серия ждёт возврата связи, затем по очереди досылает
///   упавшие и продолжает. Иначе на мёртвой сети каждый следующий файл
///   ложился бы в память упавшим (17 × до 150 МБ → выгрузка iOS → байты
///   потеряны, LABA-2239);
/// - пауз не больше [maxWaitRounds]: если связь «вернулась», а заливка всё
///   равно падает, серия сдаётся — не начатые файлы снимаются и учитываются
///   в итоге, а не пропадают молча.
///
/// Платформенные зависимости внедряются — логика гоняется host-тестом без
/// сети и media_kit.
class AlbumSendSeries<P> {
  AlbumSendSeries({
    required this.count,
    required this.prepare,
    required this.upload,
    required this.sizeOf,
    required this.isCancelled,
    required this.waitForReconnect,
    this.onPrepareFailed,
    this.onUploadFailed,
    this.onSent,
    this.onWaiting,
    this.onCancelled,
    this.retryDelays = const [Duration(seconds: 2), Duration(seconds: 5)],
    this.breakerStreak = 2,
    this.breakerHeldBytes = 256 * 1024 * 1024,
    this.maxWaitRounds = 5,
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final int count;

  /// Подготовить файл i (чтение, транскод, постер). Бросает — провал
  /// подготовки.
  final Future<P> Function(int i) prepare;

  /// Одна попытка отправки подготовленного файла i (`sendFileEvent`).
  final Future<void> Function(int i, P prepared, int attempt) upload;

  /// Размер байтов, которые SDK держит в памяти для упавшего файла.
  final int Function(P prepared) sizeOf;

  final bool Function(int i) isCancelled;

  /// Дождаться, когда связь с сервером снова есть. `false` — ждать больше
  /// нечего (выход из аккаунта).
  final Future<bool> Function() waitForReconnect;

  final void Function(int i, Object error)? onPrepareFailed;

  /// Окончательный провал заливки файла i (повторы исчерпаны или terminal).
  final void Function(int i, Object error, UploadErrorKind kind)?
  onUploadFailed;
  final void Function(int i)? onSent;

  /// Серия встаёт на паузу: [indices] — упавшие и не начатые файлы.
  final void Function(List<int> indices)? onWaiting;
  final void Function(int i)? onCancelled;

  final List<Duration> retryDelays;
  final int breakerStreak;
  final int breakerHeldBytes;
  final int maxWaitRounds;
  final Future<void> Function(Duration) _delay;

  int get maxAttempts => retryDelays.length + 1;

  Future<SeriesResult> run() async {
    final outcomes = List<SeriesItemOutcome?>.filled(count, null);
    // Упавшие на заливке transient-файлы, которые серия ещё дошлёт сама.
    final pendingRetry = <int, P>{};
    var streak = 0;
    var rounds = 0;
    var next = 0;

    int heldBytes() => pendingRetry.values.fold(0, (s, p) => s + sizeOf(p));
    bool breakerOpen() =>
        streak >= breakerStreak || heldBytes() >= breakerHeldBytes;

    // Одна полная отправка файла с повторами. true — ушёл, false — упал
    // transient-ом (остаётся в pendingRetry), null — terminal/отмена.
    Future<bool?> sendWithRetries(int i, P prepared) async {
      for (var attempt = 1; ; attempt++) {
        if (isCancelled(i)) {
          outcomes[i] = SeriesItemOutcome.cancelled;
          pendingRetry.remove(i);
          onCancelled?.call(i);
          return null;
        }
        try {
          await upload(i, prepared, attempt);
          outcomes[i] = SeriesItemOutcome.sent;
          pendingRetry.remove(i);
          onSent?.call(i);
          return true;
        } catch (e) {
          if (isCancelled(i)) {
            outcomes[i] = SeriesItemOutcome.cancelled;
            pendingRetry.remove(i);
            onCancelled?.call(i);
            return null;
          }
          final kind = classifyUploadError(e);
          Logs().w(
            '[album-send] заливка ${i + 1}/$count, попытка $attempt/'
            '$maxAttempts: ${e.runtimeType} ($kind)',
          );
          if (kind == UploadErrorKind.terminal) {
            outcomes[i] = SeriesItemOutcome.failedUpload;
            pendingRetry.remove(i);
            onUploadFailed?.call(i, e, kind);
            return null;
          }
          if (attempt >= maxAttempts) {
            outcomes[i] = SeriesItemOutcome.failedUpload;
            pendingRetry[i] = prepared;
            onUploadFailed?.call(i, e, kind);
            return false;
          }
          await _delay(retryDelays[attempt - 1]);
        }
      }
    }

    Future<void> processNext(int i) async {
      if (isCancelled(i)) {
        outcomes[i] = SeriesItemOutcome.cancelled;
        onCancelled?.call(i);
        return;
      }
      final P prepared;
      try {
        prepared = await prepare(i);
      } catch (e) {
        if (isCancelled(i)) {
          outcomes[i] = SeriesItemOutcome.cancelled;
          onCancelled?.call(i);
          return;
        }
        Logs().w('[album-send] подготовка ${i + 1}/$count: ${e.runtimeType}');
        outcomes[i] = SeriesItemOutcome.failedPrepare;
        onPrepareFailed?.call(i, e);
        return;
      }
      final ok = await sendWithRetries(i, prepared);
      if (ok == false) {
        streak++;
      } else if (outcomes[i] != SeriesItemOutcome.cancelled) {
        // Успех или terminal-отказ: сервер ответил — связь есть, цепочка
        // сетевых провалов прервана. Отмена крестиком о сети не говорит.
        streak = 0;
      }
    }

    while (true) {
      while (next < count && !breakerOpen()) {
        await processNext(next++);
      }
      final waiting = [
        ...pendingRetry.keys,
        for (var i = next; i < count; i++)
          if (!isCancelled(i)) i,
      ];
      if (waiting.isEmpty) break;
      if (rounds >= maxWaitRounds) break;
      rounds++;
      onWaiting?.call(waiting);
      Logs().i(
        '[album-send] пауза до возврата связи: упало ${pendingRetry.length}, '
        'не начато ${count - next} из $count (раунд $rounds/$maxWaitRounds)',
      );
      if (!await waitForReconnect()) break;
      streak = 0;
      // Сначала по очереди досылаем упавшие — потом очередь.
      for (final i in pendingRetry.keys.toList()..sort()) {
        final ok = await sendWithRetries(i, pendingRetry[i] as P);
        if (ok == false) streak++;
      }
    }

    // Серия сдалась до этих файлов: пузыри снимет вызывающий (у них нет
    // байтов у SDK), в итог они идут как неотправленные.
    for (var i = next; i < count; i++) {
      if (isCancelled(i)) {
        outcomes[i] = SeriesItemOutcome.cancelled;
        onCancelled?.call(i);
      } else {
        outcomes[i] = SeriesItemOutcome.notStarted;
      }
    }
    return SeriesResult(outcomes.cast<SeriesItemOutcome>());
  }
}
