// Стражи классификатора причины сбоя получения вложения (`mediaFailureKind`) и
// его применения: честный `TranscriptionErrorKind` на стадии 1 транскрибации.
//
// Инцидент 2026-09-09 (GlitchTip issue #111/#112, устройство iPhone17,2,
// сборка 3747): у пользователя на 20 секунд пропала связь — прод-MMR за окно
// сбоя не получил НИ ОДНОГО запроса, а следующая попытка того же файла прошла
// успешно (скачивание 17:08:03 UTC → транскрибация 200 OK в 17:08:05). Но
// алёрт сказал `reason=transcription-decrypt`, а пользователь прочитал «Не
// удалось расшифровать голосовое сообщение»: оба catch-all вокруг ОДНОГО шага
// `downloadAndDecryptAttachmentHealed()` не различали сеть и расшифровку.
//
// ledger:RL-media-failure-kind

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:liza/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:liza/utils/transcription_service.dart';

void main() {
  group('mediaFailureKind — закрытый перечень, сеть ≠ расшифровка', () {
    // AC:RL-media-failure-kind/1
    test('AC-1: настоящий sha256-mismatch SDK → decrypt (и только он)', () {
      expect(mediaFailureKind(kDecryptFailure), 'decrypt');
      expect(isHealableDecryptFailure(kDecryptFailure), isTrue);
    });

    // AC:RL-media-failure-kind/2 — RED-PROOF инцидента: ∀ сетевым классам НЕ decrypt
    test('AC-2: ∀ сетевым сбоям → network/timeout, НИКОГДА не decrypt', () {
      final networkErrors = <Object>[
        const SocketException('Connection reset by peer'),
        const SocketException('Failed host lookup'),
        http.ClientException('Connection closed before full header'),
        const HandshakeException('TLS handshake failed'),
        // Голые TLS-классы: `HandshakeException`/`CertificateException` —
        // ПОДклассы `TlsException`, обратное неверно. Проверка по подклассам
        // роняла бы их в `other` → `decrypt` (та же ложь, что чиним).
        const TlsException('TLS error'),
        const CertificateException('Untrusted certificate'),
        const HttpException('Connection closed while receiving data'),
      ];
      for (final e in networkErrors) {
        expect(
          mediaFailureKind(e),
          'network',
          reason: 'сетевой сбой ${e.runtimeType} не должен зваться decrypt',
        );
      }
      expect(mediaFailureKind(TimeoutException('slow')), 'timeout');
    });

    // AC:RL-media-failure-kind/3
    test('AC-3: ошибка доставки сервера (HTTP≥400 / error-page) → http', () {
      expect(
        mediaFailureKind(const MediaDownloadException(statusCode: 404)),
        'http',
      );
      expect(
        mediaFailureKind(
          const MediaDownloadException(
            statusCode: 200,
            contentType: 'application/json',
          ),
        ),
        'http',
      );
    });

    // AC:RL-media-failure-kind/4
    test('AC-4: прочие голые строки SDK → sdk, остальное → other '
        '(не маскируются под сеть)', () {
      expect(mediaFailureKind('Unable to download file from local store.'), 'sdk');
      expect(mediaFailureKind("Missing 'decrypt' in 'key_ops'."), 'sdk');
      expect(mediaFailureKind(StateError('boom')), 'other');
      expect(mediaFailureKind(Exception('boom')), 'other');
    });

    // AC:RL-media-failure-kind/5
    test('AC-5: kind не несёт текста ошибки (PII/локатор контента) ∀ входам', () {
      final errors = <Object>[
        const SocketException('mxc://synapse.liza/AbCdEf host 1.2.3.4'),
        http.ClientException('/var/tmp/mxc_AbCdEf_recording.m4a'),
        Exception('Bearer syt_secret_token'),
        kDecryptFailure,
      ];
      const forbidden = ['mxc://', '/var/', '/tmp/', 'bearer', 'syt_', '@'];
      for (final e in errors) {
        final kind = mediaFailureKind(e);
        for (final bad in forbidden) {
          expect(kind.toLowerCase(), isNot(contains(bad)),
              reason: 'kind="$kind" не должен нести "$bad"');
        }
      }
    });
  });

  group('TranscriptionService.stageOneKindFor — честный вид ошибки', () {
    // AC:RL-media-failure-kind/6 — то самое, что соврало пользователю
    test('AC-6: сетевой сбой на стадии 1 → network (НЕ decrypt): пользователь '
        'больше не читает «Не удалось расшифровать» при живом файле', () {
      expect(
        TranscriptionService.stageOneKindFor(
          const SocketException('Connection reset by peer'),
        ),
        TranscriptionErrorKind.network,
      );
      expect(
        TranscriptionService.stageOneKindFor(
          http.ClientException('Connection closed'),
        ),
        TranscriptionErrorKind.network,
      );
      expect(
        TranscriptionService.stageOneKindFor(
          const MediaDownloadException(statusCode: 502),
        ),
        TranscriptionErrorKind.network,
      );
      expect(
        TranscriptionService.stageOneKindFor(TimeoutException('slow')),
        TranscriptionErrorKind.timeout,
      );
    });

    // AC:RL-media-failure-kind/7
    test('AC-7: настоящий сбой расшифровки остаётся decrypt; неопознанное — '
        'консервативно decrypt (фолбэк прежнего поведения, не ложь про сеть)', () {
      expect(
        TranscriptionService.stageOneKindFor(kDecryptFailure),
        TranscriptionErrorKind.decrypt,
      );
      expect(
        TranscriptionService.stageOneKindFor(StateError('boom')),
        TranscriptionErrorKind.decrypt,
      );
    });
  });
}
