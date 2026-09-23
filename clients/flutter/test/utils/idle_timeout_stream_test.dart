import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/idle_timeout_stream.dart';

// Скачивание медиа терминалится по ОТСУТСТВИЮ ПРОГРЕССА, а не по стенным часам.
//
// Зачем страж: у видео-скачивания не было таймаута вовсе, и «тлеющее»
// соединение (сокет жив, байты не идут) превращалось в вечный спиннер без
// кнопки. Лечится таймаутом — но НЕ общим: 161-МБ видео на слабом канале
// качается минутами, и wall-clock бюджет зарубил бы живую загрузку. Проект уже
// откатывал такой фикс (watchdog по `pos<500ms` рубил медленный, но живой
// стрим), а `RL-e2ee-video-proxy-resume` прямо требует считать ПРОГРЕСС.
// Поэтому здесь проверяется именно РАЗЛИЧЕНИЕ «медленно» и «мертво».
//
// Пороги взяты миллисекундные, а не минутные: свойство, которое сторожим —
// «счётчик сбрасывается на каждом чанке», и оно от масштаба не зависит. Ключевой
// кейс — суммарное время загрузки МНОГОКРАТНО превышает порог, но паузы между
// чанками короче него. FakeAsync здесь не годится: таймер `Stream.timeout`
// живёт в зоне подписки и под ним не срабатывает (проверено).
//
// ledger:RL-video-viewer-save-and-overlay
void main() {
  const idle = Duration(milliseconds: 200);

  group('readBytesWithIdleTimeout', () {
    test(
      'AC:RL-video-viewer-save-and-overlay/11 — ровный поток: ошибки нет, байты склеены',
      () async {
        final bytes = await readBytesWithIdleTimeout(
          Stream.fromIterable([
            [1, 2, 3],
            [4, 5],
            [6],
          ]),
          idleTimeout: idle,
        );
        expect(bytes, [1, 2, 3, 4, 5, 6]);
      },
    );

    test(
      'AC:RL-video-viewer-save-and-overlay/11 — МЕДЛЕННО не таймаутит: суммарно вчетверо '
      'дольше порога, но паузы между чанками короче — это idle-порог, а не бюджет загрузки',
      () async {
        // 10 чанков × 80 мс = 800 мс суммарно при пороге 200 мс. Именно так
        // выглядит честная докачка большого файла на слабом канале.
        final slow = Stream<List<int>>.periodic(
          const Duration(milliseconds: 80),
          (i) => [i],
        ).take(10);

        final bytes = await readBytesWithIdleTimeout(slow, idleTimeout: idle);

        expect(
          bytes,
          hasLength(10),
          reason: 'докачка идёт — рубить нельзя, иначе рецидив «резали живой '
              'медленный стрим»',
        );
      },
    );

    test(
      'AC:RL-video-viewer-save-and-overlay/11 — МЁРТВО (тишина дольше порога) → TimeoutException',
      () async {
        final controller = StreamController<List<int>>();
        final future = readBytesWithIdleTimeout(
          controller.stream,
          idleTimeout: idle,
        );
        controller.add([1, 2, 3]);
        // Байты кончились, сокет жив и не закрыт — ровно тот случай, что давал
        // вечный спиннер без кнопки.
        await expectLater(
          future,
          throwsA(isA<TimeoutException>()),
          reason: 'без терминала здесь остаётся спиннер без кнопки — навсегда',
        );
        await controller.close();
      },
    );

    test(
      'AC:RL-video-viewer-save-and-overlay/11 — байт ПЕРЕД самым порогом сбрасывает счётчик',
      () async {
        final controller = StreamController<List<int>>();
        final future = readBytesWithIdleTimeout(
          controller.stream,
          idleTimeout: idle,
        );

        await Future<void>.delayed(const Duration(milliseconds: 150));
        controller.add([7]); // прогресс за 50 мс до порога
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await controller.close();

        // Суммарно прошло 300 мс > 200 мс порога, но каждая пауза короче него.
        await expectLater(future, completion(hasLength(1)));
      },
    );

    test(
      'onChunk отдаёт НАКОПЛЕННОЕ число байт (для индикатора прогресса)',
      () async {
        final progress = <int>[];
        await readBytesWithIdleTimeout(
          Stream.fromIterable([
            [1, 2, 3],
            [4, 5],
            [6],
          ]),
          idleTimeout: idle,
          onChunk: progress.add,
        );
        expect(progress, [3, 5, 6]);
      },
    );
  });
}
