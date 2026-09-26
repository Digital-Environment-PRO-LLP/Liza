import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

/// Замечает, что открытая Web-вкладка работает на устаревшем бандле.
///
/// SPA не перезагружается сама: пользователь держит вкладку открытой сутками и
/// продолжает получать исправленные на проде ошибки (заявка №42 — фикс отправки
/// видео уже был на web.liza.ru, а вкладка жила на коде до деплоя).
///
/// Сравнивается идентификатор ДЕПЛОЯ, а не `build_number`: номер меняется только
/// на сторовом bump, а web выкатывают и между ними. Свой id — константа из
/// `--dart-define=WEB_DEPLOY_ID`; `PackageInfo` не годится — на Web он сам качает
/// тот же `version.json` с сервера и сравнил бы его с самим собой. Сравнение по
/// `!=`, чтобы откат тоже предлагал перезагрузку.
class WebUpdateChecker {
  WebUpdateChecker({
    http.Client? httpClient,
    this.currentDeployId = ownDeployId,
    this.isWeb = kIsWeb,
    Uri? versionUri,
    DateTime Function()? now,
  }) : _http = httpClient ?? http.Client(),
       _versionUri = versionUri ?? Uri.base.resolve('/version.json'),
       _now = now ?? DateTime.now;

  static const String ownDeployId = String.fromEnvironment('WEB_DEPLOY_ID');

  static const Duration resumeThrottle = Duration(minutes: 15);
  static const Duration pollInterval = Duration(minutes: 30);

  final http.Client _http;
  final Uri _versionUri;
  final DateTime Function() _now;

  /// Свой id деплоя. Пустой — сборка без `prepare-web.sh` (локальная, ручная):
  /// проверка выключена, чтобы не показывать ложный баннер.
  final String currentDeployId;

  final bool isWeb;

  final ValueNotifier<bool> updateAvailable = ValueNotifier(false);

  Timer? _timer;
  DateTime? _lastCheck;
  bool _disposed = false;

  bool get enabled => isWeb && currentDeployId.isNotEmpty;

  /// Первая проверка + периодический опрос: вкладку в фокусе часами никто не
  /// «возвращает», и `resumed` для неё не наступает.
  void start() {
    if (!enabled || _timer != null) return;
    unawaited(check(force: true));
    _timer = Timer.periodic(pollInterval, (_) => check(force: true));
  }

  /// Возврат на вкладку — с троттлом, чтобы переключения не плодили запросы.
  Future<void> onResumed() => check();

  Future<void> check({bool force = false}) async {
    if (_disposed || !enabled || updateAvailable.value) return;
    final now = _now();
    final last = _lastCheck;
    if (!force && last != null && now.difference(last) < resumeThrottle) {
      return;
    }
    _lastCheck = now;
    final serverId = await _fetchServerDeployId(now);
    // Запрос до 15 с: за это время корневой Matrix мог уйти, notifier уже
    // уничтожен — запись в него бросила бы в необработанную async-ошибку.
    if (_disposed) return;
    if (serverId != null && serverId != currentDeployId) {
      updateAvailable.value = true;
    }
  }

  Future<String?> _fetchServerDeployId(DateTime now) async {
    try {
      final uri = _versionUri.replace(
        queryParameters: {'cachebuster': '${now.microsecondsSinceEpoch}'},
      );
      final response = await _http
          .get(uri)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      if (json is! Map) return null;
      final id = json['deploy_id'];
      return id is String && id.isNotEmpty ? id : null;
    } catch (e) {
      Logs().v('WebUpdateChecker: version.json недоступен: $e');
      return null;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    updateAvailable.dispose();
  }
}
