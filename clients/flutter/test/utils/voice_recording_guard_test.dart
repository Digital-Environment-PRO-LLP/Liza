import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/voice_recording_guard.dart';

// Страж инварианта: уход из чата во время записи голосового не теряет её молча.
// ledger:RL-discard-recording-guard
void main() {
  group('VoiceRecordingGuard.confirmLeave', () {
    setUp(() => VoiceRecordingGuard.notifier.value = null);
    tearDown(() => VoiceRecordingGuard.notifier.value = null);

    Future<bool> pumpAndConfirm(WidgetTester tester) async {
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await VoiceRecordingGuard.confirmLeave(context);
                },
                child: const Text('leave'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('нет активной записи → уход разрешён, диалога нет', (
      tester,
    ) async {
      final result = await pumpAndConfirm(tester);
      expect(result, isTrue);
      expect(find.text('Discard'), findsNothing);
    });

    testWidgets('короткая запись (<700мс) → тихий сброс без диалога', (
      tester,
    ) async {
      var cancelled = false;
      VoiceRecordingGuard.notifier.value = ActiveVoiceRecording(
        durationOf: () => const Duration(milliseconds: 300),
        cancel: () => cancelled = true,
      );
      final result = await pumpAndConfirm(tester);
      expect(result, isTrue);
      expect(cancelled, isTrue, reason: 'короткую запись сбрасываем молча');
      expect(find.text('Discard'), findsNothing);
    });

    testWidgets('запись >=700мс → показан диалог; «Discard» сбрасывает и уходит',
        (tester) async {
      var cancelled = false;
      VoiceRecordingGuard.notifier.value = ActiveVoiceRecording(
        durationOf: () => const Duration(seconds: 3),
        cancel: () => cancelled = true,
      );
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await VoiceRecordingGuard.confirmLeave(context);
                },
                child: const Text('leave'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();

      // Диалог показан с обеими кнопками.
      expect(
        find.text(
          'Are you sure you want to stop recording and discard the recorded message?',
        ),
        findsOneWidget,
      );
      expect(find.text('No'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);

      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
      expect(cancelled, isTrue);
    });

    testWidgets('запись на паузе >=700мс → «No» оставляет запись', (
      tester,
    ) async {
      var cancelled = false;
      // Пауза — тоже активная запись (материал уже накоплен), диалог обязан быть.
      VoiceRecordingGuard.notifier.value = ActiveVoiceRecording(
        durationOf: () => const Duration(seconds: 5),
        cancel: () => cancelled = true,
      );
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await VoiceRecordingGuard.confirmLeave(context);
                },
                child: const Text('leave'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('leave'));
      await tester.pumpAndSettle();

      expect(find.text('No'), findsOneWidget);
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      expect(result, isFalse, reason: '«Нет» — остаёмся в чате');
      expect(cancelled, isFalse, reason: 'запись не сброшена');
    });
  });
}
