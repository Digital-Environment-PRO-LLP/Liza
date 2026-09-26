// Голосовые на Web (заявка №44): где виден микрофон, каким кодеком пишем,
// с каким mimetype уходит событие и что бывает, если запись не дала файла.
// kIsWeb на VM всегда false — web-ветки проверяются через чистые функции.
//
// ledger:RL-web-voice-record

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:matrix/matrix.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/chat/recording_view_model.dart';
import 'package:liza/utils/voice_recording_codec.dart';
import 'package:liza/utils/voice_recording_guard.dart';
import 'test_client.dart';

class _FakeRecorder implements AudioRecorder {
  _FakeRecorder({this.stopPath});

  final String? stopPath;
  int disposeCalls = 0;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<bool> isEncoderSupported(AudioEncoder encoder) async => true;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {}

  @override
  Future<String?> stop() async => stopPath;

  @override
  Future<void> cancel() async {}

  @override
  Future<Amplitude> getAmplitude() async => Amplitude(current: -30, max: -30);

  @override
  Future<void> dispose() async => disposeCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingPermissionRecorder extends _FakeRecorder {
  final permission = Completer<bool>();

  @override
  Future<bool> hasPermission() => permission.future;
}

class _FakeWakelock extends WakelockPlusPlatformInterface
    with MockPlatformInterfaceMixin {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<String?> getTemporaryPath() async => '/tmp';
}

void main() {
  group('canRecordVoice', () {
    test('AC-1: web — да, Windows/Linux — нет, натив — как раньше', () {
      // AC:RL-web-voice-record/1
      expect(
        canRecordVoice(isWeb: true, isMobile: false, isMacOS: false),
        isTrue,
      );
      // Windows/Linux: не web, не mobile, не macOS.
      expect(
        canRecordVoice(isWeb: false, isMobile: false, isMacOS: false),
        isFalse,
      );
      expect(
        canRecordVoice(isWeb: false, isMobile: true, isMacOS: false),
        isTrue,
      );
      expect(
        canRecordVoice(isWeb: false, isMobile: false, isMacOS: true),
        isTrue,
      );
    });
  });

  group('resolveVoiceCodec', () {
    test('AC-2: web — AAC, если браузер пишет MP4, иначе WAV 16 кГц', () async {
      // AC:RL-web-voice-record/2
      final aac = await resolveVoiceCodec(
        isWeb: true,
        isIOS: false,
        supports: (e) async => e == AudioEncoder.aacLc,
      );
      expect(aac.encoder, AudioEncoder.aacLc);
      expect(aac.sampleRate, isNull);

      // Firefox: MP4 нет, opus есть — всё равно WAV (webm не играет iOS).
      final firefox = await resolveVoiceCodec(
        isWeb: true,
        isIOS: false,
        supports: (e) async => e == AudioEncoder.opus,
      );
      expect(firefox.encoder, AudioEncoder.wav);
      expect(firefox.sampleRate, 16000);
    });

    test('AC-3: натив не изменился ∀ {iOS, opus есть, opus нет}', () async {
      // AC:RL-web-voice-record/3
      final ios = await resolveVoiceCodec(
        isWeb: false,
        isIOS: true,
        supports: (e) async => true,
      );
      expect((ios.encoder, ios.sampleRate), (AudioEncoder.aacLc, null));

      final opus = await resolveVoiceCodec(
        isWeb: false,
        isIOS: false,
        supports: (e) async => e == AudioEncoder.opus,
      );
      expect((opus.encoder, opus.sampleRate), (AudioEncoder.opus, null));

      final noOpus = await resolveVoiceCodec(
        isWeb: false,
        isIOS: false,
        supports: (e) async => false,
      );
      expect((noOpus.encoder, noOpus.sampleRate), (AudioEncoder.aacLc, null));
    });
  });

  group('voiceMimeForFileName', () {
    test('AC-4: web — audio/mp4 и audio/wav, натив — null', () {
      // AC:RL-web-voice-record/4
      expect(voiceMimeForFileName('recording1.m4a', isWeb: true), 'audio/mp4');
      expect(voiceMimeForFileName('recording1.wav', isWeb: true), 'audio/wav');
      for (final name in ['recording1.m4a', 'recording1.ogg', 'r.wav']) {
        expect(voiceMimeForFileName(name, isWeb: false), isNull, reason: name);
      }
    });

    test('AC-4: fragmented MP4 из Chrome уходит audio/mp4, а не video/mp4', () {
      // AC:RL-web-voice-record/4
      // Первые байты файла, записанного Chrome 153 (ftyp isom).
      final chromeHeader = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x24, 0x66, 0x74, 0x79, 0x70, //
        0x69, 0x73, 0x6f, 0x6d, 0x00, 0x00, 0x02, 0x00,
        0x69, 0x73, 0x6f, 0x6d, 0x69, 0x73, 0x6f, 0x36,
      ]);
      const name = 'recording1.m4a';
      // Red-proof: без явного типа SDK распознаёт видео.
      expect(
        MatrixAudioFile(bytes: chromeHeader, name: name).mimeType,
        'video/mp4',
      );
      final file = MatrixAudioFile(
        bytes: chromeHeader,
        name: name,
        mimeType: voiceMimeForFileName(name, isWeb: true),
      );
      expect(file.mimeType, 'audio/mp4');
      expect(file.info['mimetype'], 'audio/mp4');
    });
  });

  group('RecordingViewModel', () {
    late Room room;

    setUpAll(() async {
      wakelockPlusPlatformInstance = _FakeWakelock();
      PathProviderPlatform.instance = _FakePathProvider();
      room = Room(
        id: '!voice:example.invalid',
        client: await prepareTestClient(loggedIn: true),
      );
    });

    tearDown(() => VoiceRecordingGuard.notifier.value = null);

    Future<RecordingViewModelState> pumpModel(
      WidgetTester tester,
      _FakeRecorder recorder,
    ) async {
      late RecordingViewModelState state;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: const Locale('ru'),
          home: Scaffold(
            body: RecordingViewModel(
              createRecorder: () => recorder,
              builder: (context, s) {
                state = s;
                return Text(s.isRecording ? 'recording' : 'idle');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return state;
    }

    testWidgets(
      'AC-5: запись без файла — без исключения, панель и guard сброшены, SnackBar',
      (tester) async {
        // AC:RL-web-voice-record/5
        final recorder = _FakeRecorder(stopPath: null);
        final state = await pumpModel(tester, recorder);

        await tester.runAsync(() => state.startRecording(room));
        await tester.pump();
        expect(find.text('recording'), findsOneWidget);
        expect(VoiceRecordingGuard.notifier.value, isNotNull);

        var sent = false;
        await tester.runAsync(() async {
          state.stopAndSend((_, _, _, _) async => sent = true);
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(sent, isFalse);
        expect(find.text('idle'), findsOneWidget);
        expect(VoiceRecordingGuard.notifier.value, isNull);
        expect(
          find.text(
            'Голосовое не записалось. Проверьте доступ к микрофону и '
            'попробуйте ещё раз.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'ушли из чата, пока висел системный диалог разрешения — без setState '
      'на размонтированном State',
      (tester) async {
        final recorder = _PendingPermissionRecorder();
        final state = await pumpModel(tester, recorder);

        final started = state.startRecording(room);
        await tester.pumpWidget(const SizedBox());
        recorder.permission.complete(false);
        await tester.runAsync(() => started);
        await tester.pump();

        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('AC-7: после отправки рекордер утилизирован (dispose)', (
      tester,
    ) async {
      // AC:RL-web-voice-record/7
      final recorder = _FakeRecorder(stopPath: '/tmp/recording1.ogg');
      final state = await pumpModel(tester, recorder);

      await tester.runAsync(() => state.startRecording(room));
      await tester.pump();

      String? sentPath;
      await tester.runAsync(() async {
        state.stopAndSend((path, _, _, _) async => sentPath = path);
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();

      expect(sentPath, '/tmp/recording1.ogg');
      expect(find.text('idle'), findsOneWidget);
      expect(recorder.disposeCalls, 1);
    });
  });
}
