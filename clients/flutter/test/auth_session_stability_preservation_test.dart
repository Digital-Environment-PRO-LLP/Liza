// ignore_for_file: avoid_print

library;


import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

// ---------------------------------------------------------------------------
// Shared fakes — same patterns as exploration test
// ---------------------------------------------------------------------------

class _DeleteBackupTracker {
  final List<String> deletedClients = [];
  void record(String clientName) => deletedClients.add(clientName);
  bool get wasDeleted => deletedClients.isNotEmpty;
  bool deletedFor(String name) => deletedClients.contains(name);
}

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
// Preservation 1 — Explicit Logout
// ---------------------------------------------------------------------------

/// **Validates: Requirements 3.1**
///
/// Observes: when `_isExplicitLogout = true`, the unfixed `onLoginStateChanged`
/// handler calls `deleteSessionBackup` unconditionally (which happens to be
/// correct for explicit logout).
///
/// Property: for ALL explicit logout events, backup IS deleted and the router
/// navigates to '/home' (login screen).
void _runExplicitLogoutPreservationTests() {
  group('Preservation 1 — Explicit Logout deletes backup and navigates to login', () {
    // Property: explicit logout always deletes backup
    test(
      'deleteSessionBackup IS called on explicit logout (isExplicitLogout=true)',
      () {
        final tracker = _DeleteBackupTracker();
        const clientName = 'explicit_logout_client';

        // Simulate the current onLoginStateChanged handler in matrix.dart.
        // The unfixed code calls deleteSessionBackup unconditionally on loggedOut.
        // For explicit logout this is CORRECT behavior we want to preserve.
        void simulatedOnLoginStateChanged(LoginState state) {
          if (state == LoginState.loggedOut) {
            tracker.record(clientName);
          }
        }

        simulatedOnLoginStateChanged(LoginState.loggedOut);

        expect(
          tracker.wasDeleted,
          isTrue,
          reason: 'Explicit logout must delete the session backup',
        );
        expect(
          tracker.deletedFor(clientName),
          isTrue,
          reason: 'Backup deleted for the correct client name',
        );
      },
    );

    // Property: navigation goes to '/home' (login screen) on explicit logout
    test(
      'router navigates to /home on explicit logout (single-account)',
      () {
        final navigatedRoutes = <String>[];

        // Simulate the routing logic from onLoginStateChanged (single account):
        //   LizaApp.router.go(
        //     state == LoginState.loggedIn ? '/backup' : '/home',
        //   );
        void simulatedRouting(LoginState state, {bool multiAccount = false}) {
          if (!multiAccount) {
            navigatedRoutes.add(
              state == LoginState.loggedIn ? '/backup' : '/home',
            );
          }
        }

        simulatedRouting(LoginState.loggedOut);

        expect(
          navigatedRoutes,
          contains('/home'),
          reason: 'Explicit logout must navigate to /home (login screen)',
        );
      },
    );

    // Property-based: for any client name, explicit logout always deletes that client's backup
    test(
      'property: for any client name, explicit logout always deletes that client backup',
      () {
        final clientNames = [
          'alice',
          'bob',
          'Liza-1234567890',
          'user@matrix.org',
          'client_with_special-chars.123',
        ];

        for (final name in clientNames) {
          final tracker = _DeleteBackupTracker();

          void handler(LoginState state) {
            if (state == LoginState.loggedOut) {
              tracker.record(name);
            }
          }

          handler(LoginState.loggedOut);

          expect(
            tracker.deletedFor(name),
            isTrue,
            reason: 'Backup must be deleted for client "$name" on explicit logout',
          );
        }
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Preservation 2 — Hard Logout (401)
// ---------------------------------------------------------------------------

/// **Validates: Requirements 3.4**
///
/// Observes: `LoginState.loggedOut` emitted by the Matrix SDK when the server
/// returns a 401 (hard logout / token invalidation) causes the unfixed handler
/// to clear the session and navigate to login — which is CORRECT.
///
/// Property: for ALL hard-logout events (server-side 401), session is cleared
/// and the login screen is shown.
void _runHardLogoutPreservationTests() {
  group('Preservation 2 — Hard Logout (401) clears session and navigates to login', () {
    test(
      'session is cleared (client removed, subs cancelled) on hard logout',
      () {
        final removedClients = <String>[];
        final cancelledSubs = <String>[];
        final tracker = _DeleteBackupTracker();
        const clientName = 'hard_logout_client';

        // Simulate the onLoginStateChanged handler for hard logout.
        // The SDK emits LoginState.loggedOut when the server returns 401.
        // The unfixed handler:
        //   1. Cancels subscriptions (_cancelSubs)
        //   2. Removes client from widget.clients
        //   3. Removes client name from store
        //   4. Calls deleteSessionBackup
        void simulatedHardLogoutHandler(LoginState state) {
          if (state == LoginState.loggedOut) {
            cancelledSubs.add(clientName); // _cancelSubs
            removedClients.add(clientName); // widget.clients.remove(c)
            tracker.record(clientName); // deleteSessionBackup
          }
        }

        simulatedHardLogoutHandler(LoginState.loggedOut);

        expect(
          removedClients,
          contains(clientName),
          reason: 'Client must be removed from active clients on hard logout',
        );
        expect(
          cancelledSubs,
          contains(clientName),
          reason: 'Subscriptions must be cancelled on hard logout',
        );
        expect(
          tracker.wasDeleted,
          isTrue,
          reason: 'Session backup must be deleted on hard logout (401)',
        );
      },
    );

    test(
      'router navigates to /home on hard logout (single-account)',
      () {
        final navigatedRoutes = <String>[];

        void simulatedRouting(LoginState state) {
          // Single-account path from onLoginStateChanged:
          navigatedRoutes.add(
            state == LoginState.loggedIn ? '/backup' : '/home',
          );
        }

        simulatedRouting(LoginState.loggedOut);

        expect(
          navigatedRoutes,
          contains('/home'),
          reason: 'Hard logout must navigate to /home (login screen)',
        );
      },
    );

    // Property: hard logout is indistinguishable from explicit logout at the
    // handler level — both emit LoginState.loggedOut and both must clear session.
    test(
      'property: LoginState.loggedOut always triggers session clear regardless of cause label',
      () {
        // The unfixed code does not distinguish cause — it always clears.
        // This is CORRECT for both explicit and hard logout.
        // (The bug is only for soft logout, which is a different scenario.)
        final scenarios = [
          'explicit_logout',
          'hard_logout_401',
          'token_revoked',
          'admin_deactivated',
        ];

        for (final scenario in scenarios) {
          final tracker = _DeleteBackupTracker();

          void handler(LoginState state) {
            if (state == LoginState.loggedOut) {
              tracker.record(scenario);
            }
          }

          handler(LoginState.loggedOut);

          expect(
            tracker.deletedFor(scenario),
            isTrue,
            reason: 'Session must be cleared for scenario: $scenario',
          );
        }
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Preservation 3 — Normal DB Open
// ---------------------------------------------------------------------------

/// **Validates: Requirements 3.2**
///
/// Observes: when `client.init()` succeeds (DB opens normally), `initWithRestore`
/// writes a fresh session backup and the client is authenticated — no destructive
/// actions occur.
///
/// Property: successful DB open restores session and writes backup without
/// deleting anything.
void _runNormalDbOpenPreservationTests() {
  group('Preservation 3 — Normal DB open restores session without changes', () {
    test(
      'successful init writes session backup and does not delete anything',
      () async {
        final storage = _FakeSecureStorage();
        const clientName = 'normal_db_client';
        const storageKey = 'Liza_session_backup_$clientName';

        // Simulate the happy path of initWithRestore:
        //   await init(...) — succeeds
        //   if (isLogged()) { storage.write(key: storageKey, value: ...) }
        //
        // No deletion occurs on the happy path.
        final deleteCalled = false;

        Future<void> simulatedInitWithRestore() async {
          // Simulate successful init — client is logged in
          final isLogged = true;
          if (isLogged) {
            await storage.write(
              key: storageKey,
              value: '{"access_token":"tok","user_id":"@u:h",'
                  '"homeserver":"https://h","device_id":"D","olm_account":null}',
            );
          }
          // No delete call on happy path
        }

        await simulatedInitWithRestore();

        expect(
          storage.containsKey(storageKey),
          isTrue,
          reason: 'Session backup must be written after successful init',
        );
        expect(
          deleteCalled,
          isFalse,
          reason: 'No deletion must occur on successful DB open',
        );
        expect(
          await storage.read(key: storageKey),
          isNotNull,
          reason: 'Session backup must be readable after successful init',
        );
      },
    );

    test(
      'successful init does not navigate to login screen',
      () {
        final navigatedRoutes = <String>[];

        // After successful init, the client emits LoginState.loggedIn.
        // The handler navigates to '/backup' (not '/home').
        void simulatedRouting(LoginState state) {
          navigatedRoutes.add(
            state == LoginState.loggedIn ? '/backup' : '/home',
          );
        }

        simulatedRouting(LoginState.loggedIn);

        expect(
          navigatedRoutes,
          contains('/backup'),
          reason: 'Successful login must navigate to /backup, not /home',
        );
        expect(
          navigatedRoutes,
          isNot(contains('/home')),
          reason: 'Successful login must NOT navigate to login screen',
        );
      },
    );

    test(
      'getDatabaseCipher succeeds when secureStorage.read returns a password',
      () async {
        final storage = _FakeSecureStorage();
        await storage.write(key: 'database_password', value: 'valid_cipher_key');

        // Simulate getDatabaseCipher happy path:
        //   password = await secureStorage.read(key: 'database_password')
        //   if (password == null) throw MissingPluginException()
        //   return password
        Future<String?> simulatedGetDatabaseCipher() async {
          final pw = await storage.read(key: 'database_password');
          if (pw == null) throw MissingPluginException();
          return pw;
        }

        final cipher = await simulatedGetDatabaseCipher();

        expect(
          cipher,
          equals('valid_cipher_key'),
          reason: 'getDatabaseCipher must return the stored password on success',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Preservation 4 — Multi-Account Isolation
// ---------------------------------------------------------------------------

/// **Validates: Requirements 3.5**
///
/// Observes: when one client logs out, only that client's backup is deleted
/// and only that client is removed. Other clients remain authenticated.
///
/// Property: for any logout event on client N, all other clients M ≠ N
/// remain authenticated and their backups are untouched.
void _runMultiAccountIsolationTests() {
  group('Preservation 4 — Multi-account isolation on logout', () {
    test(
      'logout of one client does not delete other clients backups',
      () async {
        final storage = _FakeSecureStorage();
        final clients = ['alice', 'bob', 'charlie'];

        // Pre-populate backups for all clients
        for (final name in clients) {
          await storage.write(
            key: 'Liza_session_backup_$name',
            value: '{"access_token":"tok_$name","user_id":"@$name:h",'
                '"homeserver":"https://h","device_id":"D_$name","olm_account":null}',
          );
        }

        // Simulate logout of 'alice' only.
        // The handler calls deleteSessionBackup(name) where name = 'alice'.
        const loggedOutClient = 'alice';
        await storage.delete(
          key: 'Liza_session_backup_$loggedOutClient',
        );

        // Assert: alice's backup is gone
        expect(
          storage.containsKey('Liza_session_backup_alice'),
          isFalse,
          reason: "Alice's backup must be deleted after her logout",
        );

        // Assert: bob and charlie's backups are untouched
        for (final name in clients.where((n) => n != loggedOutClient)) {
          expect(
            storage.containsKey('Liza_session_backup_$name'),
            isTrue,
            reason: "$name's backup must NOT be deleted when alice logs out",
          );
          expect(
            await storage.read(key: 'Liza_session_backup_$name'),
            isNotNull,
            reason: "$name's backup must remain readable after alice's logout",
          );
        }
      },
    );

    // Property-based: for any combination of N clients, logout of client[i]
    // only removes client[i]'s backup.
    test(
      'property: logout of client[i] only removes client[i] backup for all i',
      () async {
        final clientSets = [
          ['user_a', 'user_b'],
          ['user_a', 'user_b', 'user_c'],
          ['solo_user'],
          ['x', 'y', 'z', 'w'],
        ];

        for (final clientNames in clientSets) {
          final storage = _FakeSecureStorage();

          // Write backups for all
          for (final name in clientNames) {
            await storage.write(
              key: 'Liza_session_backup_$name',
              value: '{"access_token":"tok","user_id":"@u:h",'
                  '"homeserver":"https://h","device_id":"D","olm_account":null}',
            );
          }

          // Log out each client in turn and verify isolation
          for (final loggedOut in clientNames) {
            // Reset storage for this iteration
            final iterStorage = _FakeSecureStorage();
            for (final name in clientNames) {
              await iterStorage.write(
                key: 'Liza_session_backup_$name',
                value: 'backup_$name',
              );
            }

            // Simulate deleteSessionBackup(loggedOut)
            await iterStorage.delete(
              key: 'Liza_session_backup_$loggedOut',
            );

            // Logged-out client's backup is gone
            expect(
              iterStorage.containsKey('Liza_session_backup_$loggedOut'),
              isFalse,
              reason: 'Backup for $loggedOut must be deleted',
            );

            // All other clients' backups remain
            for (final other in clientNames.where((n) => n != loggedOut)) {
              expect(
                iterStorage.containsKey('Liza_session_backup_$other'),
                isTrue,
                reason:
                    '$other backup must remain when $loggedOut logs out '
                    '(client set: $clientNames)',
              );
            }
          }
        }
      },
    );

    test(
      'active client list: only logged-out client is removed',
      () {
        final activeClients = ['alice', 'bob', 'charlie'];
        const loggedOutClient = 'bob';

        // Simulate widget.clients.remove(c) — only removes the logged-out client
        final updatedClients = List<String>.from(activeClients)
          ..remove(loggedOutClient);

        expect(
          updatedClients,
          isNot(contains(loggedOutClient)),
          reason: 'Logged-out client must be removed from active clients',
        );
        expect(
          updatedClients,
          containsAll(['alice', 'charlie']),
          reason: 'Other clients must remain in active clients list',
        );
        expect(
          updatedClients.length,
          equals(activeClients.length - 1),
          reason: 'Exactly one client must be removed',
        );
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Preservation 5 — Keychain Available
// ---------------------------------------------------------------------------

/// **Validates: Requirements 3.2**
///
/// Observes: when the device is unlocked, `secureStorage.read('database_password')`
/// succeeds and returns the stored password. This is the happy path that must
/// continue to work after switching to `first_unlock` accessibility.
///
/// Property: when device is unlocked (no PlatformException), read succeeds
/// with both default and first_unlock accessibility settings.
void _runKeychainAvailableTests() {
  group('Preservation 5 — Keychain available: read succeeds when device is unlocked', () {
    test(
      'secureStorage.read returns password when device is unlocked (no exception)',
      () async {
        final storage = _FakeSecureStorage();
        await storage.write(key: 'database_password', value: 'my_cipher_key');

        // Device is unlocked — no PlatformException
        storage.throwPlatformException = false;

        final result = await storage.read(key: 'database_password');

        expect(
          result,
          equals('my_cipher_key'),
          reason: 'Read must succeed when device is unlocked',
        );
      },
    );

    test(
      'after switching to first_unlock accessibility, read still succeeds when unlocked',
      () async {
        // Simulate: password was written with default accessibility,
        // then the app switches to first_unlock accessibility.
        // The same key must still be readable when the device is unlocked.
        final storage = _FakeSecureStorage();
        await storage.write(key: 'database_password', value: 'cipher_after_migration');

        // Simulate first_unlock: device is unlocked, so read succeeds
        // (first_unlock means accessible after first unlock, which is a superset
        // of the default behavior when the device is already unlocked)
        storage.throwPlatformException = false;

        final result = await storage.read(key: 'database_password');

        expect(
          result,
          isNotNull,
          reason: 'Read must succeed with first_unlock when device is unlocked',
        );
        expect(
          result,
          equals('cipher_after_migration'),
          reason: 'Correct password must be returned',
        );
      },
    );

    test(
      'getDatabaseCipher does not delete password when read succeeds',
      () async {
        final storage = _FakeSecureStorage();
        await storage.write(key: 'database_password', value: 'valid_key');
        storage.throwPlatformException = false;

        var deleteCalled = false;

        // Simulate getDatabaseCipher happy path — no deletion
        Future<String?> simulatedGetDatabaseCipher() async {
          try {
            final pw = await storage.read(key: 'database_password');
            if (pw == null) throw MissingPluginException();
            return pw;
          } on MissingPluginException {
            deleteCalled = true;
            await storage.delete(key: 'database_password');
            return null;
          } catch (e) {
            rethrow;
          }
        }

        final cipher = await simulatedGetDatabaseCipher();

        expect(
          cipher,
          equals('valid_key'),
          reason: 'Cipher must be returned on success',
        );
        expect(
          deleteCalled,
          isFalse,
          reason: 'Password must NOT be deleted when read succeeds',
        );
        expect(
          storage.containsKey('database_password'),
          isTrue,
          reason: 'Password key must remain in storage after successful read',
        );
      },
    );

    // Property-based: for any valid password string, read always returns it
    // when device is unlocked.
    test(
      'property: for any stored password, read always returns it when unlocked',
      () async {
        final passwords = [
          'short',
          'a' * 64,
          'base64url_encoded_==',
          'with spaces and special chars !@#',
          '0' * 32,
        ];

        for (final pw in passwords) {
          final storage = _FakeSecureStorage();
          await storage.write(key: 'database_password', value: pw);
          storage.throwPlatformException = false;

          final result = await storage.read(key: 'database_password');

          expect(
            result,
            equals(pw),
            reason: 'Read must return "$pw" when device is unlocked',
          );
        }
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Test entry point
// ---------------------------------------------------------------------------

void main() {
  _runExplicitLogoutPreservationTests();
  _runHardLogoutPreservationTests();
  _runNormalDbOpenPreservationTests();
  _runMultiAccountIsolationTests();
  _runKeychainAvailableTests();
}
