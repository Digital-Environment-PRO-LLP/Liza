import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/utils/deep_link_target.dart';

/// Ожидающая ссылка, по которой пользователь пришёл до логина.
class PendingDeepLink {
  const PendingDeepLink(this.kind, this.code);
  final DeepLinkKind kind;
  final String code;
}

/// Держатель ссылки между deep-link и login-flow.
///
/// Обобщает прежний PendingInviteCode на ЛЮБОЙ тип цели: раньше логин
/// переживали только инвайты, а сторис и канал при !isLogged уходили на /home
/// и терялись — пользователь после входа оказывался в списке чатов вместо
/// сущности, по ссылке на которую он пришёл.
///
/// Персист в SharedPreferences обязателен: в вебе переход к форме логина —
/// полная перезагрузка страницы, статика в памяти обнуляется.
class PendingDeepLinkStore {
  static PendingDeepLink? _pending;
  static Set<String>? _consumed;

  static const _currentKey = 'pending_deep_link.current';
  static const _consumedKey = 'pending_invite.consumed_deep_links';

  /// Ключ, под которым старая версия клиента (до обобщения хранилища на
  /// story/channel) писала ожидающий инвайт-код. Одноразовая миграция в
  /// [restore] переносит значение в [_currentKey] и удаляет старый ключ —
  /// иначе инвайт, записанный старой сборкой веб-клиента прямо перед
  /// перезагрузкой страницы на новую, осиротеет и молча потеряется. Убрать
  /// можно, когда все веб-сессии заведомо обновлены до нового формата.
  static const _legacyInviteKey = 'pending_invite.current';

  static PendingDeepLink? get current => _pending;

  static void set(DeepLinkKind kind, String code) {
    _pending = PendingDeepLink(kind, code);
    unawaited(_persist(_pending));
  }

  static void clear() {
    _pending = null;
    unawaited(_persist(null));
  }

  static Future<PendingDeepLink?> restore() async {
    if (_pending != null) return _pending;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_currentKey);
    if (stored == null || stored.isEmpty) {
      return _restoreLegacyInvite(prefs);
    }
    final separator = stored.indexOf(':');
    if (separator <= 0) return null;
    final kindName = stored.substring(0, separator);
    final code = stored.substring(separator + 1);
    if (code.isEmpty) return null;
    final kind = DeepLinkKind.values
        .where((k) => k.name == kindName)
        .firstOrNull;
    if (kind == null) return null;
    _pending = PendingDeepLink(kind, code);
    return _pending;
  }

  /// Фолбэк на старый формат хранения инвайт-кода. Новый ключ пуст — но это
  /// может быть либо «ничего не ждём», либо «ждём код, записанный ДО
  /// обобщения хранилища». Различить нельзя, поэтому читаем старый ключ и,
  /// если там что-то есть, переносим его в новый формат один раз.
  static Future<PendingDeepLink?> _restoreLegacyInvite(
    SharedPreferences prefs,
  ) async {
    final legacy = prefs.getString(_legacyInviteKey);
    if (legacy == null || legacy.isEmpty) return null;
    _pending = PendingDeepLink(DeepLinkKind.invite, legacy);
    await prefs.setString(_currentKey, '${DeepLinkKind.invite.name}:$legacy');
    await prefs.remove(_legacyInviteKey);
    return _pending;
  }

  @visibleForTesting
  static void debugResetInMemory() {
    _pending = null;
    _consumed = null;
  }

  static Future<void> _persist(PendingDeepLink? pending) async {
    final prefs = await SharedPreferences.getInstance();
    if (pending == null) {
      await prefs.remove(_currentKey);
    } else {
      await prefs.setString(_currentKey, '${pending.kind.name}:${pending.code}');
    }
  }

  /// Пометить код как обработанный. true — первая обработка.
  ///
  /// AppLinks.getInitialLink() отдаёт один и тот же URL при каждом монтировании
  /// ChatList, hot reload и cold start — без persistent guard пользователь
  /// зацикливается на экране ошибки.
  static Future<bool> markDeepLinkHandled(String code) async {
    final prefs = await SharedPreferences.getInstance();
    _consumed ??= (prefs.getStringList(_consumedKey) ?? const []).toSet();
    if (!_consumed!.add(code)) return false;
    if (_consumed!.length > 64) {
      final trimmed = _consumed!.toList().sublist(_consumed!.length - 64);
      _consumed = trimmed.toSet();
    }
    await prefs.setStringList(_consumedKey, _consumed!.toList());
    return true;
  }
}
