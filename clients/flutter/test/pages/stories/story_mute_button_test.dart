// Стражи управления звуком видео-сториса (①②③).
//
// Реестр: tests/registry/RL-story-video-mute-control.md
// Дизайн: docs/superpowers/specs/2026-09-02-stories-audio-control-and-android-push-triage-design.md
//
// РЕАЛЬНЫЙ виджет StoryMuteButton (тот же, что рендерится в шапке вьюера), не
// реплика. Полный EventVideoPlayer в host-тесте не поднимается (media_kit нужен
// нативный mpv) → громкость/выравнивание на устройстве покрыты device-flow
// (AC-1/AC-6, Ярус C).
//
// ledger:RL-story-video-mute-control

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/stories/story_mute_button.dart';

Future<void> _pumpButton(WidgetTester tester, ValueNotifier<bool> muted) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: Center(child: StoryMuteButton(muted: muted))),
    ),
  );
}

void main() {
  group('StoryMuteButton — управление звуком видео-сториса', () {
    testWidgets(
      'AC-2: дефолт mute → иконка volume_off (звук у зрителей по умолчанию выкл)',
      // AC:RL-story-video-mute-control/2
      (tester) async {
        final muted = ValueNotifier<bool>(true); // дефолт как в контроллере
        await _pumpButton(tester, muted);
        expect(find.byIcon(Icons.volume_off), findsOneWidget);
        expect(find.byIcon(Icons.volume_up), findsNothing);
        muted.dispose();
      },
    );

    testWidgets('тап переключает mute↔unmute на реальном виджете', (
      tester,
    ) async {
      final muted = ValueNotifier<bool>(true);
      await _pumpButton(tester, muted);
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      expect(muted.value, isFalse);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
      expect(find.byIcon(Icons.volume_off), findsNothing);
      muted.dispose();
    });

    testWidgets(
      'AC-3: состояние держится при пересоздании виджета (тот же notifier) — '
      'механизм «распространяется на остальные истории»',
      // AC:RL-story-video-mute-control/3
      (tester) async {
        // Общий notifier сеанса (живёт в контроллере, не в плеере).
        final muted = ValueNotifier<bool>(true);
        await _pumpButton(tester, muted);
        // Пользователь включил звук на истории N.
        await tester.tap(find.byType(IconButton));
        await tester.pump();
        expect(muted.value, isFalse);

        // Переход к истории N+1: плеер и кнопка пересоздаются по ValueKey.
        // Симулируем полный remount виджета кнопки С ТЕМ ЖЕ notifier'ом.
        await tester.pumpWidget(const SizedBox.shrink());
        await _pumpButton(tester, muted);

        // Состояние НЕ сбросилось на дефолт-mute — звук остался включённым.
        expect(muted.value, isFalse);
        expect(find.byIcon(Icons.volume_up), findsOneWidget);
        expect(find.byIcon(Icons.volume_off), findsNothing);
        muted.dispose();
      },
    );
  });

  group('shouldShowStoryMuteButton — гейт показа', () {
    // AC:RL-story-video-mute-control/5
    test('AC-5: видео + подпись свёрнута → показываем', () {
      expect(
        shouldShowStoryMuteButton(isVideo: true, captionExpanded: false),
        isTrue,
      );
    });
    test('AC-5: подпись развёрнута → скрываем (не под caption-оверлеем)', () {
      expect(
        shouldShowStoryMuteButton(isVideo: true, captionExpanded: true),
        isFalse,
      );
    });
    test('фото-сторис (не видео) → кнопки нет', () {
      expect(
        shouldShowStoryMuteButton(isVideo: false, captionExpanded: false),
        isFalse,
      );
    });
  });
}
