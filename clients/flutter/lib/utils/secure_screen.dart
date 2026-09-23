import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Канал к платформенной реализации защиты экрана.
const _channel = MethodChannel('ru.liza/secure_screen');

/// Включить/снять защиту окна от скриншотов и записи экрана.
///
/// Android — `FLAG_SECURE` (система реально запрещает скриншот и запись).
/// iOS/macOS — только скрытие содержимого окна в переключателе приложений при
/// уходе в фон: запретить сам скриншот платформа не даёт, и обходить это
/// ограничение мы не пытаемся. Прочие платформы (Web/Windows/Linux) —
/// обработчика нет, вызов молча игнорируется.
Future<void> setPlatformSecure(bool enabled) async {
  try {
    await _channel.invokeMethod<void>('setSecure', {'enabled': enabled});
  } on MissingPluginException {
    // Платформа без реализации — ограничения остаются только в UI.
  } on PlatformException catch (e, s) {
    // Отказ платформы не должен ронять экран канала: контент всё равно
    // остаётся закрыт UI-гейтами (`Room.isContentProtected`).
    debugPrint('secure_screen: платформа отказала setSecure($enabled): $e\n$s');
  }
}

/// Счётчик активных стражей и последнее состояние, отданное платформе.
///
/// Счётчик, а НЕ булево поле у виджета: экраны канала вкладываются друг в
/// друга (лента → просмотрщик медиа → тред). При булевом поле закрытие
/// ВЕРХНЕГО экрана снимало бы флаг у нижнего, который ещё на экране, — и
/// подписчик снимал бы скриншот ленты. Платформу дёргаем только на переходах
/// 0↔1.
int _activeGuards = 0;
bool _platformSecure = false;

/// `true`, если реассерт на текущий `resumed` уже отправлен каким-то стражем.
///
/// Реассерт нужен платформе в целом (см. комментарий у
/// `didChangeAppLifecycleState`), а не каждому стражу по отдельности: при
/// вложенных экранах (лента → просмотрщик медиа) их несколько, и без этого
/// флага каждый бы слал свой `setSecure(true)` на один и тот же `resumed`.
/// Сбрасывается на следующей паузе, чтобы следующий `resumed` реассертнул снова.
bool _reassertedThisResume = false;

/// Сбрасывает глобальное состояние защиты между тестами.
@visibleForTesting
void debugResetSecureScreen() {
  _activeGuards = 0;
  _platformSecure = false;
  _reassertedThisResume = false;
}

/// Число стражей, удерживающих защиту прямо сейчас.
@visibleForTesting
int get debugActiveSecureGuards => _activeGuards;

/// Держит защиту экрана включённой, пока виджет в дереве.
///
/// Снятие в [dispose] обязательно: залипший `FLAG_SECURE` блокирует скриншоты
/// во всём приложении, а не только в канале.
class SecureScreenGuard extends StatefulWidget {
  const SecureScreenGuard({
    required this.enabled,
    required this.child,
    this.setSecure = setPlatformSecure,
    super.key,
  });

  final bool enabled;
  final Widget child;
  final Future<void> Function(bool enabled) setSecure;

  @override
  State<SecureScreenGuard> createState() => _SecureScreenGuardState();
}

class _SecureScreenGuardState extends State<SecureScreenGuard>
    with WidgetsBindingObserver {
  /// Держит ли ЭТОТ страж свою единицу в общем счётчике.
  bool _holding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void didUpdateWidget(SecureScreenGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _sync();
  }

  /// `MainActivity` в этом приложении НЕ пересоздаётся на поворот/смену темы —
  /// `AndroidManifest.xml` объявляет `android:configChanges` на все эти случаи.
  /// Настоящая причина реассерта — headless push-движок (`FcmPushService`)
  /// поднимает тот же синглтон `FlutterEngine`, что и Activity, но делает это
  /// через `executeDartEntrypoint` БЕЗ `configureFlutterEngine` — тот метод
  /// регистрирует канал `ru.liza/secure_screen` только в `MainActivity`. Если
  /// `setSecure(true)` уйдёт в момент, когда канал ещё не зарегистрирован,
  /// `MissingPluginException` молча проглатывается: Dart-страж думает, что
  /// защита включена, а платформа флаг не получила. На `resumed` (когда
  /// Activity точно поднята и канал точно привязан) переутверждаем желаемое
  /// состояние; на платформе вызов идемпотентен.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed) {
      // Следующий resumed должен реассертнуть заново — сбрасываем дедуп-флаг
      // на любом уходе из resumed (пауза/inactive/detached).
      _reassertedThisResume = false;
      return;
    }
    if (_reassertedThisResume) return;
    if (_holding && _platformSecure) {
      _reassertedThisResume = true;
      widget.setSecure(true);
    }
  }

  void _sync() {
    if (widget.enabled == _holding) return;
    _holding = widget.enabled;
    _activeGuards += widget.enabled ? 1 : -1;
    _apply();
  }

  /// Приводит платформу в соответствие счётчику. Вызов уходит вниз только на
  /// смене состояния: повторный `addFlags`/`clearFlags` при вложенных экранах
  /// не нужен, а лишний прыжок в главный поток Android — тем более.
  void _apply() {
    final shouldBeSecure = _activeGuards > 0;
    if (shouldBeSecure == _platformSecure) return;
    _platformSecure = shouldBeSecure;
    widget.setSecure(shouldBeSecure);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_holding) {
      _holding = false;
      _activeGuards -= 1;
      _apply();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
