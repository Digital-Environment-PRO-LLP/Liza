import 'dart:async';
import 'dart:typed_data';

import 'package:matrix/matrix.dart';

import 'e2e_config.dart';

/// Headless-«собеседник» для e2e-тестов: чистый Matrix CS API без БД, sync —
/// поллингом. Паттерн Element Web: второй пользователь не гоняется через
/// второй GUI-клиент, а действует через API (см. tests/e2e.md).
class E2eActor {
  final MatrixApi api;
  final String userId;
  String? _since;

  E2eActor._(this.api, this.userId);

  static Future<E2eActor> login(Uri homeserver, E2eUser user) async {
    final api = MatrixApi(homeserver: homeserver);
    final response = await api.login(
      'm.login.password',
      identifier: AuthenticationUserIdentifier(user: user.name),
      password: user.password,
      // client_guard пропускает только device-name с префиксом «Liza ».
      initialDeviceDisplayName: 'Liza E2E actor ${user.name}',
    );
    api.accessToken = response.accessToken;
    return E2eActor._(api, response.userId);
  }

  Future<String> createDirectChat(String inviteUserId) {
    return api.createRoom(
      invite: [inviteUserId],
      isDirect: true,
      preset: CreateRoomPreset.trustedPrivateChat,
    );
  }

  /// Групповая комната (НЕ DM) с несколькими приглашёнными — для кейсов
  /// SeenByRow с несколькими читателями и проверки исключения себя.
  Future<String> createGroupChat(List<String> inviteUserIds, {String? name}) {
    return api.createRoom(
      invite: inviteUserIds,
      preset: CreateRoomPreset.trustedPrivateChat,
      name: name,
    );
  }

  Future<String> joinRoom(String roomId) => api.joinRoom(roomId);

  Future<String> sendText(String roomId, String text) {
    return api.sendMessage(
      roomId,
      'm.room.message',
      'e2e-${DateTime.now().microsecondsSinceEpoch}',
      {'msgtype': 'm.text', 'body': text},
    );
  }

  Future<void> sendReadReceipt(String roomId, String eventId) {
    return api.postReceipt(roomId, ReceiptType.mRead, eventId);
  }

  /// Заливает аудио-байты и шлёт m.audio — для теста воспроизведения голосовых.
  Future<String> sendAudio(
    String roomId,
    Uint8List bytes, {
    String filename = 'voice.wav',
    String mimeType = 'audio/wav',
  }) async {
    final uri = await api.uploadContent(
      bytes,
      filename: filename,
      contentType: mimeType,
    );
    return api.sendMessage(
      roomId,
      'm.room.message',
      'e2e-audio-${DateTime.now().microsecondsSinceEpoch}',
      {
        'msgtype': 'm.audio',
        'body': filename,
        'url': uri.toString(),
        'info': {'mimetype': mimeType, 'size': bytes.length},
      },
    );
  }

  /// Заливает байты картинки и шлёт m.image С ПОДПИСЬЮ (`body` = подпись,
  /// `filename` = имя файла) — для теста «Скопировать текст» на медиа.
  Future<String> sendImageWithCaption(
    String roomId,
    Uint8List bytes,
    String caption, {
    String filename = 'photo.png',
    String mimeType = 'image/png',
  }) async {
    final uri = await api.uploadContent(
      bytes,
      filename: filename,
      contentType: mimeType,
    );
    return api.sendMessage(
      roomId,
      'm.room.message',
      'e2e-image-${DateTime.now().microsecondsSinceEpoch}',
      {
        'msgtype': 'm.image',
        'body': caption,
        'filename': filename,
        'url': uri.toString(),
        'info': {'mimetype': mimeType, 'size': bytes.length},
      },
    );
  }

  /// Отправляет АЛЬБОМ (Liza-галерею) из [count] картинок: [count] отдельных
  /// `m.image` с общим `com.liza.gallery.id`, полями `i`=0..N-1, `n`=count,
  /// caption на `i==0`. Воспроизводит схему `send_file_dialog.dart`. Возвращает
  /// eventId якоря (`i==0`).
  Future<String> sendGallery(
    String roomId,
    Uint8List bytes, {
    int count = 3,
    String? caption,
    String galleryId = '',
  }) async {
    final gid = galleryId.isEmpty
        ? 'e2e-gallery-${DateTime.now().microsecondsSinceEpoch}'
        : galleryId;
    String? anchorId;
    for (var i = 0; i < count; i++) {
      final uri = await api.uploadContent(
        bytes,
        filename: 'album_$i.png',
        contentType: 'image/png',
      );
      final id = await api.sendMessage(
        roomId,
        'm.room.message',
        'e2e-album-$gid-$i',
        {
          'msgtype': 'm.image',
          'body': i == 0 && caption != null ? caption : 'album_$i.png',
          'filename': 'album_$i.png',
          'url': uri.toString(),
          'info': {'mimetype': 'image/png', 'size': bytes.length},
          'com.liza.gallery': {
            'id': gid,
            'i': i,
            'n': count,
            if (i == 0 && caption != null) 'caption': caption,
          },
        },
      );
      anchorId ??= id;
    }
    return anchorId!;
  }

  /// Отправляет ОДИН `m.image` с полем `com.liza.gallery` где `n` > числа
  /// реально отправленных членов (симуляция СТАРОГО битого форварда альбома:
  /// переслан только якорь с исходным `n`, соседей нет). Даёт вечные
  /// фантом-спиннеры на клиенте ДО фикса grace-капа.
  Future<String> sendBrokenForwardedGalleryAnchor(
    String roomId,
    Uint8List bytes, {
    int declaredCount = 3,
  }) async {
    final gid = 'e2e-broken-fwd-${DateTime.now().microsecondsSinceEpoch}';
    final uri = await api.uploadContent(
      bytes,
      filename: 'broken.png',
      contentType: 'image/png',
    );
    return api.sendMessage(
      roomId,
      'm.room.message',
      'e2e-broken-$gid',
      {
        'msgtype': 'm.image',
        'body': 'broken.png',
        'filename': 'broken.png',
        'url': uri.toString(),
        'info': {'mimetype': 'image/png', 'size': bytes.length},
        'com.liza.forwarded': <String, Object?>{},
        'com.liza.gallery': {'id': gid, 'i': 0, 'n': declaredCount},
      },
    );
  }

  /// Отправляет `m.video`. По умолчанию [bytes] — НЕвоспроизводимый мусор
  /// (нет валидного контейнера), чтобы device-flow детерминированно довёл плеер
  /// до состояния ошибки/буферизации и проверил, что там НЕТ кнопок «Скачать»/
  /// «Сохранить» (страж `RL-video-viewer-save-and-overlay`). Реальное большое
  /// E2EE-видео на слабом канале воспроизводится только на устройстве (manual).
  Future<String> sendVideo(
    String roomId, {
    Uint8List? bytes,
    String filename = 'clip.mp4',
    String mimeType = 'video/mp4',
  }) async {
    final payload = bytes ??
        Uint8List.fromList(
          List<int>.generate(64 * 1024, (i) => (i * 73 + 19) & 0xff),
        );
    final uri = await api.uploadContent(
      payload,
      filename: filename,
      contentType: mimeType,
    );
    return api.sendMessage(
      roomId,
      'm.room.message',
      'e2e-video-${DateTime.now().microsecondsSinceEpoch}',
      {
        'msgtype': 'm.video',
        'body': filename,
        'filename': filename,
        'url': uri.toString(),
        'info': {'mimetype': mimeType, 'size': payload.length},
      },
    );
  }

  /// Ждёт в [roomId] событие, удовлетворяющее [test] (поллинг /sync).
  Future<MatrixEvent> waitForEvent(
    String roomId,
    bool Function(MatrixEvent event) test, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final sync = await api.sync(since: _since, timeout: 5000);
      _since = sync.nextBatch;
      final events = sync.rooms?.join?[roomId]?.timeline?.events ?? [];
      for (final event in events) {
        if (test(event)) return event;
      }
    }
    throw TimeoutException('Не дождались события в $roomId за $timeout');
  }

  /// Убрать комнату из аккаунта, чтобы повторные прогоны не плодили чаты.
  Future<void> leaveAndForget(String roomId) async {
    try {
      await api.leaveRoom(roomId);
      await api.forgetRoom(roomId);
    } catch (_) {
      // комната могла быть уже покинута — для cleanup не критично
    }
  }

  /// Покинуть комнату, НЕ забывая её: она остаётся в архиве (`loadArchive`).
  /// `forget` вычистил бы комнату и из архива — для стражей архива не годится
  /// (ledger:RL-archive-chat-back-to-archive).
  Future<void> leaveWithoutForget(String roomId) async {
    try {
      await api.leaveRoom(roomId);
    } catch (_) {
      // комната могла быть уже покинута — для сценария не критично
    }
  }

  Future<void> logout() => api.logout();
}
