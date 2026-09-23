import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/widgets/avatar.dart';
import 'package:liza/widgets/story_avatar_ring.dart';

// Спек 2026-07-30 §1.2: истории открываются ТОЛЬКО тапом по аватарке.
// Раньше вся строка участника вела в истории, и контекстное меню (выдать
// права) было недостижимо для пользователя с активной историей.
//
// Avatar в этом тесте смонтирован без предка MatrixState (Provider), поэтому
// MxcImage._load бросает исключение при первом же обращении к Matrix.of(context)
// и планирует retry-таймер экспоненциального backoff (2/4/8/16/30с, 5 попыток).
// pumpAndSettle падает на "A Timer is still pending" — драним все 5 таймеров
// явно, чтобы виджет корректно завершил жизненный цикл к концу теста.
Future<void> _drainMxcImageRetryTimers(WidgetTester tester) async {
  for (final delay in const [
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 9),
    Duration(seconds: 17),
    Duration(seconds: 31),
  ]) {
    await tester.pump(delay);
  }
}

void main() {
  testWidgets('при активном кольце тап по аватарке идёт в истории, '
      'а не в общий onTap', (tester) async {
    var storyTaps = 0;
    var avatarTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Avatar(
            name: 'Тест',
            storyRing: StoryRingState.unseen,
            onStoryTap: () => storyTaps++,
            onTap: () => avatarTaps++,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Avatar));
    await tester.pump();

    expect(storyTaps, 1, reason: 'аватарка с кольцом обязана вести в истории');
    expect(avatarTaps, 0);

    await _drainMxcImageRetryTimers(tester);
  });

  testWidgets('без кольца тап по аватарке идёт в обычный onTap',
      (tester) async {
    var storyTaps = 0;
    var avatarTaps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Avatar(
            name: 'Тест',
            storyRing: StoryRingState.none,
            onStoryTap: () => storyTaps++,
            onTap: () => avatarTaps++,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Avatar));
    await tester.pump();

    expect(storyTaps, 0);
    expect(avatarTaps, 1);

    await _drainMxcImageRetryTimers(tester);
  });
}
