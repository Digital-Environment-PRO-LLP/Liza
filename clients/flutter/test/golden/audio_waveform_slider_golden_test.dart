import 'package:flutter/material.dart';

import 'package:alchemist/alchemist.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat/events/audio_player.dart';

// Страж реестра регрессии: ledger:RL-audio-waveform-time (см. tests/registry/).
//
// Golden Яруса A + структурный ассерт на РЕАЛЬНЫЙ виджет [AudioWaveformSlider]
// (осциллограмма + выровненный ползунок). Закрывает дыру, доказанную комиссией
// 2026-07-28: возврат «плашки» от начала дорожки (убрать `padding: zero` из
// SliderTheme) НЕ ловился ни одним тестом — `audio_waveform_time_test.dart`
// мерит только ширину столбиков, golden `message_time` рендерит другой виджет.
//
// Инвариант: при value=0 thumb стоит в НАЧАЛЕ дорожки (совпадает с левым краем
// осциллограммы); при проигрывании едет по границе закраски. Держится на
// `SliderTheme(padding: zero, overlayShape: noOverlay)` + общий с осциллограммой
// горизонтальный padding. Golden ловит сдвиг пиксельно; структурный ассерт ниже
// ловит удаление именно этих параметров детерминированно (без пиксель-диффа).

final List<int> _waveform = List<int>.generate(
  AudioPlayerWidget.wavesCount,
  (i) => 120 + ((i * 37) % 5) * 180,
);

// Material Slider держит value-indicator через OverlayPortal → требует Overlay в
// дереве. Alchemist-хост его не даёт (в отличие от MaterialApp в
// testWidgets-ассерте ниже), поэтому в golden-сценарии подставляем минимальный
// ограниченный Overlay.
Widget _bar({required double value, required double wavePosition}) => SizedBox(
  width: 220,
  height: 40,
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => AudioWaveformSlider(
            waveform: _waveform,
            color: const Color(0xFF444444),
            thumbColor: const Color(0xFF000000),
            wavePosition: wavePosition,
            value: value,
            max: AudioPlayerWidget.wavesCount.toDouble(),
            onChanged: (_) {},
          ),
        ),
      ],
    ),
  ),
);

void main() {
  goldenTest(
    'ползунок голосового: в начале при value=0 vs по центру закраски при проигрывании',
    fileName: 'audio_waveform_slider',
    builder: () => GoldenTestGroup(
      columns: 1,
      children: [
        GoldenTestScenario(
          name: 'value=0 — thumb в начале дорожки',
          child: _bar(value: 0, wavePosition: 0),
        ),
        GoldenTestScenario(
          name: 'проигрывание ~40% — thumb по центру закраски',
          child: _bar(value: 16, wavePosition: 16),
        ),
      ],
    ),
  );

  // Структурный страж (детерминированный, без пикселей): РЕАЛЬНЫЙ
  // AudioWaveformSlider обязан держать `SliderTheme(padding: zero, overlayShape:
  // noOverlay)`. Убери `padding: EdgeInsets.zero` — thumb уедет от начала (та
  // самая жалоба), и ЭТОТ ассерт упадёт (в отличие от прежних тестов, которые
  // оставались зелёными — доказано состязательным прогоном 2026-07-28).
  testWidgets(
    'AudioWaveformSlider: SliderTheme padding=zero + noOverlay — ledger:RL-audio-waveform-time',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: _bar(value: 0, wavePosition: 0)),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      final sliderThemeFinder = find
          .ancestor(
            of: find.byType(Slider),
            matching: find.byType(SliderTheme),
          )
          .first;
      final sliderTheme = tester.widget<SliderTheme>(sliderThemeFinder);
      expect(
        sliderTheme.data.padding,
        EdgeInsets.zero,
        reason:
            'padding=zero держит ползунок у начала дорожки; дефолтный инсет '
            'Material сдвигает «плашку» вправо (баг «частично проиграно»)',
      );
      expect(
        sliderTheme.data.overlayShape,
        SliderComponentShape.noOverlay,
        reason: 'noOverlay убирает splash-инсет, тоже смещающий thumb',
      );

      // Slider обёрнут в тот же горизонтальный padding, что и осциллограмма —
      // иначе дорожка и столбики не совпадают по рабочей ширине.
      final padFinder = find
          .ancestor(of: find.byType(Slider), matching: find.byType(Padding))
          .first;
      final pad = tester.widget<Padding>(padFinder);
      expect(
        pad.padding,
        const EdgeInsets.symmetric(
          horizontal: AudioWaveform.horizontalPadding,
        ),
      );
    },
  );
}
