import 'package:flutter/foundation.dart';

import 'package:liza/utils/deep_link_target.dart';
import 'package:liza/utils/pending_deep_link.dart';

/// Совместимая обёртка над [PendingDeepLinkStore] для инвайт-кодов.
///
/// Хранилище обобщено на любой тип ссылки (сторис/канал тоже должны переживать
/// логин), а этот фасад оставлен, чтобы не переписывать разом все семь мест
/// вызова в homeserver_picker/auth_select.
class PendingInviteCode {
  static String? get current {
    final pending = PendingDeepLinkStore.current;
    if (pending == null || pending.kind != DeepLinkKind.invite) return null;
    return pending.code;
  }

  static void set(String? code) {
    if (code == null) {
      PendingDeepLinkStore.clear();
      return;
    }
    PendingDeepLinkStore.set(DeepLinkKind.invite, code);
  }

  static String? consume() {
    final code = current;
    clear();
    return code;
  }

  static void clear() => PendingDeepLinkStore.clear();

  static Future<String?> restore() async {
    await PendingDeepLinkStore.restore();
    return current;
  }

  // Сам debugResetInMemory — тестовый метод; вызов через публичный фасад
  // PendingInviteCode (тоже @visibleForTesting) нужен существующим тестам
  // pending_invite_code_test.dart, которые не переписываем в этой задаче.
  @visibleForTesting
  static void debugResetInMemory() {
    // ignore: invalid_use_of_visible_for_testing_member
    PendingDeepLinkStore.debugResetInMemory();
  }

  static Future<bool> markDeepLinkHandled(String code) =>
      PendingDeepLinkStore.markDeepLinkHandled(code);
}
