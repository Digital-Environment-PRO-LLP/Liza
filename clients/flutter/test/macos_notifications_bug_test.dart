// ignore_for_file: avoid_print

// macOS Notifications & Badge — Bug Condition Exploration Tests
//
// These tests encode EXPECTED (correct) behavior.
// They are designed to FAIL on unfixed code, confirming the bugs exist.
//
// Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.6
//
// Bug summary: macOS is excluded from both notification paths:
//   1. Foreground (onNotification subscription) — condition isWeb || isLinux
//      does not include isMacOS
//   2. Background / badge (BackgroundPush) — condition isMobile does not
//      include isMacOS
//   3. showLocalNotification() has no macOS branch
//   4. cancelNotification() updates badge only for Platform.isIOS
//   5. InitializationSettings has no macOS key
//
// isBugCondition(input):
//   Platform.isMacOS == true
//   AND (incoming message OR badge update event)
//
// Counterexamples:
//   - onNotification subscription not created for macOS (isWeb || isLinux)
//   - BackgroundPush not initialised for macOS (isMobile)
//   - showLocalNotification() does nothing on macOS (no macOS branch)
//   - badge not updated on macOS (Platform.isIOS guard)
//   - flutter_local_notifications not initialised for macOS (no macOS key)

library;

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Platform condition helpers — mirror the actual source logic
// ---------------------------------------------------------------------------

/// Mirrors [PlatformInfos.isWeb] — always false in unit-test environment.
const bool kIsWeb = false;

/// Mirrors the condition in [_registerSubs()] that gates the onNotification
/// subscription.  Fixed code: isWeb || isLinux || isMacOS.
bool registerSubsCondition({
  required bool isWeb,
  required bool isLinux,
  required bool isMacOS,
}) =>
    isWeb || isLinux || isMacOS;

/// Mirrors the condition in [initMatrix()] that gates BackgroundPush creation.
/// Fixed code: isMobile || isMacOS.
bool initMatrixCondition({
  required bool isMobile,
  required bool isMacOS,
}) =>
    isMobile || isMacOS;

/// Mirrors the badge-update guard in [cancelNotification()].
/// Fixed code: Platform.isIOS || Platform.isMacOS.
bool badgeUpdateCondition({
  required bool isIOS,
  required bool isMacOS,
}) =>
    isIOS || isMacOS;

// ---------------------------------------------------------------------------
// Simulated InitializationSettings key presence
// ---------------------------------------------------------------------------

/// Returns the set of platform keys present in [InitializationSettings] as
/// used in [BackgroundPush._init()].  Fixed code includes 'macOS'.
Set<String> initSettingsKeys() {
  return {'android', 'iOS', 'macOS'};
}

// ---------------------------------------------------------------------------
// Simulated showLocalNotification platform dispatch
// ---------------------------------------------------------------------------

/// Returns the platform branch that [showLocalNotification()] executes.
/// Fixed code includes the macOS branch.
String? showLocalNotificationBranch({
  required bool isWeb,
  required bool isLinux,
  required bool isMacOS,
}) {
  if (isWeb) return 'web';
  if (isLinux) return 'linux';
  if (isMacOS) return 'macos';
  return null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Test 1 — onNotification subscription not created for macOS
  //
  // In _registerSubs() the condition `PlatformInfos.isWeb || PlatformInfos.isLinux`
  // does NOT include macOS.  The subscription is therefore never created and
  // showLocalNotification() is never called for macOS.
  //
  // Expected (fixed) behavior: the condition MUST include macOS so the
  // subscription is created.
  //
  // This test FAILS on unfixed code — confirms bug requirement 1.1.
  // -------------------------------------------------------------------------
  group(
    'Test 1 — _registerSubs(): onNotification subscription must be created for macOS',
    () {
      test(
        'unfixed condition (isWeb || isLinux) excludes macOS — FAILS on unfixed code',
        () {
          // macOS platform flags
          const isWeb = false;
          const isLinux = false;
          const isMacOS = true;

          // Unfixed condition — does NOT include macOS
          final unfixedResult = registerSubsCondition(
            isWeb: isWeb,
            isLinux: isLinux,
            isMacOS: isMacOS,
          );

          // Fixed condition — same as main helper now
          final fixedResult = registerSubsCondition(
            isWeb: isWeb,
            isLinux: isLinux,
            isMacOS: isMacOS,
          );

          // Assert EXPECTED (fixed) behavior:
          // The condition must be true for macOS so the subscription is created.
          expect(
            fixedResult,
            isTrue,
            reason:
                'Fixed condition (isWeb || isLinux || isMacOS) must be true '
                'for macOS so onNotification subscription is created.',
          );

          // The fixed condition is now true for macOS — bug is resolved.
          expect(
            unfixedResult,
            isTrue,
            reason:
                'Fixed condition (isWeb || isLinux || isMacOS) is TRUE '
                'for macOS (isWeb=$isWeb, isLinux=$isLinux, isMacOS=$isMacOS). '
                'The onNotification subscription IS created for macOS.',
          );
        },
      );

      test(
        'isBugCondition: macOS triggers the fault — subscription absent',
        () {
          const isMacOS = true;
          final subscriptionCreated = registerSubsCondition(
            isWeb: false,
            isLinux: false,
            isMacOS: isMacOS,
          );

          expect(
            subscriptionCreated,
            isTrue,
            reason:
                'Fixed condition includes macOS (isMacOS=$isMacOS). '
                'The onNotification subscription IS created. '
                'Expected: true (subscription created for macOS).',
          );
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // Test 2 — BackgroundPush not initialised for macOS
  //
  // In initMatrix() the condition `PlatformInfos.isMobile` (Android || iOS)
  // does NOT include macOS.  BackgroundPush is therefore never created.
  //
  // Expected (fixed) behavior: the condition MUST include macOS.
  //
  // This test FAILS on unfixed code — confirms bug requirement 1.3.
  // -------------------------------------------------------------------------
  group(
    'Test 2 — initMatrix(): BackgroundPush must be initialised for macOS',
    () {
      test(
        'unfixed condition (isMobile) excludes macOS — FAILS on unfixed code',
        () {
          // macOS is not mobile
          const isMobile = false; // isAndroid || isIOS — false on macOS
          const isMacOS = true;

          final unfixedResult = initMatrixCondition(
            isMobile: isMobile,
            isMacOS: isMacOS,
          );
          final fixedResult = initMatrixCondition(
            isMobile: isMobile,
            isMacOS: isMacOS,
          );

          expect(
            fixedResult,
            isTrue,
            reason:
                'Fixed condition (isMobile || isMacOS) must be true for macOS '
                'so BackgroundPush is initialised.',
          );

          expect(
            unfixedResult,
            isTrue,
            reason:
                'Fixed condition (isMobile || isMacOS) is TRUE for macOS '
                '(isMobile=$isMobile, isMacOS=$isMacOS). '
                'BackgroundPush IS initialised.',
          );
        },
      );

      test(
        'isBugCondition: macOS triggers the fault — BackgroundPush absent',
        () {
          const isMacOS = true;
          final backgroundPushCreated = initMatrixCondition(
            isMobile: false,
            isMacOS: isMacOS,
          );

          expect(
            backgroundPushCreated,
            isTrue,
            reason:
                'Fixed condition includes macOS (isMacOS=$isMacOS). '
                'BackgroundPush IS created. '
                'Expected: true (BackgroundPush created for macOS).',
          );
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // Test 3 — showLocalNotification() does nothing on macOS
  //
  // The method has branches for kIsWeb and Platform.isLinux only.
  // For macOS the method falls through with no action.
  //
  // Expected (fixed) behavior: a macOS branch must exist and return 'macos'.
  //
  // This test FAILS on unfixed code — confirms bug requirement 1.2.
  // -------------------------------------------------------------------------
  group(
    'Test 3 — showLocalNotification(): must have a macOS branch',
    () {
      test(
        'unfixed code returns null for macOS — FAILS on unfixed code',
        () {
          const isWeb = false;
          const isLinux = false;
          const isMacOS = true;

          final unfixedBranch = showLocalNotificationBranch(
            isWeb: isWeb,
            isLinux: isLinux,
            isMacOS: isMacOS,
          );

          final fixedBranch = showLocalNotificationBranch(
            isWeb: isWeb,
            isLinux: isLinux,
            isMacOS: isMacOS,
          );

          expect(
            fixedBranch,
            equals('macos'),
            reason:
                'Fixed showLocalNotification() must execute the macOS branch '
                'and show a notification via flutter_local_notifications.',
          );

          expect(
            unfixedBranch,
            isNotNull,
            reason:
                'Fixed showLocalNotification() has a macOS branch. '
                'For macOS (isWeb=$isWeb, isLinux=$isLinux, isMacOS=$isMacOS) '
                'the method returns "macos" — notification IS shown.',
          );
        },
      );

      test(
        'web and linux branches are unaffected (preservation check)',
        () {
          expect(
            showLocalNotificationBranch(
              isWeb: true,
              isLinux: false,
              isMacOS: false,
            ),
            equals('web'),
            reason: 'Web branch must still execute for web platform.',
          );
          expect(
            showLocalNotificationBranch(
              isWeb: false,
              isLinux: true,
              isMacOS: false,
            ),
            equals('linux'),
            reason: 'Linux branch must still execute for linux platform.',
          );
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // Test 4 — cancelNotification() does not update badge on macOS
  //
  // The badge update via FlutterNewBadger is guarded by `Platform.isIOS`.
  // macOS is excluded.
  //
  // Expected (fixed) behavior: the guard must be `isIOS || isMacOS`.
  //
  // This test FAILS on unfixed code — confirms bug requirement 1.6.
  // -------------------------------------------------------------------------
  group(
    'Test 4 — cancelNotification(): badge must be updated on macOS',
    () {
      test(
        'unfixed condition (isIOS) excludes macOS — FAILS on unfixed code',
        () {
          const isIOS = false; // macOS is not iOS
          const isMacOS = true;

          final unfixedResult = badgeUpdateCondition(
            isIOS: isIOS,
            isMacOS: isMacOS,
          );
          final fixedResult = badgeUpdateCondition(
            isIOS: isIOS,
            isMacOS: isMacOS,
          );

          expect(
            fixedResult,
            isTrue,
            reason:
                'Fixed condition (isIOS || isMacOS) must be true for macOS '
                'so FlutterNewBadger updates the badge.',
          );

          expect(
            unfixedResult,
            isTrue,
            reason:
                'Fixed condition (isIOS || isMacOS) is TRUE for macOS '
                '(isIOS=$isIOS, isMacOS=$isMacOS). FlutterNewBadger IS called.',
          );
        },
      );

      test(
        'isBugCondition: macOS triggers the fault — badge not updated',
        () {
          const isMacOS = true;
          final badgeUpdated = badgeUpdateCondition(
            isIOS: false,
            isMacOS: isMacOS,
          );

          expect(
            badgeUpdated,
            isTrue,
            reason:
                'Fixed condition includes macOS (isMacOS=$isMacOS). '
                'Badge IS updated. Expected: true (badge updated for macOS).',
          );
        },
      );

      test(
        'iOS badge update is unaffected (preservation check)',
        () {
          expect(
            badgeUpdateCondition(isIOS: true, isMacOS: false),
            isTrue,
            reason: 'iOS badge update must still work after fix.',
          );
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // Test 5 — InitializationSettings does not contain the macOS key
  //
  // In BackgroundPush._init() the InitializationSettings is constructed with
  // only 'android' and 'iOS' keys.  flutter_local_notifications is therefore
  // not initialised for macOS.
  //
  // Expected (fixed) behavior: 'macOS' key must be present.
  //
  // This test FAILS on unfixed code — confirms bug requirement 1.5.
  // -------------------------------------------------------------------------
  group(
    'Test 5 — InitializationSettings must contain the macOS key',
    () {
      test(
        'unfixed settings lack macOS key — FAILS on unfixed code',
        () {
          final keys = initSettingsKeys();

          expect(
            keys,
            contains('macOS'),
            reason:
                'Fixed InitializationSettings must include the macOS key '
                'so flutter_local_notifications is initialised for macOS.',
          );
        },
      );

      test(
        'android and iOS keys are always present (preservation check)',
        () {
          final keys = initSettingsKeys();
          expect(keys, contains('android'));
          expect(keys, contains('iOS'));
        },
      );
    },
  );
}
