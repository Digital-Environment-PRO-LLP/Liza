import 'package:flutter/foundation.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/utils/news_poll.dart';
import 'package:liza/utils/platform_infos.dart';

/// Адресная рассылка Liza News по платформам устройства
/// (спека docs/superpowers/specs/2026-09-21-liza-news-platform-audience-design.md).
///
/// Бот кладёт в пост `com.liza.news.audience = {"platforms": [...]}`. Пуш на
/// устройства вне списка режет Sygnal, а на самом устройстве пост прячет клиент:
/// лента, превью списка, бейдж, локальное уведомление. Прятать приходится именно
/// клиенту — Windows/web/macOS показывают локальные уведомления из /sync мимо
/// Sygnal, а серверный счётчик непрочитанного один на пользователя, не на устройство.
const String newsAudienceKey = 'com.liza.news.audience';

/// Платформа этого устройства в словаре метки. iPad — это `ios` (решение
/// владельца). Windows/Linux/web в метке не бывают — адресный пост им не виден.
String? get currentNewsPlatform {
  if (debugNewsPlatformOverride case final override?) {
    return override.isEmpty ? null : override;
  }
  if (PlatformInfos.isIOS) return 'ios';
  if (PlatformInfos.isMacOS) return 'macos';
  if (PlatformInfos.isAndroid) return 'android';
  return null;
}

/// Тестовый шов: dart:io `Platform` в тестах не подменить. Пустая строка —
/// «платформа вне метки» (Windows/Linux/web).
@visibleForTesting
String? debugNewsPlatformOverride;

/// Платформы из метки; null — метки нет или она невалидна (пост для всех).
/// Правка поста (`m.new_content`) несёт метку так же, как оригинал.
List<String>? newsAudiencePlatforms(Map<String, Object?> content) {
  final audience = content[newsAudienceKey];
  if (audience is! Map) return null;
  final platforms = audience['platforms'];
  if (platforms is! List) return null;
  final result = platforms.whereType<String>().toList();
  return result.isEmpty ? null : result;
}

/// Чистое ядро: виден ли пост с такой меткой устройству платформы [platform].
bool newsAudienceAllows(List<String>? platforms, String? platform) =>
    platforms == null || (platform != null && platforms.contains(platform));

extension NewsAudienceEvent on Event {
  /// Пост Liza News адресован другим платформам — на этом устройстве его нет.
  /// Метку учитываем только от бота: иначе любой участник чата мог бы спрятать
  /// своё сообщение от собеседников на выбранных платформах.
  bool get isHiddenByNewsAudience {
    if (!newsBotMxids.contains(senderId)) return false;
    return !newsAudienceAllows(
      newsAudiencePlatforms(content),
      currentNewsPlatform,
    );
  }
}

extension NewsAudienceRoom on Room {
  /// Хвост комнаты — адресованный не этому устройству пост. Серверный
  /// `notificationCount` при этом всё равно вырос (он на пользователя), но
  /// «прочитать» невидимый пост нельзя, а квитанцию за него слать НЕЛЬЗЯ:
  /// она пометила бы пост прочитанным и на целевом устройстве того же человека.
  /// Поэтому такую комнату не считаем непрочитанной. Цена: видимый непрочитанный
  /// пост ПЕРЕД скрытым тоже перестаёт подсвечиваться — список чатов не грузит
  /// таймлайн, и найти предыдущее видимое событие негде.
  bool get hasNewsAudienceHiddenTail =>
      !markedUnread && lastEvent?.isHiddenByNewsAudience == true;
}
