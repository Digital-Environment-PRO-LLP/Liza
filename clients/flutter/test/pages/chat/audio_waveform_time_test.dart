import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat/events/audio_player.dart';

// Страж реестра регрессии: ledger:RL-audio-waveform-time (см. tests/registry/).
//
// Инвариант: осциллограмма голосового ([AudioWaveform]) должна отрисовываться
// даже в УЗКОМ пузыре, когда в ряд контролов встроено inline-время
// (RL-message-time). Баг был на iOS: 40 столбиков с margin 1px + padding 16px
// давали ~112px несжимаемого минимума; время отъедало ширину у `Expanded`
// осциллограммы → каждый столбик получал слот уже своего margin и схлопывался в
// НУЛЕВУЮ ширину (RenderFlex НЕ бросает исключение — margin просто «съедает»
// слот, столбики тихо исчезают, остаётся точка-ползунок Slider). На широком
// macOS места хватало, потому и рисовалось.
//
// Рендерим РЕАЛЬНЫЙ виджет [AudioWaveform] (примитивы вместо Event → без
// Matrix Client, который вешает пул в testWidgets).

// Узкая ширина области осциллограммы, при которой СТАРЫЕ параметры
// (padding 16 / margin 1, минимум ~112px) схлопывают столбики в 0, а НОВЫЕ
// (padding 4 / margin 0.5, минимум ~48px) — оставляют видимыми.
const double _narrow = 100.0;

// Осциллограмма из 40 отсчётов (как в реальном событии).
final List<int> _waveform = List<int>.generate(
  AudioPlayerWidget.wavesCount,
  (i) => 200 + (i % 5) * 160,
);

// Ширина ЗАКРАШЕННОГО столбика = слот `Expanded` минус его margin. Именно она
// уходит в 0 при регрессе (margin «съедает» слот). Container с decoration
// строит внутри себя `DecoratedBox` РАЗМЕРОМ уже margin — его и мерим (размер
// самого Container включал бы margin и всегда был бы > 0).
double _minBarWidth(WidgetTester tester, Finder scope) {
  final bars = find.descendant(of: scope, matching: find.byType(DecoratedBox));
  expect(
    tester.widgetList(bars).length,
    AudioPlayerWidget.wavesCount,
    reason: 'должны присутствовать все ${AudioPlayerWidget.wavesCount} столбиков',
  );
  var min = double.infinity;
  for (final e in bars.evaluate()) {
    final w = (e.renderObject as RenderBox).size.width;
    if (w < min) min = w;
  }
  return min;
}

void main() {
  testWidgets(
    'осциллограмма видима в узком пузыре рядом со временем — ledger:RL-audio-waveform-time',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: _narrow,
                child: AudioWaveform(
                  waveform: _waveform,
                  color: const Color(0xFF444444),
                  wavePosition: 10,
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      // Столбики НЕ схлопнулись: каждый шире нуля.
      expect(
        _minBarWidth(tester, find.byType(AudioWaveform)),
        greaterThan(0.0),
        reason: 'при новых отступах столбики остаются видимыми в узком пузыре',
      );
    },
  );

  // Доказательство, что страж ЛОВИТ регресс: та же раскладка со СТАРЫМИ
  // параметрами (padding 16 / margin 1) на той же узкой ширине схлопывает
  // столбики в НОЛЬ. Возврат старых отступов в [AudioWaveform] уронит тест выше.
  testWidgets('контроль: старые отступы (padding16/margin1) схлопывают столбики в 0', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: _narrow,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    for (var i = 0; i < AudioPlayerWidget.wavesCount; i++)
                      Expanded(
                        child: Container(
                          height: 32,
                          alignment: Alignment.center,
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: const BoxDecoration(
                              color: Color(0xFF444444),
                            ),
                            height: 20,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      _minBarWidth(tester, find.byType(Row)),
      0.0,
      reason:
          'старая вёрстка ДОЛЖНА схлопывать столбики в 0 на узкой ширине — это и '
          'есть баг, который чинит уменьшение отступов',
    );
  });
}
