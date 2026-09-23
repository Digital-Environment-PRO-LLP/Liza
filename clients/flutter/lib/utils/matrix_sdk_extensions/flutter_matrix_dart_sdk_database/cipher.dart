import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/config/setting_keys.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/client_manager.dart';
import 'package:liza/utils/platform_infos.dart';
import 'package:liza/utils/secure_storage.dart';

const _passwordStorageKey = 'database_password';
const _maxRetries = 5;

/// How many consecutive launches may fail with a null Keychain read (while a
/// database file exists) before we stop preserving the unreadable DB and
/// regenerate the password instead.
///
/// A genuine transient Keychain lock (e.g. iOS launched by push before the
/// device's first unlock) resolves within a launch or two, and the counter is
/// cleared on the next successful read. A *permanently* inaccessible item —
/// the app was re-signed with a different identity, so macOS denies the new
/// binary access to the item written by the previous build — never resolves.
/// Without this bound the app bricks itself in an infinite restart loop after
/// such an update (see the boot-loop regression: null read -> KeychainLocked
/// -> uncaught -> AppRestart -> repeat).
const _maxKeychainLockedBoots = 3;
const _keychainLockedBootCountKey = 'keychain_locked_boot_count';

/// What to do after attempting to read the database password.
enum KeychainReadOutcome {
  /// A password was read — open the DB with it.
  useExisting,

  /// Null read but a DB exists and we are still within the transient-lock
  /// budget — throw [PlatformException] to preserve the DB and retry next
  /// launch.
  retryLater,

  /// Either a genuine first run, or the Keychain item is permanently
  /// inaccessible — generate a fresh password (the stale, undecryptable DB is
  /// recreated downstream).
  regenerate,
}

/// Pure boot-loop policy, extracted so it can be unit-tested without platform
/// channels. [consecutiveNullBoots] is the failure count *including* the
/// current boot.
@visibleForTesting
KeychainReadOutcome decideKeychainOutcome({
  required bool passwordPresent,
  required bool databaseExists,
  required int consecutiveNullBoots,
  int maxLockedBoots = _maxKeychainLockedBoots,
}) {
  if (passwordPresent) return KeychainReadOutcome.useExisting;
  if (databaseExists && consecutiveNullBoots < maxLockedBoots) {
    return KeychainReadOutcome.retryLater;
  }
  return KeychainReadOutcome.regenerate;
}

Future<String?> getDatabaseCipher() async {
  String? password;

  try {
    password = await _readWithRetry();

    if (password != null) {
      // Successful read — clear any prior transient-lock streak.
      await _resetKeychainLockedBootCount();
      return password;
    }

    // Null read. Decide whether to preserve the existing DB (transient lock)
    // or regenerate the password (first run / permanently inaccessible item).
    final databaseExists = !kIsWeb && await _databaseFileExists();
    final consecutiveNullBoots =
        databaseExists ? await _incrementKeychainLockedBootCount() : 0;

    final outcome = decideKeychainOutcome(
      passwordPresent: false,
      databaseExists: databaseExists,
      consecutiveNullBoots: consecutiveNullBoots,
    );

    if (outcome == KeychainReadOutcome.retryLater) {
      // Before generating a new password, check if a database file already
      // exists on disk. If it does, a null read likely means the Keychain is
      // temporarily locked (iOS returns null instead of throwing), NOT that
      // this is a first run. Preserve the DB and retry on the next launch.
      Logs().w(
        'Keychain returned null but database file exists — likely a transient '
        'lock (boot $consecutiveNullBoots/$_maxKeychainLockedBoots), '
        'preserving DB and retrying next launch.',
      );
      throw PlatformException(
        code: 'KeychainLocked',
        message: 'Keychain returned null for existing database password. '
            'Device may not be fully unlocked yet.',
      );
    }

    if (databaseExists) {
      // outcome == regenerate while a DB exists: the item has been null for
      // [_maxKeychainLockedBoots] consecutive launches. This is no longer a
      // plausible transient lock — treat it as permanently inaccessible (e.g.
      // the app was re-signed) and stop the restart loop by regenerating.
      Logs().e(
        'Keychain still null after $consecutiveNullBoots boots — treating the '
        'item as permanently inaccessible; regenerating password and letting '
        'the undecryptable DB be recreated from a fresh sync.',
      );
    }

    // Truly first run, or permanently inaccessible Keychain — generate and
    // store a new password.
    final rng = Random.secure();
    final list = Uint8List(32);
    list.setAll(0, Iterable.generate(list.length, (i) => rng.nextInt(256)));
    final newPassword = base64UrlEncode(list);
    await _writeWithRetry(newPassword);

    // Verify the write succeeded.
    password = await flutterSecureStorage.read(key: _passwordStorageKey);
    if (password == null) throw MissingPluginException();

    // New password persisted — clear the streak so the next launch starts fresh.
    await _resetKeychainLockedBootCount();
  } on MissingPluginException catch (e) {
    // Platform doesn't support secure storage — unrecoverable, delete orphaned
    // password and proceed without encryption
    flutterSecureStorage
        .delete(key: _passwordStorageKey)
        .catchError((_) {});
    Logs().w('Database encryption is not supported on this platform', e);
    _sendNoEncryptionWarning(e);
  } on PlatformException catch (e, s) {
    // Temporary error (e.g. Keychain locked on iOS) — do NOT delete the DB or
    // password; rethrow so the caller can surface the error and let
    // initWithRestore recover the session on the next launch.
    Logs().w(
      'Temporary secure storage error, preserving DB and password',
      e,
      s,
    );
    rethrow;
  } catch (e, s) {
    // Unexpected error — rethrow so the caller can handle it.
    Logs().e('Unable to read database encryption key', e, s);
    rethrow;
  }

  return password;
}

/// Read the database password with retries on [PlatformException].
Future<String?> _readWithRetry() async {
  for (var attempt = 1; attempt <= _maxRetries; attempt++) {
    try {
      return await flutterSecureStorage.read(key: _passwordStorageKey);
    } on PlatformException catch (e, s) {
      Logs().w(
        'Secure storage read attempt $attempt/$_maxRetries failed',
        e,
        s,
      );
      if (attempt < _maxRetries) {
        // Exponential backoff: 500ms, 1s, 2s, 4s, 8s (~15.5s total)
        await Future.delayed(Duration(milliseconds: 500 * (1 << (attempt - 1))));
      } else {
        rethrow;
      }
    }
  }
  return null;
}

/// Write the database password with retries on [PlatformException].
Future<void> _writeWithRetry(String value) async {
  for (var attempt = 1; attempt <= _maxRetries; attempt++) {
    try {
      await flutterSecureStorage.write(
        key: _passwordStorageKey,
        value: value,
      );
      return;
    } on PlatformException catch (e, s) {
      Logs().w(
        'Secure storage write attempt $attempt/$_maxRetries failed',
        e,
        s,
      );
      if (attempt < _maxRetries) {
        await Future.delayed(Duration(milliseconds: 500 * (1 << (attempt - 1))));
      } else {
        rethrow;
      }
    }
  }
}

/// Persist and return the consecutive count of launches where the Keychain
/// returned null while a DB existed. Stored in SharedPreferences (a plist,
/// not the Keychain) so it stays readable even when the Keychain does not.
Future<int> _incrementKeychainLockedBootCount() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final next = (prefs.getInt(_keychainLockedBootCountKey) ?? 0) + 1;
    await prefs.setInt(_keychainLockedBootCountKey, next);
    return next;
  } catch (_) {
    // Cannot persist the counter — fail safe toward preserving the DB.
    return 1;
  }
}

Future<void> _resetKeychainLockedBootCount() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keychainLockedBootCountKey);
  } catch (_) {}
}

/// Check if any .sqlite database file exists on disk (returning user).
Future<bool> _databaseFileExists() async {
  try {
    final databaseDirectory = PlatformInfos.isIOS || PlatformInfos.isMacOS
        ? await getLibraryDirectory()
        : await getApplicationSupportDirectory();
    final dir = Directory(databaseDirectory.path);
    if (!await dir.exists()) return false;
    return await dir
        .list()
        .any((entity) => entity.path.endsWith('.sqlite'));
  } catch (_) {
    return false;
  }
}

void _sendNoEncryptionWarning(Object exception) async {
  final isStored = AppSettings.noEncryptionWarningShown.value;

  if (isStored == true) return;

  final l10n = await lookupL10n(PlatformDispatcher.instance.locale);
  ClientManager.sendInitNotification(
    l10n.noDatabaseEncryption,
    l10n.noDatabaseEncryption,
  );

  await AppSettings.noEncryptionWarningShown.setItem(true);
}
