import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/platform_infos.dart';

enum ConnectivityFailureType { dns, tcp, tls, timeout, httpError, unknown }

class ConnectivityCheckResult {
  final bool dnsOk;
  final bool tcpOk;
  final bool httpsOk;
  final String? failedHost;
  final String? failureReason;
  final ConnectivityFailureType? failureType;

  const ConnectivityCheckResult({
    required this.dnsOk,
    required this.tcpOk,
    required this.httpsOk,
    this.failedHost,
    this.failureReason,
    this.failureType,
  });

  bool get isOk => dnsOk && tcpOk && httpsOk;
}

class ConnectivityCheckException implements Exception {
  final String host;
  final String reason;
  final ConnectivityFailureType failureType;

  const ConnectivityCheckException({
    required this.host,
    required this.reason,
    required this.failureType,
  });

  @override
  String toString() => 'ConnectivityCheckException: $host — $reason';
}

class AuthDiagnostics {
  static int? _cachedAndroidSdkVersion;

  static Future<int> getAndroidSdkVersion() async {
    if (_cachedAndroidSdkVersion != null) return _cachedAndroidSdkVersion!;
    if (!PlatformInfos.isAndroid) return 99;
    final info = await DeviceInfoPlugin().androidInfo;
    _cachedAndroidSdkVersion = info.version.sdkInt;
    Logs().i(
      '[AuthDiag] Android SDK ${info.version.sdkInt}, '
      'device=${info.model}, manufacturer=${info.manufacturer}',
    );
    return _cachedAndroidSdkVersion!;
  }

  /// WebView on Android < 24 (Nougat) may have TLS/callback issues.
  static bool shouldUsePollingFallback(int sdkVersion) => sdkVersion < 24;

  /// Checks connectivity to each host: DNS → TCP:443 → HTTPS HEAD.
  /// Stops at the first failing host and returns the result.
  static Future<ConnectivityCheckResult> checkConnectivity({
    required List<String> hosts,
  }) async {
    const stepTimeout = Duration(seconds: 10);

    for (final host in hosts) {
      // Step 1: DNS
      try {
        await InternetAddress.lookup(host).timeout(stepTimeout);
        Logs().i('[AuthDiag] DNS OK for $host');
      } on SocketException catch (e) {
        Logs().w('[AuthDiag] DNS failed for $host', e);
        return ConnectivityCheckResult(
          dnsOk: false,
          tcpOk: false,
          httpsOk: false,
          failedHost: host,
          failureReason: e.osError?.message ?? e.message,
          failureType: ConnectivityFailureType.dns,
        );
      } on TimeoutException {
        Logs().w('[AuthDiag] DNS timeout for $host');
        return ConnectivityCheckResult(
          dnsOk: false,
          tcpOk: false,
          httpsOk: false,
          failedHost: host,
          failureReason: 'DNS lookup timed out',
          failureType: ConnectivityFailureType.timeout,
        );
      }

      // Step 2: TCP connect to port 443
      Socket? socket;
      try {
        socket = await Socket.connect(host, 443, timeout: stepTimeout);
        Logs().i('[AuthDiag] TCP OK for $host:443');
      } on SocketException catch (e) {
        Logs().w('[AuthDiag] TCP failed for $host:443', e);
        return ConnectivityCheckResult(
          dnsOk: true,
          tcpOk: false,
          httpsOk: false,
          failedHost: host,
          failureReason: e.osError?.message ?? e.message,
          failureType: ConnectivityFailureType.tcp,
        );
      } on TimeoutException {
        Logs().w('[AuthDiag] TCP timeout for $host:443');
        return ConnectivityCheckResult(
          dnsOk: true,
          tcpOk: false,
          httpsOk: false,
          failedHost: host,
          failureReason: 'TCP connection timed out',
          failureType: ConnectivityFailureType.timeout,
        );
      } finally {
        socket?.destroy();
      }
    }

    return const ConnectivityCheckResult(
      dnsOk: true,
      tcpOk: true,
      httpsOk: true,
    );
  }
}
