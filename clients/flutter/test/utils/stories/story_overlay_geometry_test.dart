import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/stories/story_overlay_geometry.dart';

void main() {
  test(
    'mediaContainRect: широкая область, квадратное медиа → letterbox по бокам',
    () {
      final r = mediaContainRect(const Size(200, 100), 1.0); // медиа 1:1
      // высота области 100 → медиа 100x100, центрировано по ширине 200
      expect(r.height, 100);
      expect(r.width, 100);
      expect(r.left, 50);
      expect(r.top, 0);
    },
  );

  test(
    'fractionToLocal: центр медиа = центр прямоугольника медиа [ledger:RL-stories-overlay-anchor]',
    () {
      final media = const Rect.fromLTWH(50, 0, 100, 100);
      expect(fractionToLocal(0.5, 0.5, media), const Offset(100, 50));
    },
  );

  test('localToFraction обратно к fractionToLocal', () {
    final media = const Rect.fromLTWH(50, 0, 100, 100);
    final f = localToFraction(const Offset(100, 50), media);
    expect(f.dx, closeTo(0.5, 1e-9));
    expect(f.dy, closeTo(0.5, 1e-9));
  });

  test('localToFraction клампит за пределами области в [0..1]', () {
    final media = const Rect.fromLTWH(0, 0, 100, 100);
    final f = localToFraction(const Offset(-20, 200), media);
    expect(f.dx, 0.0);
    expect(f.dy, 1.0);
  });

  test(
    'mediaContainRect: узкая область, квадратное медиа → letterbox сверху/снизу',
    () {
      final r = mediaContainRect(const Size(100, 200), 1.0); // медиа 1:1
      // ширина области 100 → медиа 100x100, центрировано по высоте 200
      expect(r.width, 100);
      expect(r.height, 100);
      expect(r.left, 0);
      expect(r.top, 50);
    },
  );

  test('storyFrameRect: без maxAspect кадр = вся область (мобильный)', () {
    for (final area in const [
      Size(300, 800),
      Size(1000, 400),
      Size(412, 915),
    ]) {
      final r = storyFrameRect(area);
      expect(r.left, closeTo(0, 1e-9), reason: 'area=$area');
      expect(r.top, closeTo(0, 1e-9), reason: 'area=$area');
      expect(r.width, closeTo(area.width, 1e-9), reason: 'area=$area');
      expect(r.height, closeTo(area.height, 1e-9), reason: 'area=$area');
    }
  });

  test('storyFrameRect: вырожденная область → пустой кадр без краша', () {
    expect(storyFrameRect(const Size(0, 0)), const Rect.fromLTWH(0, 0, 0, 0));
    expect(storyFrameRect(const Size(100, 0)).height, 0);
    expect(
      storyFrameRect(const Size(0, 0), maxAspect: storyFrameAspect),
      const Rect.fromLTWH(0, 0, 0, 0),
    );
  });

  group('storyFrameRect: maxAspect (редактор на ПК) '
      '[ledger:RL-stories-create-all-platforms]', () {
    test('широкое окно → ширина под 9:16, кадр центрирован '
        '[AC:RL-stories-create-all-platforms/1]', () {
      // Окно 1600x900: высота кадра остаётся 900, ширина = 900*(9/16)=506.25,
      // центрирована → поля по бокам вместо растягивания на всю ширину.
      final r = storyFrameRect(
        const Size(1600, 900),
        maxAspect: storyFrameAspect,
      );
      const expectedW = 900 * storyFrameAspect;
      expect(r.height, closeTo(900, 1e-9));
      expect(r.width, closeTo(expectedW, 1e-9));
      expect(r.left, closeTo((1600 - expectedW) / 2, 1e-9));
      expect(r.top, closeTo(0, 1e-9));
      expect(r.width / r.height, closeTo(storyFrameAspect, 1e-9));
    });

    test('узкое окно (уже 9:16) → ширина остаётся полной, полей нет '
        '[AC:RL-stories-create-all-platforms/2]', () {
      // Телефон/узкое окно 400x900: ширина под 9:16 = 506 > 400 → ограничение
      // не срабатывает, поведение как раньше.
      final r = storyFrameRect(
        const Size(400, 900),
        maxAspect: storyFrameAspect,
      );
      expect(r.width, closeTo(400, 1e-9));
      expect(r.left, closeTo(0, 1e-9));
      expect(r.height, closeTo(900, 1e-9));
    });

    test('ровно 9:16 → границы совпадают, поля не появляются '
        '[AC:RL-stories-create-all-platforms/2]', () {
      final r = storyFrameRect(
        const Size(900 * storyFrameAspect, 900),
        maxAspect: storyFrameAspect,
      );
      expect(r.left, closeTo(0, 1e-9));
      expect(r.width, closeTo(900 * storyFrameAspect, 1e-9));
    });

    test('кадр редактора и вьюера имеют одинаковый аспект на широком окне '
        '[AC:RL-stories-create-all-platforms/3]', () {
      // Инвариант: то, что автор видит в редакторе, совпадает по пропорции с
      // тем, что увидит зритель — иначе оверлеи «поедут» между экранами.
      final editor = storyFrameRect(
        const Size(1600, 1000),
        maxAspect: storyFrameAspect,
      );
      final viewer = storyViewerMediaRect(
        const Size(1600, 1000),
        topInset: 0,
        bottomInset: 0,
        maxAspect: storyFrameAspect,
      );
      expect(
        editor.width / editor.height,
        closeTo(viewer.width / viewer.height, 1e-9),
      );
    });
  });

  test('storyViewerFrameRect: точный экран 9:16 → кадр на всю область', () {
    final r = storyViewerFrameRect(const Size(90, 160));
    expect(r.left, closeTo(0, 1e-9));
    expect(r.top, closeTo(0, 1e-9));
    expect(r.width, closeTo(90, 1e-9));
    expect(r.height, closeTo(160, 1e-9));
  });

  test('storyViewerFrameRect: экран выше 9:16 → поля сверху/снизу', () {
    // ширина 90 → кадр 90x160, центрирован по высоте 300
    final r = storyViewerFrameRect(const Size(90, 300));
    expect(r.width, closeTo(90, 1e-9));
    expect(r.height, closeTo(160, 1e-9));
    expect(r.left, closeTo(0, 1e-9));
    expect(r.top, closeTo(70, 1e-9)); // (300-160)/2
  });

  test('storyViewerFrameRect: всегда аспект ровно 9:16', () {
    for (final area in const [
      Size(300, 800),
      Size(1000, 400),
      Size(412, 915),
    ]) {
      final r = storyViewerFrameRect(area);
      expect(
        r.width / r.height,
        closeTo(storyFrameAspect, 1e-9),
        reason: 'area=$area',
      );
    }
  });

  group('storyViewerzones', () {
    test('делит область на три зоны: верх+медиа+низ = высота', () {
      final z = storyViewerZones(
        const Size(400, 900),
        topInset: 40,
        topPanelHeight: 60,
        bottomPanelHeight: 80,
      );
      expect(z.top.top, 0);
      expect(z.top.height, 100); // topInset + topPanelHeight
      expect(z.media.top, 100);
      expect(z.media.height, 720); // 900 - 100 - 80
      expect(z.bottom.top, 820);
      expect(z.bottom.height, 80);
      // все во всю ширину
      expect(z.top.width, 400);
      expect(z.media.width, 400);
      expect(z.bottom.width, 400);
    });

    test('крошечная область: медиа не уходит в отрицательную высоту', () {
      final z = storyViewerZones(
        const Size(400, 100),
        topInset: 40,
        topPanelHeight: 60,
        bottomPanelHeight: 80,
      );
      expect(z.media.height, greaterThanOrEqualTo(0));
      expect(z.media.width, 400);
    });
  });

  group('storyViewerMediaRect', () {
    test(
      'медиа почти на весь экран: от topInset до низа минус safe-area и зазор',
      () {
        final r = storyViewerMediaRect(
          const Size(400, 900),
          topInset: 44,
          bottomInset: 34,
        );
        expect(r.left, 0);
        expect(r.top, 44); // под статус-баром
        expect(r.width, 400); // во всю ширину
        // высота = 900 - 44 - 34 - storyViewerBottomGap(8)
        expect(r.height, 900 - 44 - 34 - storyViewerBottomGap);
        expect(r.bottom, 900 - 34 - storyViewerBottomGap); // зазор до safe-area
      },
    );

    test('без системных вырезов: медиа от 0 до высоты минус зазор', () {
      final r = storyViewerMediaRect(
        const Size(400, 800),
        topInset: 0,
        bottomInset: 0,
      );
      expect(r.top, 0);
      expect(r.height, 800 - storyViewerBottomGap);
    });

    test('bottomPanelHeight резервирует чёрную зону под медиа', () {
      final r = storyViewerMediaRect(
        const Size(400, 900),
        topInset: 44,
        bottomInset: 34,
        bottomPanelHeight: 64,
      );
      // медиа заканчивается выше на высоту панели: под ней остаётся зона
      expect(r.height, 900 - 44 - 34 - storyViewerBottomGap - 64);
      expect(r.bottom, 900 - 34 - storyViewerBottomGap - 64);
    });

    test('крошечная область: высота медиа не уходит в минус', () {
      final r = storyViewerMediaRect(
        const Size(400, 50),
        topInset: 44,
        bottomInset: 34,
      );
      expect(r.height, greaterThanOrEqualTo(0));
      expect(r.width, 400);
    });

    test(
      'maxAspect: широкая область (desktop) → ширина под 9:16, центрирована',
      () {
        // Широкое окно: высота медиа = 1000-0-0-8 = 992; ширина под 9:16 =
        // 992*(9/16)=558, центрирована в 1600.
        final r = storyViewerMediaRect(
          const Size(1600, 1000),
          topInset: 0,
          bottomInset: 0,
          maxAspect: storyFrameAspect,
        );
        final expectedH = 1000 - storyViewerBottomGap;
        final expectedW = expectedH * storyFrameAspect;
        expect(r.height, closeTo(expectedH, 1e-9));
        expect(r.width, closeTo(expectedW, 1e-9));
        expect(r.left, closeTo((1600 - expectedW) / 2, 1e-9));
        expect(r.width / r.height, closeTo(storyFrameAspect, 1e-9));
      },
    );

    test('maxAspect: узкий мобильный (уже 9:16) → ширина остаётся полной', () {
      // Телефон 400x900: высота медиа = 900-44-34-8 = 814; ширина под 9:16 =
      // 814*0.5625=458 > 400 → ограничение не срабатывает, ширина = 400.
      final r = storyViewerMediaRect(
        const Size(400, 900),
        topInset: 44,
        bottomInset: 34,
        maxAspect: storyFrameAspect,
      );
      expect(r.width, 400);
      expect(r.left, 0);
    });

    test('maxAspect: null → поведение как раньше (во всю ширину)', () {
      final r = storyViewerMediaRect(
        const Size(1600, 1000),
        topInset: 0,
        bottomInset: 0,
      );
      expect(r.width, 1600);
      expect(r.left, 0);
    });
  });

  // AC:RL-stories-media-transform/6 — clamp панорамы переднего плана.
  group('clampStoryTranslation', () {
    const frame = Size(360, 640);

    test('scale=1 → смещение заперто в (0,0) (панорамировать нечего)', () {
      // Квадрат в 9:16 — contain меньше рамки, перехлёста нет.
      final contain = mediaContainRect(frame, 1.0).size;
      final r = clampStoryTranslation(
        translation: const Offset(0.5, 0.5),
        scale: 1.0,
        containSize: contain,
        frameSize: frame,
      );
      expect(r.dx, 0.0);
      expect(r.dy, 0.0);
    });

    test(
      'scale=2, медиа 9:16 → смещение ограничено половиной перехлёста (0.5)',
      () {
        final contain = mediaContainRect(frame, storyFrameAspect).size;
        final r = clampStoryTranslation(
          translation: const Offset(10, 10),
          scale: 2.0,
          containSize: contain,
          frameSize: frame,
        );
        expect(r.dx, closeTo(0.5, 0.0001));
        expect(r.dy, closeTo(0.5, 0.0001));
      },
    );

    test('значение в пределах диапазона не меняется', () {
      final contain = mediaContainRect(frame, storyFrameAspect).size;
      final r = clampStoryTranslation(
        translation: const Offset(0.1, -0.2),
        scale: 2.0,
        containSize: contain,
        frameSize: frame,
      );
      expect(r.dx, closeTo(0.1, 0.0001));
      expect(r.dy, closeTo(-0.2, 0.0001));
    });

    test('нулевая рамка → нулевое смещение (без краша)', () {
      final r = clampStoryTranslation(
        translation: const Offset(0.3, 0.3),
        scale: 2.0,
        containSize: const Size(100, 100),
        frameSize: Size.zero,
      );
      expect(r, Offset.zero);
    });
  });
}
