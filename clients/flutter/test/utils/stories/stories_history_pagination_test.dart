import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/stories/stories_extension.dart';

void main() {
  const cutoff = 1000000;
  const maxPages = 5;

  test('надо грузить: самое старое событие новее cutoff, есть история, cap не достигнут', () {
    expect(
      shouldRequestMoreStoryHistory(
        oldestLoadedTs: cutoff + 5000, // новее границы -> за ним могут быть активные
        cutoffTs: cutoff,
        canRequestHistory: true,
        pagesLoaded: 0,
        maxPages: maxPages,
      ),
      isTrue,
    );
  });

  test('стоп: дошли до события старше cutoff (активных за ним нет)', () {
    expect(
      shouldRequestMoreStoryHistory(
        oldestLoadedTs: cutoff - 1,
        cutoffTs: cutoff,
        canRequestHistory: true,
        pagesLoaded: 0,
        maxPages: maxPages,
      ),
      isFalse,
    );
  });

  test('стоп: упёрлись в начало комнаты (canRequestHistory=false)', () {
    expect(
      shouldRequestMoreStoryHistory(
        oldestLoadedTs: cutoff + 5000,
        cutoffTs: cutoff,
        canRequestHistory: false,
        pagesLoaded: 0,
        maxPages: maxPages,
      ),
      isFalse,
    );
  });

  test('стоп: достигнут cap maxPages', () {
    expect(
      shouldRequestMoreStoryHistory(
        oldestLoadedTs: cutoff + 5000,
        cutoffTs: cutoff,
        canRequestHistory: true,
        pagesLoaded: maxPages,
        maxPages: maxPages,
      ),
      isFalse,
    );
  });

  test('стоп: timeline пуст (oldestLoadedTs == null)', () {
    expect(
      shouldRequestMoreStoryHistory(
        oldestLoadedTs: null,
        cutoffTs: cutoff,
        canRequestHistory: true,
        pagesLoaded: 0,
        maxPages: maxPages,
      ),
      isFalse,
    );
  });

  test('граница: событие ровно на cutoff -> ещё грузим (>= cutoff)', () {
    expect(
      shouldRequestMoreStoryHistory(
        oldestLoadedTs: cutoff,
        cutoffTs: cutoff,
        canRequestHistory: true,
        pagesLoaded: 0,
        maxPages: maxPages,
      ),
      isTrue,
    );
  });
}
