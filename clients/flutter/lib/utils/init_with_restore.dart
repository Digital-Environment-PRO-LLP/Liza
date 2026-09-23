import 'dart:convert';

import 'package:matrix/matrix.dart';

import 'package:liza/config/setting_keys.dart';
import 'package:liza/utils/platform_infos.dart';
import 'package:liza/utils/secure_storage.dart';

class SessionBackup {
  final String? olmAccount;
  final String accessToken;
  final String userId;
  final String homeserver;
  final String? deviceId;
  final String? deviceName;

  const SessionBackup({
    required this.olmAccount,
    required this.accessToken,
    required this.userId,
    required this.homeserver,
    required this.deviceId,
    this.deviceName,
  });

  factory SessionBackup.fromJsonString(String json) =>
      SessionBackup.fromJson(jsonDecode(json));

  factory SessionBackup.fromJson(Map<String, dynamic> json) => SessionBackup(
    olmAccount: json['olm_account'],
    accessToken: json['access_token'],
    userId: json['user_id'],
    homeserver: json['homeserver'],
    deviceId: json['device_id'],
    deviceName: json['device_name'],
  );

  Map<String, dynamic> toJson() => {
    'olm_account': olmAccount,
    'access_token': accessToken,
    'user_id': userId,
    'homeserver': homeserver,
    'device_id': deviceId,
    if (deviceName != null) 'device_name': deviceName,
  };

  @override
  String toString() => jsonEncode(toJson());
}

extension InitWithRestoreExtension on Client {
  static Future<void> deleteSessionBackup(
    String clientName, {
    String? userId,
  }) async {
    final storage = PlatformInfos.isMobile || PlatformInfos.isLinux
        ? flutterSecureStorage
        : null;
    await storage?.delete(
      key: '${AppSettings.applicationName.value}_session_backup_$clientName',
    );
    // Also delete the stored recovery key so that an invalid key is not
    // auto-filled in the Bootstrap dialog after the user logs in again.
    if (userId != null) {
      await storage?.delete(key: 'ssss_recovery_key_$userId');
    }
  }

  Future<void> initWithRestore({void Function()? onMigration}) async {
    final storageKey =
        '${AppSettings.applicationName.value}_session_backup_$clientName';
    final storage = PlatformInfos.isMobile || PlatformInfos.isLinux
        ? flutterSecureStorage
        : null;

    try {
      await init(
        onInitStateChanged: (state) {
          if (state == InitState.migratingDatabase) onMigration?.call();
        },
        waitForFirstSync: false,
        waitUntilLoadCompletedLoaded: false,
      );
      if (isLogged()) {
        final accessToken = this.accessToken;
        final homeserver = this.homeserver?.toString();
        final deviceId = deviceID;
        final userId = userID;
        final hasBackup =
            accessToken != null &&
            homeserver != null &&
            deviceId != null &&
            userId != null;
        assert(hasBackup);
        if (hasBackup) {
          Logs().v('Store session in backup');
          storage?.write(
            key: storageKey,
            value: SessionBackup(
              olmAccount: encryption?.pickledOlmAccount,
              accessToken: accessToken,
              deviceId: deviceId,
              homeserver: homeserver,
              deviceName: deviceName,
              userId: userId,
            ).toString(),
          );
        }
      }
    } catch (e, s) {
      Logs().wtf('Client init failed!', e, s);
      final sessionBackupString = await storage?.read(key: storageKey);
      if (sessionBackupString == null) {
        rethrow;
      }

      try {
        final sessionBackup = SessionBackup.fromJsonString(sessionBackupString);
        await init(
          newToken: sessionBackup.accessToken,
          newOlmAccount: sessionBackup.olmAccount,
          newDeviceID: sessionBackup.deviceId,
          newDeviceName: sessionBackup.deviceName,
          newHomeserver: Uri.tryParse(sessionBackup.homeserver),
          newUserID: sessionBackup.userId,
          waitForFirstSync: false,
          waitUntilLoadCompletedLoaded: false,
          onInitStateChanged: (state) {
            if (state == InitState.migratingDatabase) onMigration?.call();
          },
        );
      } catch (e, s) {
        Logs().wtf('Restore client failed!', e, s);
        rethrow;
      }
    }
  }
}
