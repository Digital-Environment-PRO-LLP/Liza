// ledger:RL-channel-reactions-flow
// AC:RL-channel-reactions-flow/1
// guard.render:real-widget
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/events/message.dart';

Widget _wrap(Widget child) => MaterialApp(
  locale: const Locale('ru'),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  home: Scaffold(body: child),
);

/// Чипы-заглушки фиксированного размера: геометрию проверяем на реальном
/// `ChannelPostStatsRow`, а размер реакции не должен зависеть от шрифта.
List<Widget> _fakeChips(int count) => List.generate(
  count,
  (i) => Container(
    key: ValueKey('reaction_$i'),
    width: 56,
    height: 28,
    color: const Color(0xFF335577),
  ),
);

void main() {
  group('полоса реакций поста канала', () {
    for (final n in [1, 3, 7, 12]) {
      testWidgets('$n реакций: счётчик в последней строке, без наложения', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _wrap(
            Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 300,
                child: ChannelPostStatsRow(
                  reactionChips: _fakeChips(n),
                  viewCount: 6,
                  time: '12:16',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final timeRect = tester.getRect(find.text('12:16'));
        final lastReaction = tester.getRect(
          find.byKey(ValueKey('reaction_${n - 1}')),
        );

        // Счётчик и время стоят В ПОТОКЕ реакций: их левый край правее
        // последней реакции ИЛИ они ниже её (перенеслись на новую строку).
        final flowsAround =
            timeRect.left >= lastReaction.right - 0.5 ||
            timeRect.top >= lastReaction.bottom - 0.5;
        expect(
          flowsAround,
          isTrue,
          reason:
              'при $n реакциях время наложилось на реакцию: '
              'time=$timeRect, reaction=$lastReaction',
        );

        // Реакции занимают ширину поста, а не жмутся в узкую колонку слева.
        final firstReaction = tester.getRect(
          find.byKey(const ValueKey('reaction_0')),
        );
        expect(firstReaction.left, lessThan(40));

        // Полоса разложена по всей ширине: при 7+ чипах ширина 300 вмещает
        // по 4-5 в строку, значит правый край самого правого чипа заметно
        // дальше ширины одного чипа — столбика нет.
        if (n >= 3) {
          final maxRight = List.generate(
            n,
            (i) => tester.getRect(find.byKey(ValueKey('reaction_$i'))).right,
          ).reduce((a, b) => a > b ? a : b);
          expect(
            maxRight - firstReaction.left,
            greaterThan(120),
            reason: 'при $n реакциях полоса схлопнулась в столбик',
          );
        }
      });
    }

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
  });
}
