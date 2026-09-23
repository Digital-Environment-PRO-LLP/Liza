import 'package:flutter/foundation.dart';

/// Зеркало «экран заблокирован» с нативного слоя (macOS: `com.apple.screenIsLocked`
/// / `…Unlocked` через `MacApnsPushPlugin`, канал `onScreenLock`).
///
/// Зачем: на десктопе квитанция «прочитано» уходит и при
/// `AppLifecycleState.inactive` — окно видимо, но не в фокусе (человек реально
/// читает). Заблокированный экран даёт тот же `inactive`, а читать там некому.
/// Пока квитанция была безвредна — телефон получал пуш всё равно. С серверной
/// read-grace (`push.read_grace_ms`, 2026-09-17) квитанция с залоченного Мака
/// глушила бы пуш на iPhone — сообщение осталось бы без единого сигнала.
/// Поэтому `inactive` считается «читаемым» только при разблокированном экране.
///
/// Платформы без нативного зеркала (Windows/Linux/Web) остаются `false` —
/// прежнее поведение.
abstract final class ScreenLockState {
  static final ValueNotifier<bool> locked = ValueNotifier<bool>(false);

  static bool get isLocked => locked.value;

  static void update(bool value) {
    if (locked.value != value) locked.value = value;
  }

  @visibleForTesting
  static void reset() => locked.value = false;
}
