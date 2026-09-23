import 'package:shared_preferences/shared_preferences.dart';

/// Локальная (не синхронизируемая) отметка просмотренных сторисов.
/// "Кто посмотрел" на сервер НЕ шлём. Хранится только на устройстве.
///
/// Опциональный [scope] (обычно userID) изолирует отметки между аккаунтами
/// на одном устройстве. Без scope используется ключ по умолчанию (обратная
/// совместимость со старыми данными).
class StoriesSeenStore {
  final SharedPreferences _prefs;
  final String _key;

  StoriesSeenStore(this._prefs, {String? scope})
      : _key = scope == null
            ? 'com.liza.stories.seen'
            : 'com.liza.stories.seen.$scope';

  Set<String>? _cache;
  Set<String> get _seen =>
      _cache ??= (_prefs.getStringList(_key) ?? const []).toSet();

  bool isSeen(String eventId) => _seen.contains(eventId);

  Future<void> markSeen(String eventId) async {
    final seen = _seen..add(eventId);
    _cache = seen;
    await _prefs.setStringList(_key, seen.toList());
  }

  bool hasUnseen(Iterable<String> eventIds) {
    final seen = _seen;
    return eventIds.any((id) => !seen.contains(id));
  }

  /// Сбросить кеш в памяти — следующий доступ перечитает prefs.
  /// Нужен, чтобы StoriesBar увидел seen, записанный StoryViewer (другой
  /// инстанс store пишет в те же prefs, но кеши независимы).
  void invalidateCache() => _cache = null;

  Future<void> markAllSeen(Iterable<String> eventIds) async {
    final seen = _seen..addAll(eventIds);
    _cache = seen;
    await _prefs.setStringList(_key, seen.toList());
  }
}
