import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/stories/story_model.dart';

void main() {
  group('StoryOverlay.fromJson', () {
    test('парсит текст с координатами', () {
      final o = StoryOverlay.fromJson({'text': 'Привет', 'x': 0.3, 'y': 0.5});
      expect(o, isNotNull);
      expect(o!.text, 'Привет');
      expect(o.x, 0.3);
      expect(o.y, 0.5);
    });

    test('null, если нет текста', () {
      expect(StoryOverlay.fromJson({'x': 0.1, 'y': 0.2}), isNull);
    });

    test('round-trip toJson -> fromJson', () {
      const o = StoryOverlay(text: 'A', x: 0.4, y: 0.6);
      final back = StoryOverlay.fromJson(o.toJson());
      expect(back!.text, o.text);
      expect(back.x, closeTo(o.x, 0.0001));
      expect(back.y, closeTo(o.y, 0.0001));
    });

    test('toJson пишет x/y как int (Matrix запрещает float в content)', () {
      const o = StoryOverlay(text: 'A', x: 0.4, y: 0.6);
      final json = o.toJson();
      expect(json['x'], isA<int>());
      expect(json['y'], isA<int>());
      // Промилле 0-10000: 0.4 -> 4000, 0.6 -> 6000.
      expect(json['x'], 4000);
      expect(json['y'], 6000);
    });

    test('fromJson читает старый float-формат (обратная совместимость)', () {
      final o = StoryOverlay.fromJson({'text': 'A', 'x': 0.3, 'y': 0.7});
      expect(o!.x, closeTo(0.3, 0.0001));
      expect(o.y, closeTo(0.7, 0.0001));
    });
  });

  group('StoryContent.fromContent', () {
    test('парсит из event.content по ключу com.liza.story', () {
      final content = <String, Object?>{
        'msgtype': 'm.image',
        storyContentKey: {
          'expires_ts': 1750700000000,
          'overlays': [
            {'text': 'Hi', 'x': 0.5, 'y': 0.5},
          ],
        },
      };
      final story = StoryContent.fromContent(content);
      expect(story, isNotNull);
      expect(story!.expiresTs, 1750700000000);
      expect(story.overlays, hasLength(1));
      expect(story.overlays.first.text, 'Hi');
    });

    test('null, если ключа com.liza.story нет (обычное m.image)', () {
      expect(StoryContent.fromContent({'msgtype': 'm.image'}), isNull);
    });

    test('пустой overlays, если ключ overlays отсутствует', () {
      final story = StoryContent.fromContent({
        storyContentKey: {'expires_ts': 1},
      });
      expect(story!.overlays, isEmpty);
    });

    test('игнорирует невалидные элементы overlays без краша', () {
      final story = StoryContent.fromContent({
        storyContentKey: {
          'expires_ts': 1,
          'overlays': [
            'строка-мусор',
            {'text': 'ok', 'x': 0.1, 'y': 0.2},
          ],
        },
      });
      expect(story!.overlays, hasLength(1));
      expect(story.overlays.first.text, 'ok');
    });
  });

  group('storyIsActive', () {
    test('активен, если expires_ts в будущем', () {
      const s = StoryContent(expiresTs: 2000, overlays: []);
      expect(storyIsActive(s, 1000), isTrue);
    });

    test('протух, если expires_ts в прошлом', () {
      const s = StoryContent(expiresTs: 1000, overlays: []);
      expect(storyIsActive(s, 2000), isFalse);
    });
  });

  group('StoryContent с caption', () {
    test(
      'StoryContent round-trip с caption [ledger:RL-stories-caption-links]',
      () {
        final c = StoryContent(
          expiresTs: 1000,
          caption: 'Привет https://example.com',
          overlays: const [StoryOverlay(text: 'T', x: 0.3, y: 0.5)],
        );
        final json = c.toJson();
        expect(json['caption'], 'Привет https://example.com');
        final back = StoryContent.fromContent({'com.liza.story': json})!;
        expect(back.caption, 'Привет https://example.com');
        expect(back.overlays.single.text, 'T');
      },
    );

    test('пустой/отсутствующий caption не сериализуется', () {
      final c = StoryContent(expiresTs: 1000, overlays: const []);
      expect(c.toJson().containsKey('caption'), isFalse);
    });

    test('пустая строка caption не сериализуется', () {
      expect(
        StoryContent(
          expiresTs: 1000,
          overlays: const [],
          caption: '',
        ).toJson().containsKey('caption'),
        isFalse,
      );
    });

    test('fromJson игнорирует старое поле link, не падает', () {
      final o = StoryOverlay.fromJson({
        'text': 'X',
        'x': 5000,
        'y': 5000,
        'link': 'https://old',
      });
      expect(o, isNotNull);
      expect(o!.text, 'X');
    });
  });

  group('StoryMedia (трансформ + фон)', () {
    // AC:RL-stories-media-transform/2 — round-trip промилле-int без потерь.
    test('round-trip scale/dx/dy через промилле-int', () {
      const m = StoryMedia(
        background: StoryMediaBackground.blur,
        scale: 1.5,
        dx: -0.03,
        dy: 0.08,
      );
      final json = m.toJson();
      // Matrix запрещает float в content — всё целое.
      expect(json['scale'], isA<int>());
      expect(json['dx'], isA<int>());
      expect(json['dy'], isA<int>());
      expect(json['bg'], 'blur');
      final back = StoryMedia.fromJson(json)!;
      expect(back.scale, closeTo(1.5, 0.0001));
      expect(back.dx, closeTo(-0.03, 0.0001));
      expect(back.dy, closeTo(0.08, 0.0001));
      expect(back.background, StoryMediaBackground.blur);
    });

    // AC:RL-stories-media-transform/3 — отсутствие media → cover (легаси).
    test('отсутствие media в content → null (легаси-рендер cover)', () {
      final story = StoryContent.fromContent({
        storyContentKey: {'expires_ts': 1, 'overlays': <Object>[]},
      });
      expect(story, isNotNull);
      expect(story!.media, isNull);
    });

    test('media без bg=blur (или "cover") → фон cover', () {
      final m = StoryMedia.fromJson({'bg': 'cover', 'scale': 2000})!;
      expect(m.background, StoryMediaBackground.cover);
      expect(m.scale, closeTo(2.0, 0.0001));
    });

    test('дефолт scale=1 при отсутствии полей', () {
      final m = StoryMedia.fromJson({'bg': 'blur'})!;
      expect(m.scale, 1.0);
      expect(m.dx, 0.0);
      expect(m.dy, 0.0);
    });

    test('back-compat: старый float scale/offset читается', () {
      final m = StoryMedia.fromJson({'bg': 'blur', 'scale': 1.5, 'dx': 0.1})!;
      expect(m.scale, closeTo(1.5, 0.0001));
      expect(m.dx, closeTo(0.1, 0.0001));
    });

    test('StoryContent round-trip с media и trim', () {
      final c = StoryContent(
        expiresTs: 1000,
        overlays: const [],
        media: const StoryMedia(
          background: StoryMediaBackground.blur,
          scale: 2.0,
          dx: 0.05,
          dy: -0.05,
          trim: StoryTrim(startMs: 15000, endMs: 75000),
        ),
      );
      final back = StoryContent.fromContent({storyContentKey: c.toJson()})!;
      expect(back.media, isNotNull);
      expect(back.media!.scale, closeTo(2.0, 0.0001));
      expect(back.media!.trim!.startMs, 15000);
      expect(back.media!.trim!.endMs, 75000);
    });

    test('media без trim не сериализует trim', () {
      const c = StoryContent(
        expiresTs: 1,
        overlays: [],
        media: StoryMedia(scale: 1.0),
      );
      final mediaJson = c.toJson()['media'] as Map<String, Object?>;
      expect(mediaJson.containsKey('trim'), isFalse);
    });
  });
}
