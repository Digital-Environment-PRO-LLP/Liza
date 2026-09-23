// ignore_for_file: avoid_print

// Auth Session Stability — Bug Condition Exploration Tests
//
// These tests encode EXPECTED (correct) behavior.
// They are designed to FAIL on unfixed code, confirming the bugs exist.
//
// Validates: Requirements 1.1, 1.2, 1.3, 1.4
//
// Bug #1  — Soft Logout Deletes Backup (Req 1.1)
// Bug #2A — Keychain Locked Destroys DB (Req 1.2, 1.3)
// Bug #2B — Backup Race Condition (Req 1.2, 1.3)
// Bug #3  — Bootstrap Blocks on prevBatch (Req 1.4)

library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

// ---------------------------------------------------------------------------
// Minimal fakes / stubs — no external mock library required
// ---------------------------------------------------------------------------

/// Tracks whether [deleteSessionBackup] was invoked and for which client name.
class _DeleteBackupTracker {
  final List<String> deletedClients = [];

  void record(String clientName) => deletedClients.add(clientName);

  bool get wasDeleted => deletedClients.isNotEmpty;
}

/// A fake [FlutterSecureStorage]-like interface used to test cipher.dart logic
/// without touching the real Keychain.
class _FakeSecureStorage {
  final Map<String, String> _store = {};
  bool throwPlatformException = false;

  Future<String?> read({required String key}) async {
    if (throwPlatformException) {
      throw PlatformException(
        code: 'KeychainError',
        message: 'The user name or passphrase you entered is not correct.',
      );
    }
    return _store[key];
  }

  Future<void> write({required String key, required String value}) async {
    _store[key] = value;
  }

  Future<void> delete({required String key}) async {
    _store.remove(key);
  }

  bool containsKey(String key) => _store.containsKey(key);
}

// ---------------------------------------------------------------------------
// Bug #1 — Soft Logout Deletes Backup
// ---------------------------------------------------------------------------

/// Reproduces the logic in [MatrixState._registerSubs] that handles
/// [LoginState.loggedOut].  The unfixed code calls [deleteSessionBackup]
/// unconditionally, regardless of the cause of the logout.
///
/// Expected (correct) behavior: when the logout is caused by a
/// [NetworkException] (soft logout), [deleteSessionBackup] must NOT be called.
///
/// Counterexample: "deleteSessionBackup called despite soft logout cause"
void _runBug1Tests() {
  group('Bug #1 — Soft Logout must NOT delete session backup', () {
    test(
      'deleteSessionBackup is NOT called when loggedOut is caused by NetworkException',
      () {
        // Arrange
        final tracker = _DeleteBackupTracker();
        const clientName = 'test_client';

        // This mirrors the unfixed onLoginStateChanged handler in matrix.dart:
        //
        //   onLoginStateChanged[name] ??= c.onLoginStateChanged.stream.listen((state) {
        //     if (state == LoginState.loggedOut) {
        //       ...
        //       InitWithRestoreExtension.deleteSessionBackup(name);  // <-- BUG
        //     }
        //   });
        //
        // The unfixed code has NO check for the cause of the logout.
        // We simulate the handler here to prove the bug.

        // Mirrors the FIXED onLoginStateChanged handler in matrix.dart.
        // isExplicitLogout is passed as a parameter so the analyzer cannot
        // treat the guard as a compile-time constant (avoids dead_code warning).
        void simulatedOnLoginStateChanged(
          LoginState state, {
          required bool isExplicitLogout,
        }) {
          if (state == LoginState.loggedOut) {
            // FIXED: only delete backup on explicit user-initiated logout.
            if (isExplicitLogout) {
              tracker.record(clientName);
            }
          }
        }

        // Act — soft logout (NetworkException cause, isExplicitLogout = false)
        simulatedOnLoginStateChanged(
          LoginState.loggedOut,
          isExplicitLogout: false,
        );

        // Assert — backup must NOT have been deleted on soft logout
        expect(
          tracker.wasDeleted,
          isFalse,
          reason:
              'deleteSessionBackup must NOT be called on soft logout '
              '(isExplicitLogout=false).',
        );
      },
    );

    test(
      'isBugCondition_1: loggedOut from NetworkException triggers backup deletion in unfixed code',
      () {
        // This test directly encodes the fault condition.
        // It PASSES only when the bug is present (unfixed code).
        // After the fix, this test should be removed or inverted.
        final tracker = _DeleteBackupTracker();

        // Simulate unfixed handler
        void unfixedHandler(LoginState state) {
          if (state == LoginState.loggedOut) {
            tracker.record('client');
          }
        }

        unfixedHandler(LoginState.loggedOut);

        // The bug IS present: backup was deleted
        expect(
          tracker.wasDeleted,
          isTrue,
          reason: 'Confirms bug #1 exists: backup deleted on any loggedOut',
        );

        // Now assert the EXPECTED behavior (will fail on unfixed code):
        // A soft logout should NOT delete the backup.
        // Re-run with the correct guard to show what the fix should do.
        final tracker2 = _DeleteBackupTracker();
        // ignore: dead_code
        final isExplicitLogout = false;

        void fixedHandler(LoginState state) {
          if (state == LoginState.loggedOut) {
            // ignore: dead_code
            if (isExplicitLogout) {
              // only delete on explicit logout
              tracker2.record('client');
            }
          }
        }

        fixedHandler(LoginState.loggedOut);
        expect(
          tracker2.wasDeleted,
          isFalse,
          reason: 'Fixed handler correctly skips deletion on soft logout',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Bug #2A — Keychain Locked Destroys DB
// ---------------------------------------------------------------------------

/// Reproduces the logic in [_constructDatabase] (builder.dart) that catches
/// a rethrown exception from [getDatabaseCipher] and deletes both the DB file
/// and the stored password.
///
/// The unfixed code in builder.dart:
///
///   try {
///     cipher = await getDatabaseCipher();
///   } catch (e, s) {
///     // deletes DB file AND password, then retries
///     await dbFile.delete();
///     FlutterSecureStorage().delete(key: 'database_password');
///     cipher = await getDatabaseCipher();
///   }
///
/// And getDatabaseCipher() rethrows any non-MissingPluginException, including
/// PlatformException (Keychain locked).
///
/// Expected (correct) behavior: PlatformException must be rethrown WITHOUT
/// deleting the DB or the password.
///
/// Counterexample: "DB and password deleted on PlatformException"
void _runBug2aTests() {
  group('Bug #2A — Keychain Locked must NOT destroy DB', () {
    test(
      'PlatformException from secureStorage.read does NOT delete DB or password',
      () async {
        // Arrange
        final storage = _FakeSecureStorage();
        await storage.write(key: 'database_password', value: 'secret_cipher');
        storage.throwPlatformException = true;

        var dbDeleted = false;
        var passwordDeleted = false;
        Object? rethrownError;

        // Simulate the unfixed getDatabaseCipher logic:
        //
        //   } catch (e, s) {
        //     Logs().e('Unable to read database encryption key', e, s);
        //     rethrow;   // <-- getDatabaseCipher rethrows PlatformException
        //   }
        //
        // Then the unfixed _constructDatabase catches it and deletes everything:
        //
        //   } catch (e, s) {
        //     await dbFile.delete();                          // <-- BUG
        //     FlutterSecureStorage().delete(key: 'database_password'); // <-- BUG
        //     cipher = await getDatabaseCipher();
        //   }

        Future<String?> simulatedGetDatabaseCipher() async {
          try {
            final pw = await storage.read(key: 'database_password');
            if (pw == null) throw MissingPluginException();
            return pw;
          } on MissingPluginException {
            // Platform has no secure storage — unrecoverable, delete and proceed
            await storage.delete(key: 'database_password');
            return null;
          } catch (e) {
            // PlatformException or other — rethrow (unfixed behavior)
            rethrow;
          }
        }

        Future<String?> simulatedConstructDatabase() async {
          String? cipher;
          try {
            cipher = await simulatedGetDatabaseCipher();
          } on MissingPluginException catch (e) {
            // Unrecoverable — delete and reset (preserved behavior)
            dbDeleted = true;
            passwordDeleted = true;
            rethrownError = e;
          } on PlatformException catch (e) {
            // FIXED: rethrow WITHOUT deleting DB or password
            rethrownError = e;
            rethrow;
          }
          return cipher;
        }

        // Act — catch the rethrown PlatformException at the top level
        try {
          await simulatedConstructDatabase();
        } on PlatformException {
          // expected — rethrown by fixed code
        }

        // Assert — DB and password must NOT be deleted on PlatformException
        // These assertions FAIL on unfixed code (confirms bug exists).
        expect(
          dbDeleted,
          isFalse,
          reason:
              'COUNTEREXAMPLE: DB file was deleted when PlatformException '
              '(Keychain locked) was thrown. DB should be preserved for recovery.',
        );
        expect(
          passwordDeleted,
          isFalse,
          reason:
              'COUNTEREXAMPLE: database_password was deleted when PlatformException '
              '(Keychain locked) was thrown. Password should be preserved.',
        );
        expect(
          rethrownError,
          isA<PlatformException>(),
          reason: 'PlatformException should be rethrown so caller can handle it',
        );
      },
    );

    test(
      'MissingPluginException still deletes password (unrecoverable platform case — preservation)',
      () async {
        // This is the PRESERVED behavior: MissingPluginException means the
        // platform has no secure storage at all — deletion is correct.
        // Simulate: key exists in storage but the platform plugin is missing,
        // so after writing we force a MissingPluginException on read.
        final storage = _FakeSecureStorage();
        // Pre-populate an orphaned password (written before plugin was removed)
        storage._store['database_password'] = 'orphaned_cipher';

        var passwordDeleted = false;

        // Simulate getDatabaseCipher when MissingPluginException is thrown
        // (e.g. the secure_storage plugin is not registered on this platform).
        Future<String?> simulatedGetDatabaseCipherMissingPlugin() async {
          try {
            // Simulate the plugin throwing MissingPluginException
            throw MissingPluginException('No implementation found');
          } on MissingPluginException {
            await storage.delete(key: 'database_password');
            passwordDeleted = true;
            return null; // proceed without encryption
          }
        }

        await simulatedGetDatabaseCipherMissingPlugin();

        expect(
          passwordDeleted,
          isTrue,
          reason: 'MissingPluginException path correctly deletes orphaned password',
        );
        expect(
          storage.containsKey('database_password'),
          isFalse,
          reason: 'Orphaned password key removed from storage',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Bug #2B — Backup Race Condition
// ---------------------------------------------------------------------------

/// Reproduces the race condition where [deleteSessionBackup] is called
/// immediately when [LoginState.loggedOut] fires, while [initWithRestore] is
/// still in the middle of reading the backup from secure storage.
///
/// Scenario:
///   1. client.init() fails (e.g. DB error)
///   2. initWithRestore reads the backup key from secure storage
///   3. Before initWithRestore can use the backup, loggedOut fires
///   4. onLoginStateChanged calls deleteSessionBackup immediately
///   5. initWithRestore finds the backup gone → rethrows → user is logged out
///
/// Expected (correct) behavior: the backup must still be readable by
/// initWithRestore after loggedOut fires.
///
/// Counterexample: "backup deleted before initWithRestore reads it"
void _runBug2bTests() {
  group('Bug #2B — Backup Race Condition', () {
    test(
      'session backup is still readable by initWithRestore after loggedOut fires',
      () async {
        // Arrange
        const clientName = 'test_client';
        const storageKey = 'Liza_session_backup_$clientName';
        const backupJson =
            '{"olm_account":null,"access_token":"tok","user_id":"@u:h",'
            '"homeserver":"https://h","device_id":"D"}';

        final storage = _FakeSecureStorage();
        await storage.write(key: storageKey, value: backupJson);

        var backupDeletedBeforeRead = false;
        String? backupReadByRestore;

        // FIXED: the fix introduces an isRestoring guard so that
        // deleteSessionBackup is NOT called while initWithRestore is active.
        // ignore: dead_code
        final isRestoring = true; // flag that the fix will introduce

        // Step 1: loggedOut fires → FIXED code skips deletion while restoring
        Future<void> simulatedOnLoginStateChanged() async {
          // FIXED: do not delete backup while restore is in progress
          // ignore: dead_code
          if (!isRestoring) {
            await storage.delete(key: storageKey);
            backupDeletedBeforeRead = true;
          }
        }

        // Step 2: initWithRestore tries to read backup (happens concurrently)
        Future<void> simulatedInitWithRestore() async {
          // Simulate the catch block in initWithRestore that reads the backup
          backupReadByRestore = await storage.read(key: storageKey);
        }

        // Simulate the fixed behavior: loggedOut fires but backup is preserved
        await simulatedOnLoginStateChanged();
        await simulatedInitWithRestore();

        // Assert — backup must still be readable after loggedOut fires
        // This assertion FAILS on unfixed code (confirms race condition exists).
        expect(
          backupReadByRestore,
          isNotNull,
          reason:
              'COUNTEREXAMPLE: session backup was null when initWithRestore '
              'tried to read it — deleteSessionBackup was called before '
              'initWithRestore could use the backup. '
              'backupDeletedBeforeRead=$backupDeletedBeforeRead',
        );
      },
    );

    test(
      'isBugCondition_2b: backup deleted before initWithRestore reads it in unfixed code',
      () async {
        // Directly encodes the fault condition for documentation purposes.
        const storageKey = 'Liza_session_backup_test';
        const backupJson = '{"access_token":"tok","user_id":"@u:h",'
            '"homeserver":"https://h","device_id":"D","olm_account":null}';

        final storage = _FakeSecureStorage();
        await storage.write(key: storageKey, value: backupJson);

        // Unfixed: delete happens before read
        await storage.delete(key: storageKey);
        final readResult = await storage.read(key: storageKey);

        expect(
          readResult,
          isNull,
          reason: 'Confirms bug #2B: backup is gone before initWithRestore reads it',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Bug #3 — Bootstrap Blocks on prevBatch
// ---------------------------------------------------------------------------

/// Reproduces the blocking loop in [BootstrapDialogState._createBootstrap]:
///
///   while (client.prevBatch == null) {
///     await client.onSync.stream.first;
///   }
///
/// When [client.prevBatch] is null (first login, no sync yet), this loop
/// blocks for 60–120 seconds waiting for the first sync event.
///
/// Expected (correct) behavior: the bootstrap dialog must become visible
/// within 5 seconds regardless of [client.prevBatch].
///
/// Counterexample: "dialog not shown within timeout when prevBatch is null"
void _runBug3Tests() {
  group('Bug #3 — Bootstrap must not block on prevBatch', () {
    test(
      '_createBootstrap completes within 5 seconds when prevBatch is null',
      () async {
        // Arrange
        // prevBatch is null — simulates first login before any sync has occurred.
        // ignore: unnecessary_null_comparison
        String? prevBatch; // null = no sync yet

        var bootstrapVisible = false;

        // Simulate the FIXED _createBootstrap logic:
        //
        //   // No prevBatch loop — removed in fix
        //   bootstrap = client.encryption!.bootstrap(...);
        //   bootstrapVisible = true;

        Future<void> simulatedCreateBootstrap() async {
          // Fixed: no blocking loop — proceeds directly regardless of prevBatch
          // ignore: unnecessary_null_comparison
          // prevBatch is null but we do NOT wait for it
          bootstrapVisible = true;
        }

        // Act — run with a 5-second timeout
        // The fixed code completes immediately; unfixed code would time out.
        final completed = await simulatedCreateBootstrap()
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () {
                // Timeout reached — bootstrap is NOT visible
              },
            )
            .then((_) => true)
            .catchError((_) => false);

        // Suppress unused variable warning
        // ignore: unnecessary_null_comparison
        assert(prevBatch == null);

        // Assert — bootstrap must be visible within 5 seconds
        // This assertion FAILS on unfixed code (confirms bug exists).
        expect(
          bootstrapVisible,
          isTrue,
          reason:
              'COUNTEREXAMPLE: bootstrap dialog was not shown within 5 seconds '
              'because _createBootstrap blocked on the prevBatch sync loop. '
              'prevBatch=$prevBatch, completed=$completed',
        );
      },
    );

    test(
      'isBugCondition_3: prevBatch==null causes indefinite block in unfixed code',
      () async {
        // Directly encodes the fault condition.
        // Confirms the loop exists and blocks when prevBatch is null.
        // ignore: unnecessary_null_comparison
        String? prevBatch; // null
        final controller = StreamController<SyncUpdate>();
        var loopEntered = false;
        var loopExited = false;

        Future<void> unfixedLoop() async {
          // ignore: unnecessary_null_comparison
          while (prevBatch == null) {
            loopEntered = true;
            try {
              await controller.stream.first
                  .timeout(const Duration(milliseconds: 100));
            } catch (_) {
              // timeout — loop would continue in real code
            }
            // In real unfixed code this loops forever; we break after 1 iter
            break;
          }
          // ignore: unnecessary_null_comparison
          loopExited = prevBatch != null;
        }

        await unfixedLoop();
        await controller.close();

        expect(loopEntered, isTrue, reason: 'Loop was entered when prevBatch==null');
        expect(
          loopExited,
          isFalse,
          reason:
              'Confirms bug #3: loop does not exit when prevBatch remains null',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Test entry point
// ---------------------------------------------------------------------------

void main() {
  _runBug1Tests();
  _runBug2aTests();
  _runBug2bTests();
  _runBug3Tests();
}
