import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:liza/utils/device_capability_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DeviceCapabilityService', () {
    test('sends PUT request with platform and build on first call', () async {
      final calls = <Map<String, dynamic>>[];
      final service = DeviceCapabilityService(
        putCapability: (deviceId, platform, build) async {
          calls.add({'deviceId': deviceId, 'platform': platform, 'build': build});
          return true;
        },
        resolvePlatform: () => 'android',
        resolveBuild: () async => 3675,
        prefs: await SharedPreferences.getInstance(),
      );

      await service.reportIfNeeded(deviceId: 'DEVICE1');

      expect(calls, [
        {'deviceId': 'DEVICE1', 'platform': 'android', 'build': 3675},
      ]);
    });

    test('does not resend when platform/build unchanged from last success', () async {
      final calls = <Map<String, dynamic>>[];
      final prefs = await SharedPreferences.getInstance();
      final service = DeviceCapabilityService(
        putCapability: (deviceId, platform, build) async {
          calls.add({'deviceId': deviceId, 'platform': platform, 'build': build});
          return true;
        },
        resolvePlatform: () => 'android',
        resolveBuild: () async => 3675,
        prefs: prefs,
      );

      await service.reportIfNeeded(deviceId: 'DEVICE1');
      await service.reportIfNeeded(deviceId: 'DEVICE1');

      expect(calls.length, 1);
    });

    test('resends when build increases', () async {
      final calls = <int>[];
      final prefs = await SharedPreferences.getInstance();
      var build = 3675;
      final service = DeviceCapabilityService(
        putCapability: (deviceId, platform, b) async {
          calls.add(b);
          return true;
        },
        resolvePlatform: () => 'android',
        resolveBuild: () async => build,
        prefs: prefs,
      );

      await service.reportIfNeeded(deviceId: 'DEVICE1');
      build = 3680;
      await service.reportIfNeeded(deviceId: 'DEVICE1');

      expect(calls, [3675, 3680]);
    });

    test('does not update marker when PUT fails (fail-open, retry next time)', () async {
      var callCount = 0;
      final prefs = await SharedPreferences.getInstance();
      final service = DeviceCapabilityService(
        putCapability: (deviceId, platform, build) async {
          callCount++;
          throw Exception('network error');
        },
        resolvePlatform: () => 'android',
        resolveBuild: () async => 3675,
        prefs: prefs,
      );

      await service.reportIfNeeded(deviceId: 'DEVICE1'); // не должно throw наружу
      await service.reportIfNeeded(deviceId: 'DEVICE1');

      expect(callCount, 2); // обе попытки реально ушли, маркер не выставился
    });

    test('skips sending when build is unresolvable (e.g. Web)', () async {
      final calls = <int>[];
      final prefs = await SharedPreferences.getInstance();
      final service = DeviceCapabilityService(
        putCapability: (deviceId, platform, build) async {
          calls.add(build);
          return true;
        },
        resolvePlatform: () => 'web',
        resolveBuild: () async => null,
        prefs: prefs,
      );

      await service.reportIfNeeded(deviceId: 'DEVICE1');

      expect(calls, isEmpty);
    });
  });
}
