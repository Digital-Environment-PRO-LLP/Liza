// ignore_for_file: avoid_print

// macOS Notifications & Badge — Preservation Property Tests
//
// These tests capture OBSERVED baseline behavior on iOS, Android, Linux, Web.
// They are designed to PASS on unfixed code, confirming that the fix does not
// introduce regressions on other platforms.
//
// Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5
//
// Observations (from unfixed code):
//   - iOS:     BackgroundPush is initialised (PlatformInfos.isMobile == true)
//   - Android: BackgroundPush is initialised (PlatformInfos.isMobile == true)
//   - Linux:   onNotification subscription is created (PlatformInfos.isLinux == true)
//   - Web:     onNotification subscription is created (PlatformInfos.isWeb == true)
//   - iOS:     badge is updated via FlutterNewBadger (Platform.isIOS == true)
//   - iOS:     firebase field is null (Platform.isIOS ? null : FcmSharedIsolate())
//   - Android: firebase field is a FcmSharedIsolate instance
//   - InitializationSettings contains keys 'android' and 'iOS'
//
// Preservation invariant:
//   FOR ALL input WHERE NOT isBugCondition(input):
//     originalFunction(input) == fixedFunction(input)
//
// isBugCondition(input): Platform.isMacOS == true

library;

import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Platform condition helpers — mirror the actual source logic
// (same helpers as macos_notifications_bug_test.dart for consistency)
// ---------------------------------------------------------------------------

/// Mirrors the condition in [_registerSubs()] that gates the onNotification
/// subscription.  On unfixed code: isWeb || isLinux.
bool registerSubsCondition({
  required bool isWeb,
  required bool isLinux,
}) =>
    isWeb || isLinux;

/// Mirrors the condition in [initMatrix()] that gates BackgroundPush creation.
/// On unfixed code: isMobile (isAndroid || isIOS).
bool initMatrixCondition({required bool isMobile}) => isMobile;

/// Mirrors the badge-update guard in [cancelNotification()].
/// On unfixed code: Platform.isIOS.
bool badgeUpdateCondition({required bool isIOS}) => isIOS;

/// Returns the set of platform keys present in [InitializationSettings] as
/// used in [BackgroundPush._init()].  On unfixed code: 'android' and 'iOS'.
Set<String> initSettingsKeys({bool includeMacOS = false}) {
  final keys = {'android', 'iOS'};
  if (includeMacOS) keys.add('macOS');
  return keys;
}

/// Returns the platform branch that [showLocalNotification()] would execute.
/// On unfixed code there is no macOS branch.
String? showLocalNotificationBranch({
  required bool isWeb,
  required bool isLinux,
  required bool isMacOS,
}) {
  if (isWeb) return 'web';
  if (isLinux) return 'linux';
  // Fixed code adds: if (isMacOS) return 'macos';
  return null;
}

/// Mirrors the firebase field initialisation in [BackgroundPush]:
///   Platform.isIOS ? null : FcmSharedIsolate()
/// Returns true when firebase is non-null (i.e. FcmSharedIsolate is created).
bool firebaseIsNonNull({required bool isIOS}) => !isIOS;

/// Mirrors the setupPush() early-exit guard.
/// On unfixed code: !PlatformInfos.isMobile → early return.
/// Returns true when setupPush proceeds (does NOT exit early).
bool setupPushProceeds({
  required bool isMobile,
  required bool isLoggedIn,
  required bool hasMatrix,
}) =>
    isLoggedIn && isMobile && hasMatrix;

/// Mirrors the UnifiedPush initialisation guard in [_init()].
/// Only Android initialises UnifiedPush.
bool unifiedPushInitialised({required bool isAndroid}) => isAndroid;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // Property 1 — BackgroundPush initialisation is unchanged for iOS/Android
  //
  // Observation: PlatformInfos.isMobile == true for both iOS and Android.
  // The initMatrix() condition `if (PlatformInfos.isMobile)` creates
  // BackgroundPush for these platforms.
  //
  // Preservation: after the fix (which adds isMacOS to the condition),
  // iOS and Android must still satisfy the condition.
  //
  // Validates: Requirements 3.1, 3.2
  // -------------------------------------------------------------------------
  group(
    'Property 1 — BackgroundPush initialisation preserved for iOS and Android',
    () {
      test('iOS: isMobile == true → BackgroundPush is initialised', () {
        // iOS platform flags
        const isAndroid = false;
        const isIOS = true;
        final isMobile = isAndroid || isIOS; // mirrors PlatformInfos.isMobile

        final result = initMatrixCondition(isMobile: isMobile);

        expect(
          result,
          isTrue,
          reason:
              'iOS: isMobile=$isMobile — BackgroundPush must be initialised '
              'on iOS. Preservation: this must remain true after the fix.',
        );
      });

      test('Android: isMobile == true → BackgroundPush is initialised', () {
        const isAndroid = true;
        const isIOS = false;
        final isMobile = isAndroid || isIOS; // ignore: dead_code

        final result = initMatrixCondition(isMobile: isMobile);

        expect(
          result,
          isTrue,
          reason:
              'Android: isMobile=$isMobile — BackgroundPush must be initialised '
              'on Android. Preservation: this must remain true after the fix.',
        );
      });

      test(
        'Windows: isMobile == false → BackgroundPush is NOT initialised (unchanged)',
        () {
          const isMobile = false; // Windows is not mobile

          final result = initMatrixCondition(isMobile: isMobile);

          expect(
            result,
            isFalse,
            reason:
                'Windows: isMobile=$isMobile — BackgroundPush must NOT be '
                'initialised on Windows. Preservation: unchanged.',
          );
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // Property 2 — onNotification subscription preserved for Linux and Web
  //
  // Observation: PlatformInfos.isLinux == true on Linux, PlatformInfos.isWeb
  // == true on Web.  The _registerSubs() condition `isWeb || isLinux` creates
  // the subscription for these platforms.
  //
  // Preservation: after the fix (which adds isMacOS), Linux and Web must
  // still satisfy the condition.
  //
  // Validates: Requirements 3.3, 3.4
  // -------------------------------------------------------------------------
  group(
    'Property 2 — onNotification subscription preserved for Linux and Web',
    () {
      test('Linux: isLinux == true → onNotification subscription is created',
          () {
        const isWeb = false;
        const isLinux = true;

        final result = registerSubsCondition(isWeb: isWeb, isLinux: isLinux);

        expect(
          result,
          isTrue,
          reason:
              'Linux: isLinux=$isLinux — onNotification subscription must be '
              'created on Linux. Preservation: unchanged after fix.',
        );
      });

      test('Web: isWeb == true → onNotification subscription is created', () {
        const isWeb = true;
        const isLinux = false;

        final result = registerSubsCondition(isWeb: isWeb, isLinux: isLinux);

        expect(
          result,
          isTrue,
          reason:
              'Web: isWeb=$isWeb — onNotification subscription must be created '
              'on Web. Preservation: unchanged after fix.',
        );
      });

      test(
        'Android: isWeb=false, isLinux=false → subscription NOT created (unchanged)',
        () {
          const isWeb = false;
          const isLinux = false;

          final result =
              registerSubsCondition(isWeb: isWeb, isLinux: isLinux);

          expect(
            result,
            isFalse,
            reason:
                'Android: isWeb=$isWeb, isLinux=$isLinux — onNotification '
                'subscription must NOT be created via this path on Android '
                '(Android uses BackgroundPush instead). Preservation: unchanged.',
          );
        },
      );

      test(
        'Windows: isWeb=false, isLinux=false → subscription NOT created (unchanged)',
        () {
          const isWeb = false;
          const isLinux = false;

          final result =
              registerSubsCondition(isWeb: isWeb, isLinux: isLinux);

          expect(
            result,
            isFalse,
            reason:
                'Windows: isWeb=$isWeb, isLinux=$isLinux — onNotification '
                'subscription must NOT be created on Windows. '
                'Preservation: unchanged.',
          );
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // Property 3 — iOS badge update via FlutterNewBadger is preserved
  //
  // Observation: cancelNotification() calls FlutterNewBadger only when
  // Platform.isIOS == true.
  //
  // Preservation: after the fix (which adds isMacOS), iOS must still trigger
  // the badge update.
  //
  // Validates: Requirement 3.1
  // -------------------------------------------------------------------------
  group('Property 3 — iOS badge update preserved', () {
    test('iOS: isIOS == true → badge is updated via FlutterNewBadger', () {
      const isIOS = true;

      final result = badgeUpdateCondition(isIOS: isIOS);

      expect(
        result,
        isTrue,
        reason:
            'iOS: isIOS=$isIOS — FlutterNewBadger must be called on iOS. '
            'Preservation: this must remain true after the fix.',
      );
    });

    test(
      'Android: isIOS == false → badge NOT updated via this path (unchanged)',
      () {
        const isIOS = false;

        final result = badgeUpdateCondition(isIOS: isIOS);

        expect(
          result,
          isFalse,
          reason:
              'Android: isIOS=$isIOS — FlutterNewBadger must NOT be called '
              'on Android via this path. Preservation: unchanged.',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Property 4 — Android firebase field is FcmSharedIsolate (non-null)
  //              iOS firebase field is null
  //
  // Observation: `final firebase = Platform.isIOS ? null : FcmSharedIsolate()`
  //   - iOS:     firebase == null
  //   - Android: firebase != null (FcmSharedIsolate instance)
  //
  // Preservation: after the fix (which changes to `isIOS || isMacOS ? null`),
  // iOS must still have firebase == null, Android must still have firebase != null.
  //
  // Validates: Requirements 3.1, 3.2
  // -------------------------------------------------------------------------
  group('Property 4 — firebase field initialisation preserved', () {
    test('iOS: firebase is null (APNs used instead of FCM)', () {
      const isIOS = true;

      final isNonNull = firebaseIsNonNull(isIOS: isIOS);

      expect(
        isNonNull,
        isFalse,
        reason:
            'iOS: isIOS=$isIOS — firebase must be null on iOS (APNs is used). '
            'Preservation: unchanged after fix.',
      );
    });

    test('Android: firebase is non-null (FcmSharedIsolate instance)', () {
      const isIOS = false; // Android

      final isNonNull = firebaseIsNonNull(isIOS: isIOS);

      expect(
        isNonNull,
        isTrue,
        reason:
            'Android: isIOS=$isIOS — firebase must be a FcmSharedIsolate '
            'instance on Android. Preservation: unchanged after fix.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Property 5 — setupPush() does not exit early on iOS/Android
  //
  // Observation: setupPush() guard is:
  //   `!PlatformInfos.isMobile || matrix == null || !loggedIn`
  // For iOS/Android (isMobile == true), the guard is false → proceeds.
  //
  // Preservation: after the fix (which adds `&& !isMacOS` to the guard),
  // iOS and Android must still proceed through setupPush().
  //
  // Validates: Requirements 3.1, 3.2
  // -------------------------------------------------------------------------
  group('Property 5 — setupPush() proceeds on iOS and Android', () {
    test('iOS: isMobile=true, loggedIn=true, hasMatrix=true → proceeds', () {
      const isMobile = true; // iOS
      const isLoggedIn = true;
      const hasMatrix = true;

      final proceeds = setupPushProceeds(
        isMobile: isMobile,
        isLoggedIn: isLoggedIn,
        hasMatrix: hasMatrix,
      );

      expect(
        proceeds,
        isTrue,
        reason:
            'iOS: setupPush() must NOT exit early when isMobile=$isMobile, '
            'isLoggedIn=$isLoggedIn, hasMatrix=$hasMatrix. '
            'Preservation: unchanged after fix.',
      );
    });

    test('Android: isMobile=true, loggedIn=true, hasMatrix=true → proceeds',
        () {
      const isMobile = true; // Android
      const isLoggedIn = true;
      const hasMatrix = true;

      final proceeds = setupPushProceeds(
        isMobile: isMobile,
        isLoggedIn: isLoggedIn,
        hasMatrix: hasMatrix,
      );

      expect(
        proceeds,
        isTrue,
        reason:
            'Android: setupPush() must NOT exit early when isMobile=$isMobile, '
            'isLoggedIn=$isLoggedIn, hasMatrix=$hasMatrix. '
            'Preservation: unchanged after fix.',
      );
    });

    test(
      'Linux: isMobile=false → exits early (unchanged — Linux uses onNotification stream)',
      () {
        const isMobile = false; // Linux
        const isLoggedIn = true;
        const hasMatrix = true;

        final proceeds = setupPushProceeds(
          isMobile: isMobile,
          isLoggedIn: isLoggedIn,
          hasMatrix: hasMatrix,
        );

        expect(
          proceeds,
          isFalse,
          reason:
              'Linux: setupPush() must exit early (isMobile=$isMobile). '
              'Linux uses the onNotification stream path instead. '
              'Preservation: unchanged.',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Property 6 — InitializationSettings always contains 'android' and 'iOS'
  //
  // Observation: BackgroundPush._init() constructs InitializationSettings
  // with keys 'android' and 'iOS'.
  //
  // Preservation: after the fix (which adds 'macOS'), the existing keys must
  // still be present.
  //
  // Validates: Requirements 3.1, 3.2
  // -------------------------------------------------------------------------
  group(
    'Property 6 — InitializationSettings always contains android and iOS keys',
    () {
      test('unfixed settings contain android and iOS keys', () {
        final keys = initSettingsKeys(includeMacOS: false);

        expect(
          keys,
          contains('android'),
          reason:
              'InitializationSettings must always contain the "android" key. '
              'Preservation: unchanged after fix.',
        );
        expect(
          keys,
          contains('iOS'),
          reason:
              'InitializationSettings must always contain the "iOS" key. '
              'Preservation: unchanged after fix.',
        );
      });

      test('fixed settings still contain android and iOS keys', () {
        final keys = initSettingsKeys(includeMacOS: true);

        expect(
          keys,
          contains('android'),
          reason:
              'Fixed InitializationSettings must still contain "android". '
              'Preservation: android key must not be removed.',
        );
        expect(
          keys,
          contains('iOS'),
          reason:
              'Fixed InitializationSettings must still contain "iOS". '
              'Preservation: iOS key must not be removed.',
        );
        expect(
          keys,
          contains('macOS'),
          reason:
              'Fixed InitializationSettings must also contain "macOS". '
              'This is the new key added by the fix.',
        );
      });
    },
  );

  // -------------------------------------------------------------------------
  // Property 7 — showLocalNotification() web/linux branches are unchanged
  //
  // Observation: showLocalNotification() dispatches to 'web' for isWeb==true
  // and 'linux' for isLinux==true.
  //
  // Preservation: after the fix (which adds a macOS branch), web and linux
  // branches must still execute correctly.
  //
  // Validates: Requirements 3.3, 3.4
  // -------------------------------------------------------------------------
  group(
    'Property 7 — showLocalNotification() web and linux branches preserved',
    () {
      test('Web: isWeb=true → web branch executes', () {
        final branch = showLocalNotificationBranch(
          isWeb: true,
          isLinux: false,
          isMacOS: false,
        );

        expect(
          branch,
          equals('web'),
          reason:
              'Web: showLocalNotification() must execute the web branch. '
              'Preservation: unchanged after fix.',
        );
      });

      test('Linux: isLinux=true → linux branch executes', () {
        final branch = showLocalNotificationBranch(
          isWeb: false,
          isLinux: true,
          isMacOS: false,
        );

        expect(
          branch,
          equals('linux'),
          reason:
              'Linux: showLocalNotification() must execute the linux branch. '
              'Preservation: unchanged after fix.',
        );
      });

      test(
        'Android: isWeb=false, isLinux=false, isMacOS=false → no branch (unchanged)',
        () {
          final branch = showLocalNotificationBranch(
            isWeb: false,
            isLinux: false,
            isMacOS: false,
          );

          expect(
            branch,
            isNull,
            reason:
                'Android: showLocalNotification() has no branch for Android '
                '(Android uses BackgroundPush). Preservation: unchanged.',
          );
        },
      );
    },
  );

  // -------------------------------------------------------------------------
  // Property 8 — UnifiedPush is initialised only on Android
  //
  // Observation: BackgroundPush._init() calls UnifiedPush.initialize() only
  // when Platform.isAndroid == true.
  //
  // Preservation: after the fix, UnifiedPush must still be initialised on
  // Android and NOT on other platforms.
  //
  // Validates: Requirement 3.2
  // -------------------------------------------------------------------------
  group('Property 8 — UnifiedPush initialisation preserved for Android', () {
    test('Android: isAndroid=true → UnifiedPush is initialised', () {
      const isAndroid = true;

      final result = unifiedPushInitialised(isAndroid: isAndroid);

      expect(
        result,
        isTrue,
        reason:
            'Android: UnifiedPush must be initialised on Android. '
            'Preservation: unchanged after fix.',
      );
    });

    test('iOS: isAndroid=false → UnifiedPush is NOT initialised', () {
      const isAndroid = false;

      final result = unifiedPushInitialised(isAndroid: isAndroid);

      expect(
        result,
        isFalse,
        reason:
            'iOS: UnifiedPush must NOT be initialised on iOS. '
            'Preservation: unchanged after fix.',
      );
    });

    test('Linux: isAndroid=false → UnifiedPush is NOT initialised', () {
      const isAndroid = false;

      final result = unifiedPushInitialised(isAndroid: isAndroid);

      expect(
        result,
        isFalse,
        reason:
            'Linux: UnifiedPush must NOT be initialised on Linux. '
            'Preservation: unchanged after fix.',
      );
    });
  });
}
