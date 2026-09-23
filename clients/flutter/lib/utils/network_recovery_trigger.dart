import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:connectivity_plus/connectivity_plus.dart';

/// Состояния, в которых мобильная ОС вправе заморозить процесс. `inactive` —
/// НЕ заморозка (шторка, Пункт управления, системный баннер): процесс работает,
/// сокеты живы.
bool isSuspendingLifecycleState(AppLifecycleState? state) =>
    state == AppLifecycleState.hidden ||
    state == AppLifecycleState.paused ||
    state == AppLifecycleState.detached;

/// Решает, пересоздавать ли HTTP-клиенты на `resumed`.
///
/// Пересоздание (`MatrixState._refreshHttpClients`) закрывает прежний клиент
/// через `IOClient.close()` = `force: true` и рвёт ВСЕ запросы в полёте.
/// Оправдано оно только после заморозки процесса, когда ОС уже убила сокеты.
/// Возврат из одного `inactive` заморозкой не является, но приходит тем же
/// `resumed`. Инцидент 2026-09-15 (GlitchTip #2026): на медленной мобильной сети
/// голосовое 733 КБ качалось больше 10 с, два возврата из шторки оборвали и
/// загрузку, и её единственный повтор (Traefik: оба GET обрезаны ровно в моменты
/// `foreground`) → ложный `[audio-fail] kind=network` и SnackBar пользователю.
class ResumeHttpRefreshGate {
  /// [initial] — состояние на момент создания. Неизвестное считаем заморозкой:
  /// процесс мог стартовать в фоне от пуша.
  ResumeHttpRefreshGate(AppLifecycleState? initial)
    : _suspendedSinceResume =
          initial == null || isSuspendingLifecycleState(initial);

  bool _suspendedSinceResume;

  /// Вызывать на КАЖДУЮ смену состояния; `true` — пора пересоздать клиенты.
  bool onStateChange(AppLifecycleState state) {
    if (isSuspendingLifecycleState(state)) {
      _suspendedSinceResume = true;
      return false;
    }
    if (state != AppLifecycleState.resumed) return false;
    final refresh = _suspendedSinceResume;
    _suspendedSinceResume = false;
    return refresh;
  }
}

/// Пересоздаёт HTTP-клиенты при возврате/смене сети на mobile.
///
/// Проблема: при переключении сети (Wi-Fi <-> LTE на ходу) без сворачивания
/// приложения в пуле Dart остаются мёртвые TCP-сокеты. Клиент бьётся в них
/// (`Syncloop failed`, `HandshakeException`), пока пользователь не свернёт и
/// не развернёт приложение (только тогда срабатывает refresh на `resumed`).
///
/// Триггер слушает [Connectivity.onConnectivityChanged] и на ПЕРЕХОД в online
/// или смену активного транспорта дёргает [onRefresh] (в `MatrixState` это
/// `_refreshHttpClients`). Sync-loop SDK сам оживает за ~3с на свежих сокетах.
///
/// Только mobile: на macOS/desktop приложение при потере фокуса не выгружается,
/// сокеты живут, а пересоздание рвало бы активные upload/download/sync.
///
/// Логика вынесена из `MatrixState`, чтобы тестироваться без платформы: поток
/// событий, колбэк refresh и флаг isMobile инъектируются.
class NetworkRecoveryTrigger {
  NetworkRecoveryTrigger({
    required Stream<List<ConnectivityResult>> stream,
    required void Function() onRefresh,
    required bool isMobile,
    Duration debounce = const Duration(milliseconds: 1500),
  })  : _stream = stream,
        _onRefresh = onRefresh,
        _isMobile = isMobile,
        _debounce = debounce;

  final Stream<List<ConnectivityResult>> _stream;
  final void Function() _onRefresh;
  final bool _isMobile;
  final Duration _debounce;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _debounceTimer;

  /// Активный транспорт на прошлом событии (или null, если сети не было).
  /// Первое событие лишь запоминает состояние и НЕ триггерит: клиент только
  /// что жил, пересоздавать сокеты не нужно.
  ConnectivityResult? _lastTransport;
  bool _seenFirst = false;

  void start() {
    if (!_isMobile) return;
    _sub = _stream.listen(_onEvent);
  }

  void _onEvent(List<ConnectivityResult> results) {
    final transport = _activeTransport(results);

    if (!_seenFirst) {
      _seenFirst = true;
      _lastTransport = transport;
      return;
    }

    final wasOffline = _lastTransport == null;
    final isOnline = transport != null;
    final transportChanged =
        _lastTransport != null && transport != null && transport != _lastTransport;

    _lastTransport = transport;

    // Триггерим на переход offline -> online и на смену активного транспорта
    // между двумя online-состояниями. Стабильный online и уход в offline —
    // без refresh.
    if (isOnline && (wasOffline || transportChanged)) {
      _scheduleRefresh();
    }
  }

  void _scheduleRefresh() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, _onRefresh);
  }

  /// Первый не-none транспорт из списка (connectivity_plus 6.x отдаёт список,
  /// т.к. активных интерфейсов может быть несколько). null = сети нет.
  ConnectivityResult? _activeTransport(List<ConnectivityResult> results) {
    for (final r in results) {
      if (r != ConnectivityResult.none) return r;
    }
    return null;
  }

  void dispose() {
    _debounceTimer?.cancel();
    _sub?.cancel();
  }
}
