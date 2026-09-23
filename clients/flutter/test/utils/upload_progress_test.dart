import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

import 'package:liza/utils/upload_progress_http_client.dart';
import 'package:liza/utils/upload_progress_tracker.dart';

/// Внутренний клиент, который просто вычитывает тело запроса целиком
/// (это и прогоняет поток-счётчик `UploadProgressHttpClient`) и отдаёт
/// валидный ответ media-upload.
class _DrainingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    await request.finalize().toBytes();
    final body = utf8.encode('{"content_uri":"mxc://server/abc"}');
    return http.StreamedResponse(
      Stream.value(body),
      200,
      contentLength: body.length,
      request: request,
    );
  }
}

http.Request _uploadRequest(String url, int bytes) =>
    http.Request('POST', Uri.parse(url))..bodyBytes = Uint8List(bytes);

void main() {
  group('UploadProgressTracker', () {
    test('reportActiveProgress обновляет notifier активного txid', () {
      final tracker = UploadProgressTracker.instance;
      final notifier = tracker.register('txid-a');
      tracker.markActive('txid-a');

      tracker.reportActiveProgress(50, 200);

      expect(notifier.value, closeTo(0.25, 1e-9));
      expect(tracker.hasRealProgress('txid-a'), isTrue);

      tracker.unregister('txid-a');
      expect(tracker.hasRealProgress('txid-a'), isFalse);
    });

    test('reportActiveProgress без активного txid — no-op', () {
      final tracker = UploadProgressTracker.instance;
      final notifier = tracker.register('txid-b');
      tracker.markActive(null);

      tracker.reportActiveProgress(10, 100);

      expect(notifier.value, 0);
      expect(tracker.hasRealProgress('txid-b'), isFalse);
      tracker.unregister('txid-b');
    });

    test('доля клампится в 0..0.99', () {
      final tracker = UploadProgressTracker.instance;
      final notifier = tracker.register('txid-c');
      tracker.markActive('txid-c');

      tracker.reportActiveProgress(500, 200);

      // Кап 0.99: «байты отданы в сокет» ≠ «сервер подтвердил».
      expect(notifier.value, 0.99);
      tracker.unregister('txid-c');
    });

    test('requestCancel/isCancelled и очистка в unregister', () {
      final tracker = UploadProgressTracker.instance;
      tracker.register('txid-cx');
      tracker.markActive('txid-cx');

      expect(tracker.isCancelled('txid-cx'), isFalse);
      expect(tracker.isActiveCancelled, isFalse);

      tracker.requestCancel('txid-cx');
      expect(tracker.isCancelled('txid-cx'), isTrue);
      expect(tracker.isActiveCancelled, isTrue);

      tracker.unregister('txid-cx');
      // unregister снимает флаг — иначе он протёк бы в следующую загрузку.
      expect(tracker.isCancelled('txid-cx'), isFalse);
    });
  });

  group('UploadProgressHttpClient', () {
    test('крупная media-загрузка — все байты учтены (кап 0.99)', () async {
      final tracker = UploadProgressTracker.instance;
      final notifier = tracker.register('txid-up');
      tracker.markActive('txid-up');

      final client = UploadProgressHttpClient(_DrainingClient());
      await client.send(
        _uploadRequest(
          'https://h.example/_matrix/media/v3/upload',
          2 * 1024 * 1024,
        ),
      );

      expect(tracker.hasRealProgress('txid-up'), isTrue);
      // Все байты отданы, но прогресс капится на 0.99 — 100% показывается
      // фактом снятия overlay (unregister после ответа сервера).
      expect(notifier.value, 0.99);
      tracker.unregister('txid-up');
    });

    test('отмена обрывает отдачу MatrixException-ом (терминально для SDK)',
        () async {
      final tracker = UploadProgressTracker.instance;
      tracker.register('txid-cancel');
      tracker.markActive('txid-cancel');
      // Пользователь нажал крестик ещё до начала отдачи.
      tracker.requestCancel('txid-cancel');

      final client = UploadProgressHttpClient(_DrainingClient());

      // Отмена до начала отдачи → send бросает MatrixException синхронно
      // (top-of-send проверка). Замыкание — чтобы throwsA поймал синхронный
      // throw. retry-цикл room.sendFileEvent ловит MatrixException как
      // терминальный (см. UploadProgressHttpClient).
      expect(
        () => client.send(
          _uploadRequest(
            'https://h.example/_matrix/media/v3/upload',
            2 * 1024 * 1024,
          ),
        ),
        throwsA(isA<MatrixException>()),
      );

      tracker.unregister('txid-cancel');
    });

    test('мелкая загрузка (<1 МБ) не трекается', () async {
      final tracker = UploadProgressTracker.instance;
      final notifier = tracker.register('txid-small');
      tracker.markActive('txid-small');

      final client = UploadProgressHttpClient(_DrainingClient());
      await client.send(
        _uploadRequest(
          'https://h.example/_matrix/media/v3/upload',
          512 * 1024,
        ),
      );

      expect(tracker.hasRealProgress('txid-small'), isFalse);
      expect(notifier.value, 0);
      tracker.unregister('txid-small');
    });

    test('не-upload запрос не трекается', () async {
      final tracker = UploadProgressTracker.instance;
      final notifier = tracker.register('txid-other');
      tracker.markActive('txid-other');

      final client = UploadProgressHttpClient(_DrainingClient());
      await client.send(
        _uploadRequest(
          'https://h.example/_matrix/client/v3/sendToDevice',
          2 * 1024 * 1024,
        ),
      );

      expect(tracker.hasRealProgress('txid-other'), isFalse);
      expect(notifier.value, 0);
      tracker.unregister('txid-other');
    });
  });
}
