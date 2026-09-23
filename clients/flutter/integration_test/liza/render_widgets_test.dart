import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:liza/pages/chat/events/audio_player.dart';
import 'package:liza/pages/chat/events/message_content.dart';

// Девайсный рендер-страж (Ярус C, Android/iOS): прогоняет РЕАЛЬНЫЕ прод-виджеты
// [AudioWaveformSlider] и [CornerTimeLayout] на НАСТОЯЩЕМ бинаре устройства, а не
// на хостовой Dart-VM. Host-golden (Ярус A) со шрифтом Ahem платформо-НЕзависим и
// НЕ ловит расхождения рендера на Android (как рисуется Material Slider, метрики
// шрифта, IntrinsicWidth над RichText в native-движке, OverlayPortal Slider).
// Этот тест закрывает пробел «зелёный golden ≠ так же на Android» (комиссия
// 2026-07-28). Сервер НЕ нужен — только рендер.
//
// ⚠️ Что этот Ярус даёт и чего НЕТ: он проверяет, что прод-виджеты рисуются на
// устройстве БЕЗ overflow/исключений и с сохранёнными параметрами выравнивания
// (padding=zero/noOverlay — механизм «плашки у начала»). Пиксель-точную позицию
// thumb он НЕ мерит (это делает host-golden `audio_waveform_slider` детерминиро-
// ванно; на девайсе pixel-diff недетерминирован из-за density/шрифтов).
// Ещё honest-gap: инстанцируем `AudioWaveformSlider`/`CornerTimeLayout` НАПРЯМУЮ,
// а не через `AudioPlayerWidget`/`MessageContent` (тем нужен Matrix Client). Значит
// регресс в ПРОВОДКЕ (как родитель зовёт эти виджеты) здесь не виден — это зона
// host-юнитов/golden, не девайсного яруса.

const _available = 340.0;
const _timeKey = Key('time');
const _contentKey = Key('content');

final List<int> _waveform = List<int>.generate(
  AudioPlayerWidget.wavesCount,
  (i) => 120 + ((i * 37) % 5) * 180,
);

Widget _audio(double value, double wavePosition) => SizedBox(
  width: _available,
  height: 40,
  child: AudioWaveformSlider(
    waveform: _waveform,
    color: const Color(0xFF444444),
    thumbColor: const Color(0xFF000000),
    wavePosition: wavePosition,
    value: value,
    max: AudioPlayerWidget.wavesCount.toDouble(),
    onChanged: (_) {},
  ),
);

Widget _timeRow() => Row(
  key: _timeKey,
  mainAxisSize: MainAxisSize.min,
  children: const [
    Text('12:09', style: TextStyle(fontSize: 11, color: Colors.white)),
    SizedBox(width: 3),
    Icon(Icons.done_all, size: 14, color: Colors.white),
  ],
);

Widget _bubble(String text) => SizedBox(
  width: _available,
  child: Align(
    alignment: Alignment.topLeft,
    child: Material(
      color: const Color(0xFF4C4B7A),
      child: CornerTimeLayout(
        content: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
          child: Text(
            text,
            key: _contentKey,
            style: const TextStyle(fontSize: 16, color: Colors.white),
          ),
        ),
        time: _timeRow(),
      ),
    ),
  ),
);

Future<void> _host(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(home: Scaffold(body: Center(child: child))),
);

void _assertSliderAligned(WidgetTester tester) {
  // Выравнивание «плашки у начала» держится на этих параметрах — их и мерим
  // (детерминированно, на девайсе). Убери любой — thumb уедет от начала дорожки.
  final sliderTheme = tester.widget<SliderTheme>(
    find
        .ancestor(of: find.byType(Slider), matching: find.byType(SliderTheme))
        .first,
  );
  expect(sliderTheme.data.padding, EdgeInsets.zero);
  expect(sliderTheme.data.overlayShape, SliderComponentShape.noOverlay);
  final pad = tester.widget<Padding>(
    find.ancestor(of: find.byType(Slider), matching: find.byType(Padding)).first,
  );
  expect(
    pad.padding,
    const EdgeInsets.symmetric(horizontal: AudioWaveform.horizontalPadding),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Liza render (device): аудио-ползунок + время в углу', () {
    testWidgets(
      'AudioWaveformSlider непрослушанное (value=0) — рисуется, ползунок выровнен — ledger:RL-audio-waveform-time',
      (tester) async {
        await _host(tester, _audio(0, 0));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(Slider), findsOneWidget);
        expect(find.byType(AudioWaveform), findsOneWidget);
        _assertSliderAligned(tester);
      },
    );

    testWidgets(
      'AudioWaveformSlider проигранное (value>0) — рисуется без overflow на устройстве — ledger:RL-audio-waveform-time',
      (tester) async {
        await _host(tester, _audio(16, 16));
        await tester.pumpAndSettle();
        // Ключевое для Яруса C: проигранное состояние рисуется на нативном
        // движке без исключений/overflow (host-VM с Ahem этого не воспроизводит).
        expect(tester.takeException(), isNull);
        expect(find.byType(Slider), findsOneWidget);
        _assertSliderAligned(tester);
      },
    );

    testWidgets(
      'CornerTimeLayout короткий «ок» — компактный пузырь, время под текстом — ledger:RL-message-time-corner',
      (tester) async {
        await _host(tester, _bubble('ок'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final layout = tester.getRect(find.byType(CornerTimeLayout));
        // Короткий пузырь НЕ раздувается на всю ширину (IntrinsicWidth) на девайсе.
        expect(layout.width, lessThan(_available - 40));
        // Время — строкой НИЖЕ текста (в углу), не inline.
        final contentBottom = tester.getRect(find.byKey(_contentKey)).bottom;
        final timeRect = tester.getRect(find.byKey(_timeKey));
        expect(timeRect.top, greaterThanOrEqualTo(contentBottom));
        // ...и прижато ВПРАВО (Align.centerRight): правый край времени ≈ правому
        // краю пузыря. Замена на centerLeft увела бы время влево — ловим это.
        expect(layout.right - timeRect.right, lessThan(20));
      },
    );

    testWidgets(
      'CornerTimeLayout длинный текст — время в правом нижнем углу, без наезда — ledger:RL-message-time-corner',
      (tester) async {
        await _host(
          tester,
          _bubble(
            'до ждфыо адфоы адофыд аождфыоа джфы аджфофыждао фдыжво аждфыо '
            'аждлофываджфыоа дфы аджфы жд ещё немного текста для переноса строк',
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final layout = tester.getRect(find.byType(CornerTimeLayout));
        // Длинный текст расширил пузырь (в отличие от «ок») — но не бесконечно.
        expect(layout.width, greaterThan(_available - 40));
        // Время всё равно строкой ниже текста, не наезжает, и прижато вправо.
        final contentBottom = tester.getRect(find.byKey(_contentKey)).bottom;
        final timeRect = tester.getRect(find.byKey(_timeKey));
        expect(timeRect.top, greaterThanOrEqualTo(contentBottom));
        expect(layout.right - timeRect.right, lessThan(20));
      },
    );
  });
}
