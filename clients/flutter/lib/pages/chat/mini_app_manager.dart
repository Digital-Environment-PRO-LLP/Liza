import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Описание одного открытого MiniApp-инстанса.
class MiniAppInstance {
  final String appUrl;
  final String appId;
  final String appName;
  final Room room;

  /// 'first_party' (наш доверенный app, прямой WebView) либо 'third_party'
  /// (сторонний код — грузится изолированно через shell + sandboxed iframe).
  final String appType;

  /// Deep-link на конкретную страницу mini App (`#!/tproduct/123`). Пусто —
  /// открываем главную.
  final String appStartPath;

  MiniAppInstance({
    required this.appUrl,
    required this.appId,
    required this.appName,
    required this.room,
    this.appType = 'first_party',
    this.appStartPath = '',
  });
}

/// Глобальный менеджер открытых MiniApp.
///
/// Хранит список открытых приложений, активное приложение,
/// состояние развёрнутости. Уведомляет подписчиков (MiniAppOverlay)
/// о любых изменениях.
class MiniAppManager extends ChangeNotifier {
  MiniAppManager._();
  static final MiniAppManager instance = MiniAppManager._();

  final List<MiniAppInstance> _apps = [];
  String? _activeAppId;
  bool _isExpanded = false;

  List<MiniAppInstance> get apps => List.unmodifiable(_apps);
  bool get hasApps => _apps.isNotEmpty;
  int get appCount => _apps.length;
  bool get isExpanded => _isExpanded;

  String? get activeAppId => _activeAppId;

  MiniAppInstance? get activeApp {
    if (_activeAppId == null) return null;
    try {
      return _apps.firstWhere((a) => a.appId == _activeAppId);
    } catch (_) {
      return null;
    }
  }

  /// Открывает miniApp. Если уже открыт — переключает на него и разворачивает.
  void open({
    required String appUrl,
    required String appId,
    required String appName,
    required Room room,
    String appType = 'first_party',
    String appStartPath = '',
  }) {
    final existing = _apps.where((a) => a.appId == appId);
    if (existing.isNotEmpty) {
      _activeAppId = appId;
      _isExpanded = true;
      notifyListeners();
      return;
    }

    _apps.add(MiniAppInstance(
      appUrl: appUrl,
      appId: appId,
      appName: appName,
      room: room,
      appType: appType,
      appStartPath: appStartPath,
    ));
    _activeAppId = appId;
    _isExpanded = true;
    notifyListeners();
  }

  /// Сворачивает текущий miniApp в плашку.
  void minimize() {
    _isExpanded = false;
    notifyListeners();
  }

  /// Разворачивает miniApp. Если указан appId — переключает на него.
  void expand([String? appId]) {
    if (appId != null && _apps.any((a) => a.appId == appId)) {
      _activeAppId = appId;
    }
    _isExpanded = true;
    notifyListeners();
  }

  /// Закрывает конкретный miniApp.
  void close(String appId) {
    _apps.removeWhere((a) => a.appId == appId);
    if (_activeAppId == appId) {
      _activeAppId = _apps.isNotEmpty ? _apps.last.appId : null;
    }
    if (_apps.isEmpty) {
      _isExpanded = false;
    }
    notifyListeners();
  }

  /// Закрывает все miniApp.
  void closeAll() {
    _apps.clear();
    _activeAppId = null;
    _isExpanded = false;
    notifyListeners();
  }

  /// Переключается на следующий miniApp (для свайпа между ними).
  void switchToNext() {
    if (_apps.length <= 1) return;
    final idx = _apps.indexWhere((a) => a.appId == _activeAppId);
    _activeAppId = _apps[(idx + 1) % _apps.length].appId;
    notifyListeners();
  }
}
