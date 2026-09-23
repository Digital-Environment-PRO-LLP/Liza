import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-device capability-сервис: сообщает серверу {platform, build} через
/// отдельный эндпоинт, НЕ через device_display_name/clientName (см. design
/// doc docs/superpowers/specs/2026-07-01-chat-topology-stories-sync-gate-design.md,
/// секция 2 — почему device_display_name отвергнут как носитель).
class DeviceCapabilityService {
  DeviceCapabilityService({
    required this.putCapability,
    required this.resolvePlatform,
    required this.resolveBuild,
    required this.prefs,
  });

  /// Реальный сетевой вызов: PUT .../devices/{deviceId}/capabilities.
  /// Внедряется как зависимость для тестируемости без реальной сети;
  /// production-реализация подключается в Task 12 через client.request.
  final Future<bool> Function(String deviceId, String platform, int build)
      putCapability;

  final String Function() resolvePlatform;
  final Future<int?> Function() resolveBuild;
  final SharedPreferences prefs;

  static const _markerKeyPrefix = 'com.liza.capabilities.last_sent.';

  Future<void> reportIfNeeded({required String deviceId}) async {
    final platform = resolvePlatform();
    final build = await resolveBuild();
    if (build == null) {
      // Web и подобные платформы без надёжного build number: не шлём
      // фиктивное значение (см. design doc секция 2 "Web").
      return;
    }

    final markerKey = '$_markerKeyPrefix$deviceId';
    final lastSentRaw = prefs.getString(markerKey);
    if (lastSentRaw != null) {
      final lastSent = jsonDecode(lastSentRaw) as Map<String, dynamic>;
      if (lastSent['platform'] == platform && lastSent['build'] == build) {
        return;
      }
    }

    try {
      final success = await putCapability(deviceId, platform, build);
      if (success) {
        await prefs.setString(
          markerKey,
          jsonEncode({'platform': platform, 'build': build}),
        );
      }
    } catch (_) {
      // Fail-open: тихо проглатываем, попробуем на следующем вызове
      // (следующий cold start/resume), без агрессивных ретраев.
    }
  }
}
