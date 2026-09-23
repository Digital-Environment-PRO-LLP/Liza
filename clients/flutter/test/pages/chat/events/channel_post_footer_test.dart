import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/channel_post_comments.dart';
import 'package:liza/pages/chat/events/message.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('ru'),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('ChannelPostCommentsBar', () {
    testWidgets('без комментариев зовёт «Прокомментировать»', (tester) async {
      await tester.pumpWidget(
        _wrap(ChannelPostCommentsBar(count: 0, onTap: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('Прокомментировать'), findsOneWidget);
      expect(find.text('Оставить комментарий'), findsNothing);
    });

    testWidgets('с комментариями показывает их число', (tester) async {
      await tester.pumpWidget(
        _wrap(ChannelPostCommentsBar(count: 3, onTap: () {})),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 комментария'), findsOneWidget);
    });

    testWidgets('тап по строке срабатывает', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(
        _wrap(ChannelPostCommentsBar(count: 0, onTap: () => tapped++)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ChannelPostCommentsBar));
      expect(tapped, 1);
    });
  });

  group('ChannelPostStatsRow', () {
    testWidgets('без реакций строка остаётся: просмотры и время справа', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ChannelPostStatsRow(
            reactionChips: null,
            viewCount: 4464,
            time: '15:59',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('15:59'), findsOneWidget);
      expect(find.textContaining('4464'), findsOneWidget);
    });

    testWidgets('нулевые просмотры не рисуют счётчик, время остаётся', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const ChannelPostStatsRow(
            reactionChips: null,
            viewCount: 0,
            time: '15:59',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('15:59'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    });
  });
}
