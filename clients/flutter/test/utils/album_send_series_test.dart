// ledger:RL-album-send-partial-failure
//
// Жалоба 2026-09-25 (Александр, iOS): «Пытался отправить 20+ видео. В итоге
// ошибка с таким сообщением. Какой значок повтора нажимать?» По прод-БД: альбом
// n=23, на сервере 6 — первый же обрыв заливки (`unexpected EOF` в MMR)
// `rethrow`-ом оборвал серию, и 17 не начатых видео пропали молча.
//
// Страж — на реальном оркестраторе `AlbumSendSeries` (им пользуется
// `SendFileDialog._send`), зависимости внедрены: заливка, подготовка,
// ожидание сети и задержки — без сети и без media_kit.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:matrix/matrix.dart';

import 'package:liza/utils/album_send_series.dart';
import 'package:liza/utils/upload_error_classifier.dart';

/// Сценарий заливки: сколько раз подряд файл i падает и чем.
class _Net {
  final Map<int, List<Object>> failuresFor;
  final List<(int, int)> calls = [];
  int inFlight = 0;
  int maxInFlight = 0;

  _Net([this.failuresFor = const {}]);

  Future<void> upload(int i, int prepared, int attempt) async {
    calls.add((i, attempt));
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      await Future<void>.value();
      final queue = failuresFor[i];
      if (queue != null && queue.isNotEmpty) throw queue.removeAt(0);
    } finally {
      inFlight--;
    }
  }

  int attemptsOf(int i) => calls.where((c) => c.$1 == i).length;
}

Object _eof() => ClientException('Connection closed: unexpected EOF');

List<Object> _eofTimes(int n) => [for (var k = 0; k < n; k++) _eof()];

AlbumSendSeries<int> _series({
  required int count,
  required _Net net,
  Set<int> prepareFails = const {},
  Set<int> cancelled = const {},
  Future<bool> Function()? waitForReconnect,
  List<int>? prepared,
  List<List<int>>? waitingLog,
  int sizeBytes = 1,
  int breakerHeldBytes = 256 * 1024 * 1024,
}) => AlbumSendSeries<int>(
  count: count,
  prepare: (i) async {
    prepared?.add(i);
    if (prepareFails.contains(i)) {
      throw const FileSystemException('транскод упал');
    }
    return i;
  },
  upload: net.upload,
  sizeOf: (_) => sizeBytes,
  isCancelled: cancelled.contains,
  waitForReconnect: waitForReconnect ?? () async => true,
  onWaiting: (indices) => waitingLog?.add(List.of(indices)),
  breakerHeldBytes: breakerHeldBytes,
  delay: (_) async {},
);

void main() {
  group('AC:RL-album-send-partial-failure/1 — провал заливки одного файла не '
      'рвёт серию', () {
    for (final n in [3, 23]) {
      for (final (label, k) in [
        ('первый', 0),
        ('средний', n ~/ 2),
        ('последний', n - 1),
      ]) {
        test('N=$n, K=$label: N−1 отправлены, K «не отправлен» с ↻, '
            '0 молча пропавших', () async {
          // Transient-провал на всех 3 попытках и на досыле после паузы:
          // файл K остаётся упавшим до конца серии.
          final net = _Net({k: _eofTimes(100)});
          final result = await _series(count: n, net: net).run();

          expect(result.total, n);
          for (var i = 0; i < n; i++) {
            expect(
              result.outcomes[i],
              i == k ? SeriesItemOutcome.failedUpload : SeriesItemOutcome.sent,
              reason: 'файл $i',
            );
          }
          expect(result.notSent, 1);
          expect(result.retryable, 1, reason: 'байты у SDK — ↻ законен');
          // Ни одного файла, до которого серия не дошла.
          expect(
            result.outcomes.where((o) => o == SeriesItemOutcome.notStarted),
            isEmpty,
          );
        });
      }
    }
  });

  test('AC:RL-album-send-partial-failure/2 — провал ПОДГОТОВКИ снимает только '
      'свой файл', () async {
    for (final k in [0, 5, 22]) {
      final net = _Net();
      final result = await _series(
        count: 23,
        net: net,
        prepareFails: {k},
      ).run();
      expect(result.outcomes[k], SeriesItemOutcome.failedPrepare);
      expect(
        result.outcomes.where((o) => o == SeriesItemOutcome.sent).length,
        22,
        reason: 'K=$k',
      );
      expect(net.attemptsOf(k), 0, reason: 'нечего заливать');
    }
  });

  group('AC:RL-album-send-partial-failure/3 — повторы заливки', () {
    test('transient: до 3 попыток, успех на 3-й — файл отправлен', () async {
      final net = _Net({1: _eofTimes(2)});
      final result = await _series(count: 3, net: net).run();
      expect(net.attemptsOf(1), 3);
      expect(result.outcomes[1], SeriesItemOutcome.sent);
    });

    for (final (label, error) in [
      (
        '413',
        MatrixException.fromJson({
          'errcode': 'M_TOO_LARGE',
          'error': 'too large',
        }),
      ),
      (
        '403',
        MatrixException.fromJson({'errcode': 'M_FORBIDDEN', 'error': 'quota'}),
      ),
      ('диск', const FileSystemException('ENOSPC')),
    ]) {
      test('terminal ($label): ровно 1 попытка, без досыла', () async {
        final net = _Net({
          1: [error, error, error],
        });
        final result = await _series(count: 3, net: net).run();
        expect(net.attemptsOf(1), 1);
        expect(result.outcomes[1], SeriesItemOutcome.failedUpload);
        expect(result.outcomes[2], SeriesItemOutcome.sent);
      });
    }
  });

  test(
    'AC:RL-album-send-partial-failure/4 — 2 упавших подряд: новые файлы не '
    'начинаются до возврата связи; не начатые — «ожидание», не ошибка',
    () async {
      // Сеть лежит: файлы 0 и 1 падают на всех попытках.
      final net = _Net({0: _eofTimes(3), 1: _eofTimes(3)});
      final prepared = <int>[];
      final waiting = <List<int>>[];
      final reconnect = Completer<bool>();
      final done = _series(
        count: 6,
        net: net,
        prepared: prepared,
        waitingLog: waiting,
        waitForReconnect: () => reconnect.future,
      ).run();

      await pumpEventQueue();
      // Рубильник: подготовлены только 0 и 1, файлы 2..5 не тронуты.
      expect(prepared, [0, 1]);
      expect(waiting, [
        [0, 1, 2, 3, 4, 5],
      ]);

      reconnect.complete(true);
      final result = await done;
      expect(prepared, [0, 1, 2, 3, 4, 5]);
      expect(result.notSent, 0, reason: 'после возврата сети ушли все');
    },
  );

  test('AC:RL-album-send-partial-failure/4 — лимит удерживаемых байтов '
      'упавших тоже ставит серию на паузу', () async {
    final net = _Net({0: _eofTimes(3)});
    final prepared = <int>[];
    final reconnect = Completer<bool>();
    final done = _series(
      count: 4,
      net: net,
      prepared: prepared,
      sizeBytes: 300,
      breakerHeldBytes: 256,
      waitForReconnect: () => reconnect.future,
    ).run();
    await pumpEventQueue();
    expect(prepared, [0], reason: 'один упавший 300 Б ≥ лимита 256 Б');
    reconnect.complete(true);
    expect((await done).notSent, 0);
  });

  test('AC:RL-album-send-partial-failure/5 — после возврата связи сначала '
      'досылаются упавшие, затем очередь; параллельных заливок 0', () async {
    final net = _Net({0: _eofTimes(3), 1: _eofTimes(3)});
    final result = await _series(count: 4, net: net).run();

    final order = net.calls.map((c) => c.$1).toList();
    // 0×3, 1×3 (рубильник), досыл 0, досыл 1, затем 2, 3.
    expect(order, [0, 0, 0, 1, 1, 1, 0, 1, 2, 3]);
    expect(net.maxInFlight, 1);
    expect(result.notSent, 0);
  });

  test('AC:RL-album-send-partial-failure/10 — отмена крестиком тихая и не '
      'в счёт неотправленных; остальные идут дальше', () async {
    final net = _Net();
    final result = await _series(count: 5, net: net, cancelled: {2}).run();
    expect(result.outcomes[2], SeriesItemOutcome.cancelled);
    expect(net.attemptsOf(2), 0);
    expect(result.notSent, 0);
    expect(result.outcomes.where((o) => o == SeriesItemOutcome.sent).length, 4);
  });

  test('сеть не вернулась за все раунды: не начатые учтены в итоге, а не '
      'пропали молча', () async {
    final net = _Net({0: _eofTimes(1000), 1: _eofTimes(1000)});
    final result = await _series(count: 5, net: net).run();
    expect(result.outcomes.sublist(2), [
      SeriesItemOutcome.notStarted,
      SeriesItemOutcome.notStarted,
      SeriesItemOutcome.notStarted,
    ]);
    expect(result.notSent, 5);
    expect(result.retryable, 2);
  });

  test('выход из аккаунта во время паузы — серия завершается', () async {
    final net = _Net({0: _eofTimes(3), 1: _eofTimes(3)});
    final result = await _series(
      count: 3,
      net: net,
      waitForReconnect: () async => false,
    ).run();
    expect(result.outcomes[2], SeriesItemOutcome.notStarted);
    expect(result.notSent, 3);
  });

  test(
    'AC:RL-album-send-partial-failure/3 — заливка прошла, но sendEvent '
    'вернул null (SDK не бросает): НЕ «отправлено», а повтор тем же txid',
    () async {
      expect(
        classifyUploadError(const SendEventDroppedException()),
        UploadErrorKind.transient,
      );
      final net = _Net({
        1: [const SendEventDroppedException()],
      });
      final result = await _series(count: 3, net: net).run();
      expect(net.attemptsOf(1), 2);
      expect(result.outcomes[1], SeriesItemOutcome.sent);
    },
  );

  test('AC:RL-album-send-partial-failure/4 — terminal-отказ между двумя '
      'сетевыми провалами рвёт цепочку: паузы нет', () async {
    final forbidden = MatrixException.fromJson({
      'errcode': 'M_FORBIDDEN',
      'error': 'quota',
    });
    final net = _Net({
      0: _eofTimes(3),
      1: [forbidden],
      2: _eofTimes(3),
    });
    final waiting = <List<int>>[];
    final prepared = <int>[];
    final result = await _series(
      count: 5,
      net: net,
      prepared: prepared,
      waitingLog: waiting,
      waitForReconnect: () async => true,
    ).run();
    // 0 (сеть) → 1 (terminal, streak=0) → 2 (сеть, streak=1) → 3, 4 без паузы.
    expect(prepared, [0, 1, 2, 3, 4]);
    expect(waiting.first, [
      0,
      2,
    ], reason: 'пауза только в конце — дослать 0 и 2');
    expect(result.outcomes[1], SeriesItemOutcome.failedUpload);
  });
}
