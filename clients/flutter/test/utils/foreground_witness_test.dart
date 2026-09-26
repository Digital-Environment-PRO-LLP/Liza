import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/foreground_witness.dart';
import 'package:liza/utils/idle_timeout_stream.dart';

// Сон мобильного процесса — не мёртвый канал (GlitchTip #2064, 2026-09-24,
// сборка 3767): видео 63 МБ качалось, приложение ушло в фон в 19:12:30, и при
// фоновом пробуждении в 19:30:44 idle-таймер загрузки выстрелил
// `media stream idle > 60s` → `[video-fail] swap-failed`. MMR всё это время
// честно отдавал файл (Traefik: 8,7 МБ за 496 с, пока процесс не заморозили).
//
// Сторожим обе половины контракта: сон НЕ терминалит и НЕ шлёт алёрт, а честная
// тишина ПОСЛЕ возврата — по-прежнему терминал (иначе вернули бы вечный спиннер).
//
// ledger:RL-video-viewer-save-and-overlay
void main() {
  const idle = Duration(milliseconds: 200);

  group('readBytesWithIdleTimeout + ForegroundWitness', () {
    test(
      'AC:RL-video-viewer-save-and-overlay/14 — тишина, пока процесс заморожен, '
      'НЕ терминалит; после возврата отсчёт заново',
      () async {
        final witness = ForegroundWitness.manual(
          initial: AppLifecycleState.resumed,
        );
        final controller = StreamController<List<int>>();
        final future = readBytesWithIdleTimeout(
          controller.stream,
          idleTimeout: idle,
          witness: witness,
        );
        controller.add([1]);
        witness.onStateChange(AppLifecycleState.paused);
        // Втрое дольше порога во сне — прежняя реализация тут бросала.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        witness.onStateChange(AppLifecycleState.resumed);
        // После возврата — меньше порога, и байты пошли снова.
        await Future<void>.delayed(const Duration(milliseconds: 120));
        controller.add([2]);
        await controller.close();
        await expectLater(future, completion([1, 2]));
        witness.dispose();
      },
    );

    test(
      'AC:RL-video-viewer-save-and-overlay/14 — честная тишина ПОСЛЕ возврата → '
      'TimeoutException (сон не отменяет терминал мёртвого канала)',
      () async {
        final witness = ForegroundWitness.manual(
          initial: AppLifecycleState.resumed,
        );
        final controller = StreamController<List<int>>();
        final future = readBytesWithIdleTimeout(
          controller.stream,
          idleTimeout: idle,
          witness: witness,
        );
        witness.onStateChange(AppLifecycleState.paused);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        witness.onStateChange(AppLifecycleState.resumed);
        final sw = Stopwatch()..start();
        await expectLater(future, throwsA(isA<TimeoutException>()));
        // Отсчёт пошёл С ВОЗВРАТА, а не выстрелил сразу просроченным.
        expect(sw.elapsed, greaterThanOrEqualTo(const Duration(milliseconds: 150)));
        await controller.close();
        witness.dispose();
      },
    );

    test(
      'AC:RL-video-viewer-save-and-overlay/14 — `inactive` (шторка) заморозкой '
      'НЕ считается: тишина дольше порога терминалит как обычно',
      () async {
        final witness = ForegroundWitness.manual(
          initial: AppLifecycleState.resumed,
        );
        final controller = StreamController<List<int>>();
        final future = readBytesWithIdleTimeout(
          controller.stream,
          idleTimeout: idle,
          witness: witness,
        );
        witness.onStateChange(AppLifecycleState.inactive);
        await expectLater(future, throwsA(isA<TimeoutException>()));
        await controller.close();
        witness.dispose();
      },
    );
  });

  group('retryOnceAfterSuspension', () {
    test(
      'AC:RL-video-viewer-save-and-overlay/15 — сетевой сбой в фоне → ровно один '
      'повтор, и только после возврата в foreground',
      () async {
        final witness = ForegroundWitness.manual(
          initial: AppLifecycleState.paused,
        );
        var calls = 0;
        final retried = <Object>[];
        final future = retryOnceAfterSuspension<int>(
          () async {
            calls++;
            if (calls == 1) throw const SocketException('reset by peer');
            return 42;
          },
          witness,
          onRetry: retried.add,
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(calls, 1, reason: 'в фоне повтор замёрз бы так же — ждём возврата');
        witness.onStateChange(AppLifecycleState.resumed);
        await expectLater(future, completion(42));
        expect(calls, 2);
        expect(retried, hasLength(1));
        witness.dispose();
      },
    );

    test(
      'AC:RL-video-viewer-save-and-overlay/15 — сбой в первые секунды после '
      'возврата (сокет пережил сон) тоже объясняется сном',
      () async {
        final witness = ForegroundWitness.manual(
          initial: AppLifecycleState.paused,
        );
        witness.onStateChange(AppLifecycleState.resumed);
        var calls = 0;
        final result = await retryOnceAfterSuspension<int>(() async {
          calls++;
          if (calls == 1) throw TimeoutException('media stream idle > 60s');
          return 7;
        }, witness);
        expect(result, 7);
        witness.dispose();
      },
    );

    test(
      'AC:RL-video-viewer-save-and-overlay/15 — ∀ НЕ-объяснимых сном случаев '
      'повтора НЕТ: сбой на глазах / HTTP-код / второй сбой / плеер закрыт / desktop',
      () async {
        Future<int> failing() async => throw const SocketException('reset');

        // На глазах у пользователя (resumed, grace давно прошёл).
        final foreground = ForegroundWitness.manual(
          initial: AppLifecycleState.resumed,
        );
        var calls = 0;
        await expectLater(
          retryOnceAfterSuspension<int>(() {
            calls++;
            return failing();
          }, foreground),
          throwsA(isA<SocketException>()),
        );
        expect(calls, 1);

        // Не транспорт (ответ сервера/данные) — даже в фоне без повтора.
        final bg = ForegroundWitness.manual(initial: AppLifecycleState.paused);
        calls = 0;
        await expectLater(
          retryOnceAfterSuspension<int>(() async {
            calls++;
            throw StateError('decrypt');
          }, bg),
          throwsA(isA<StateError>()),
        );
        expect(calls, 1);

        // Второй сбой — терминал, а не третья попытка.
        final justResumed = ForegroundWitness.manual(
          initial: AppLifecycleState.paused,
        )..onStateChange(AppLifecycleState.resumed);
        calls = 0;
        await expectLater(
          retryOnceAfterSuspension<int>(() {
            calls++;
            return failing();
          }, justResumed),
          throwsA(isA<SocketException>()),
        );
        expect(calls, 2);

        // Плеер закрыт — повтор не нужен.
        calls = 0;
        await expectLater(
          retryOnceAfterSuspension<int>(
            () {
              calls++;
              return failing();
            },
            bg,
            abandoned: () => true,
          ),
          throwsA(isA<SocketException>()),
        );
        expect(calls, 1);

        // Desktop: свидетеля нет — свёрнутое окно не замораживается.
        calls = 0;
        await expectLater(
          retryOnceAfterSuspension<int>(() {
            calls++;
            return failing();
          }, null),
          throwsA(isA<SocketException>()),
        );
        expect(calls, 1);

        for (final w in [foreground, bg, justResumed]) {
          w.dispose();
        }
      },
    );
  });

  test('dispose до возврата отпускает ожидающих без StateError', () async {
    final w = ForegroundWitness.manual(initial: AppLifecycleState.paused);
    final waiting = w.untilForeground();
    w.dispose();
    await expectLater(waiting, completes);
  });

  test(
    'AC:RL-video-viewer-save-and-overlay/14 — холодный старт (состояние ещё '
    'неизвестно) считается заморозкой, первое resumed снимает её',
    () async {
      final w = ForegroundWitness.manual();
      expect(w.suspended, isTrue, reason: 'процесс мог стартовать в фоне от пуша');
      w.onStateChange(AppLifecycleState.resumed);
      expect(w.suspended, isFalse);
      expect(w.failureExplainedBySuspension, isTrue, reason: 'grace после возврата');
      w.dispose();
    },
  );
}
