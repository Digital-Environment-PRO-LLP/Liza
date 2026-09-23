// ignore_for_file: depend_on_referenced_packages

// Страж RL-badge-mismatch-signal (дополнение 2026-09-08): read-back бейджа НЕ
// имеет права рапортовать расхождение, если между замером и чтением бейдж
// переписал ДРУГОЙ писатель, и обязан молчать, пока запись вообще проглочена.
//
// Прод-факт 2026-09-08: issue `[badge-mismatch] platform=ios` — 224 события,
// живых. Разбор payload'ов: delta==1 в 225/260 случаев, пары expected/shown —
// ВСЕГДА соседние целые, а у одного пользователя расхождение ходило в ОБЕ
// стороны за день (0→1, 1→2, 2→1, 1→0). Залипший бейдж односторонен и монотонен;
// двунаправленный лаг ±1 — подпись гонки, а не дефекта. Писателей бейджа ≥4
// (onSync-подписка на КАЖДЫЙ клиент, resume, push_helper, cancelNotification —
// последний намеренно пишет N−1), все fire-and-forget и без общего гарда.
//
// ledger:RL-badge-mismatch-signal

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:liza/utils/app_badge.dart';

const _badgerChannel = MethodChannel('flutter_new_badger');
const _apnsChannel = MethodChannel('com.prodamus.laba.liza/apns');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> calls;

  void mockBadger({bool denied = false}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_badgerChannel, (call) async {
      calls.add(call.method);
      if (denied) {
        throw PlatformException(code: 'PERMISSION_DENIED');
      }
      return null;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_apnsChannel, (call) async => true);
  }

  setUp(() {
    calls = [];
    AppBadge.resetDenied();
    AppBadge.markPermissionRequested();
  });

  test('AC-11: успешная запись двигает writeSeq (монотонно)', () async {
    // Счётчик — единственный признак, по которому измеряющая сторона отличает
    // «бейдж залип» от «нас обогнал другой писатель».
    mockBadger();
    final before = AppBadge.writeSeq;
    await AppBadge.trySet(3);
    await AppBadge.trySet(4);
    expect(AppBadge.writeSeq, before + 2);
  });

  test('AC-12: проглоченная запись writeSeq НЕ двигает', () async {
    // RED-PROOF: если бы seq рос и при отказе платформы, гард стал бы
    // тавтологичным «всегда обогнали» и детектор ослеп бы полностью.
    mockBadger(denied: true);
    final before = AppBadge.writeSeq;
    await AppBadge.trySet(3);
    expect(AppBadge.writeSeq, before);
    expect(AppBadge.isDenied, isTrue);
  });

  test('AC-13: isWriteSuppressed истинен при отказе платформы', () async {
    mockBadger(denied: true);
    expect(AppBadge.isWriteSuppressed, isFalse);
    await AppBadge.trySet(3);
    expect(AppBadge.isWriteSuppressed, isTrue);
  });

  test('AC-14: до permission-латча на iOS запись проглочена — ∀ комбинации', () {
    // Дыра контракта, дававшая гарантированный ложняк на холодном старте:
    // trySet выходит молча, а `_denied` остаётся false — прежний гард
    // (`isDenied`) пропускал read-back, и тот сравнивал Dart-счёт с числом,
    // оставленным NSE. Это доминирующая пара iOS (0,1) ×88 в проде.
    // Проверяем предикат на ВСЕХ восьми комбинациях: host-VM идёт на macOS, где
    // `Platform.isIOS == false`, поэтому через геттер ветка iOS непокрываема.
    bool suppressed(bool denied, bool isIOS, bool done) =>
        AppBadge.writeSuppressed(
            denied: denied, isIOS: isIOS, permissionFlowDone: done);

    // iOS до латча — подавлено независимо от denied (главный кейс).
    expect(suppressed(false, true, false), isTrue);
    expect(suppressed(true, true, false), isTrue);
    // iOS после латча — подавлено ТОЛЬКО при отказе платформы.
    expect(suppressed(false, true, true), isFalse);
    expect(suppressed(true, true, true), isTrue);
    // Не-iOS: латча нет вовсе, решает только denied (red-proof: предикат не
    // вырожден в «всегда true» — иначе детектор ослеп бы на всех платформах).
    expect(suppressed(false, false, false), isFalse);
    expect(suppressed(false, false, true), isFalse);
    expect(suppressed(true, false, false), isTrue);
    expect(suppressed(true, false, true), isTrue);
  });

  test('AC-15: снятие бейджа (0) проходит даже под латчем отказа', () async {
    // Регресс-защита существующего инварианта: иначе один PERMISSION_DENIED
    // навсегда заклинивал бы залипшую «1».
    mockBadger(denied: true);
    await AppBadge.trySet(3);
    calls.clear();
    mockBadger();
    await AppBadge.trySet(0);
    expect(calls, contains('removeBadge'));
  });
}
