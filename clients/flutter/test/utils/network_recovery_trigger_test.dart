library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liza/utils/network_recovery_trigger.dart';

void main() {
  group('NetworkRecoveryTrigger', () {
    late StreamController<List<ConnectivityResult>> controller;
    late int refreshCalls;

    NetworkRecoveryTrigger build({required bool isMobile}) {
      return NetworkRecoveryTrigger(
        stream: controller.stream,
        onRefresh: () => refreshCalls++,
        isMobile: isMobile,
        debounce: const Duration(milliseconds: 1500),
      );
    }

    setUp(() {
      controller = StreamController<List<ConnectivityResult>>.broadcast();
      refreshCalls = 0;
    });

    tearDown(() {
      controller.close();
    });

    test('offline -> online на mobile вызывает refresh один раз', () {
      fakeAsync((async) {
        final t = build(isMobile: true)..start();
        controller.add([ConnectivityResult.none]);
        async.flushMicrotasks();
        controller.add([ConnectivityResult.wifi]);
        async.elapse(const Duration(seconds: 2));
        expect(refreshCalls, 1);
        t.dispose();
      });
    });

    test('на desktop/macOS refresh не вызывается вовсе', () {
      fakeAsync((async) {
        final t = build(isMobile: false)..start();
        controller.add([ConnectivityResult.none]);
        controller.add([ConnectivityResult.wifi]);
        async.elapse(const Duration(seconds: 2));
        expect(refreshCalls, 0);
        t.dispose();
      });
    });

    test('дебаунс: пачка событий при переключении -> один refresh', () {
      fakeAsync((async) {
        final t = build(isMobile: true)..start();
        controller.add([ConnectivityResult.none]);
        // Быстрая пачка (переключение Wi-Fi -> LTE сыпет несколькими событиями).
        controller.add([ConnectivityResult.mobile]);
        async.elapse(const Duration(milliseconds: 200));
        controller.add([ConnectivityResult.none]);
        async.elapse(const Duration(milliseconds: 200));
        controller.add([ConnectivityResult.mobile]);
        async.elapse(const Duration(seconds: 2));
        expect(refreshCalls, 1);
        t.dispose();
      });
    });

    test('смена транспорта wifi -> mobile (без промежуточного none) -> refresh', () {
      fakeAsync((async) {
        final t = build(isMobile: true)..start();
        controller.add([ConnectivityResult.wifi]);
        async.elapse(const Duration(seconds: 2));
        // wifi уже посчитан как online, refresh на первом online не нужен —
        // клиент только что жил. Считается только ПЕРЕХОД в online.
        expect(refreshCalls, 0);
        controller.add([ConnectivityResult.mobile]);
        async.elapse(const Duration(seconds: 2));
        // Смена активного транспорта = новые сокеты, старые мертвы -> refresh.
        expect(refreshCalls, 1);
        t.dispose();
      });
    });

    test('стабильный online без смены транспорта -> без лишних refresh', () {
      fakeAsync((async) {
        final t = build(isMobile: true)..start();
        controller.add([ConnectivityResult.wifi]);
        async.elapse(const Duration(seconds: 2));
        controller.add([ConnectivityResult.wifi]);
        async.elapse(const Duration(seconds: 2));
        expect(refreshCalls, 0);
        t.dispose();
      });
    });

    test('dispose останавливает реакцию на события', () {
      fakeAsync((async) {
        final t = build(isMobile: true)..start();
        controller.add([ConnectivityResult.none]);
        t.dispose();
        controller.add([ConnectivityResult.wifi]);
        async.elapse(const Duration(seconds: 2));
        expect(refreshCalls, 0);
      });
    });
  });
}
