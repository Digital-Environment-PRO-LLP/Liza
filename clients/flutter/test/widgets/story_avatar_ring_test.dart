import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liza/widgets/story_avatar_ring.dart';

void main() {
  Widget wrap(Widget child) =>
      MaterialApp(home: Scaffold(body: Center(child: child)));

  testWidgets('none: кольца нет, child виден', (tester) async {
    await tester.pumpWidget(
      wrap(const StoryAvatarRing(
        state: StoryRingState.none,
        child: Text('AV'),
      )),
    );
    expect(find.text('AV'), findsOneWidget);
    final ring = tester.widget<StoryAvatarRing>(find.byType(StoryAvatarRing));
    expect(ring.state, StoryRingState.none);
  });

  testWidgets('unseen: рендерится без ошибок', (tester) async {
    await tester.pumpWidget(
      wrap(const StoryAvatarRing(
        state: StoryRingState.unseen,
        child: Text('AV'),
      )),
    );
    expect(find.text('AV'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('seen: рендерится без ошибок', (tester) async {
    await tester.pumpWidget(
      wrap(const StoryAvatarRing(
        state: StoryRingState.seen,
        child: Text('AV'),
      )),
    );
    expect(tester.takeException(), isNull);
  });
}
