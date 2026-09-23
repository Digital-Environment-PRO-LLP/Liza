// Host-страж grace-капа сетки альбома (защита от ВЕЧНЫХ фантом-спиннеров от
// битого форварда галереи). Чистая функция `galleryExpectedCount` (рендер
// `GalleryBubble` — device smoke `gallery_forward_flow_test.dart`).
//
// Корень: старый форвард копировал только якорь с исходным `n` (напр. 3), а
// соседей не слал → у получателя `expectedCount` рисовал `n` ячеек при 1 члене
// → `n-1` вечных `CircularProgressIndicator`. Grace-кап по возрасту якоря
// (`originServerTs`) отличает «соседи ещё едут» (свежий) от «их не будет»
// (легаси-форвард, старый).
//
// ledger:RL-gallery-count-cap-defensive

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat/events/gallery.dart';

void main() {
  const freshMs = 1000; // якорь свежий (в пределах grace)
  final staleMs = galleryGraceMs + 5000; // старше grace

  group('galleryExpectedCount', () {
    test(
      'AC:RL-gallery-count-cap-defensive/1 — легаси битый форвард (n=3, '
      'members=1, старый якорь) → факт 1, НЕ 3 (0 фантомов)',
      () {
        expect(
          galleryExpectedCount(
            membersLen: 1,
            n: 3,
            hasRedacted: false,
            anchorAgeMs: staleMs,
          ),
          1,
          reason: 'старый якорь → показываем факт, вечных фантомов нет',
        );
      },
    );

    test(
      'AC:RL-gallery-count-cap-defensive/2 — свежий грузящийся альбом (n=3, '
      'members=1, свежий якорь) → держим 3 (спиннеры соседей штатны)',
      () {
        expect(
          galleryExpectedCount(
            membersLen: 1,
            n: 3,
            hasRedacted: false,
            anchorAgeMs: freshMs,
          ),
          3,
          reason: 'свежий якорь → соседи ещё едут по /sync, держим спиннеры',
        );
      },
    );

    test(
      'AC:RL-gallery-count-cap-defensive/3 — граница grace: чуть до порога '
      'держит n, чуть после — факт',
      () {
        expect(
          galleryExpectedCount(
            membersLen: 2,
            n: 5,
            hasRedacted: false,
            anchorAgeMs: galleryGraceMs - 1,
          ),
          5,
        );
        expect(
          galleryExpectedCount(
            membersLen: 2,
            n: 5,
            hasRedacted: false,
            anchorAgeMs: galleryGraceMs + 1,
          ),
          2,
        );
      },
    );

    test(
      'AC:RL-gallery-count-cap-defensive/4 — redaction-ветка не сломана: '
      'hasRedacted → факт независимо от возраста',
      () {
        expect(
          galleryExpectedCount(
            membersLen: 4,
            n: 5,
            hasRedacted: true,
            anchorAgeMs: freshMs, // даже свежий
          ),
          4,
          reason: 'после удаления члена показываем факт, не заявленное n',
        );
      },
    );

    test(
      'AC:RL-gallery-count-cap-defensive/3 — полный альбом (members==n) → '
      'n, без фантомов, независимо от возраста',
      () {
        expect(
          galleryExpectedCount(
            membersLen: 3,
            n: 3,
            hasRedacted: false,
            anchorAgeMs: freshMs,
          ),
          3,
        );
        expect(
          galleryExpectedCount(
            membersLen: 3,
            n: 3,
            hasRedacted: false,
            anchorAgeMs: staleMs,
          ),
          3,
        );
      },
    );

    test(
      'AC:RL-gallery-count-cap-defensive/1 — n отсутствует (обычная группа) '
      '→ факт',
      () {
        expect(
          galleryExpectedCount(
            membersLen: 2,
            n: null,
            hasRedacted: false,
            anchorAgeMs: freshMs,
          ),
          2,
        );
      },
    );
  });
}
