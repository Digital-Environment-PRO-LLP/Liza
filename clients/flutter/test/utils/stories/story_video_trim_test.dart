import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/stories/story_video_trim.dart';

// ledger:RL-stories-video-trim-window
void main() {
  group('planTrim (окно с начала)', () {
    test('видео короче минуты — не режем', () {
      final p = planTrim(12000);
      expect(p.needsTrim, isFalse);
      expect(p.startMs, 0);
      expect(p.endMs, 12000);
    });

    test('видео ровно 60с — не режем', () {
      final p = planTrim(storyMaxVideoMs);
      expect(p.needsTrim, isFalse);
      expect(p.endMs, storyMaxVideoMs);
    });

    test('видео длиннее минуты — берём первую минуту', () {
      final p = planTrim(95000);
      expect(p.needsTrim, isTrue);
      expect(p.startMs, 0);
      expect(p.endMs, 60000);
    });
  });

  // AC:RL-stories-video-trim-window/7
  group('planTrimWindow (выбранный дорожкой отрезок, startMs>0)', () {
    test('59с целиком, старт 0 — без обрезки', () {
      final p = planTrimWindow(59000, startMs: 0);
      expect(p.needsTrim, isFalse);
      expect(p.endMs, 59000);
    });

    test('61с, старт 0 — окно ровно 60с', () {
      final p = planTrimWindow(61000, startMs: 0);
      expect(p.needsTrim, isTrue);
      expect(p.startMs, 0);
      expect(p.endMs, 60000);
    });

    test('180с, старт в середине — окно 60с от выбранного места', () {
      final p = planTrimWindow(180000, startMs: 45000);
      expect(p.needsTrim, isTrue);
      expect(p.startMs, 45000);
      expect(p.endMs, 105000);
    });

    test('старт у самого конца — окно прижимается к концу видео', () {
      // durationMs=100000, окно 60с → максимальный старт = 40000.
      final p = planTrimWindow(100000, startMs: 90000);
      expect(p.startMs, 40000);
      expect(p.endMs, 100000);
      expect(p.endMs - p.startMs, 60000);
    });

    test('старт вылезает за конец на коротком видео — окно к концу', () {
      // durationMs=70000: maxStart=10000, окно 60с.
      final p = planTrimWindow(70000, startMs: 999999);
      expect(p.startMs, 10000);
      expect(p.endMs, 70000);
    });

    test('отрицательный старт клампится к нулю', () {
      final p = planTrimWindow(120000, startMs: -5000);
      expect(p.startMs, 0);
      expect(p.endMs, 60000);
    });

    test('нулевая длительность — без обрезки', () {
      final p = planTrimWindow(0, startMs: 0);
      expect(p.needsTrim, isFalse);
      expect(p.endMs, 0);
    });
  });
}
