// ledger:RL-auth-orphan-after-oidc
// AC:RL-auth-orphan-after-oidc/5 AC:RL-auth-orphan-after-oidc/10
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/utils/pending_deep_link.dart';
import 'package:liza/utils/pending_invite_code.dart';
import 'package:liza/utils/pending_invite_gate.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // ignore: invalid_use_of_visible_for_testing_member
    PendingInviteCode.debugResetInMemory();

  });


  test('AC-10: код из персиста доступен после await restore()', () async {
    SharedPreferences.setMockInitialValues({
      'pending_deep_link.current': 'invite:p_persisted1',
    });

    // До restore() код не виден — ровно та гонка, из-за которой кнопка,
    // нажатая рано, отправляла inviteCode: null.
    expect(PendingInviteCode.current, isNull);

    final restore = PendingInviteCode.restore();
    await restore;

    expect(PendingInviteCode.current, 'p_persisted1');
  });

  test('AC-10: legacy-ключ тоже переживает восстановление', () async {
    SharedPreferences.setMockInitialValues({
      'pending_invite.current': 'p_legacy0001',
    });

    await PendingInviteCode.restore();

    expect(PendingInviteCode.current, 'p_legacy0001');
  });

  test('AC-5: без сохранённого кода restore() не выдумывает инвайт', () async {
    SharedPreferences.setMockInitialValues({});

    await PendingInviteCode.restore();

    expect(PendingInviteCode.current, isNull);
    expect(PendingDeepLinkStore.current, isNull);
  });

  // --- Страж самой гонки ---
  //
  // Тесты выше проверяют контракт restore() и зелены независимо от правки
  // контроллера. Регресс «кнопка не дождалась восстановления» ловят тесты ниже.
  //
  // Проверяется РЕАЛЬНАЯ продакшен-функция inviteCodeAfterRestore — та самая,
  // которую в бою зовут обе кнопки (registerAction и authProxyLoginAction).
  // Не реплика и не грep исходника: уберёшь `await` внутри неё — тесты краснеют.
  // Прежний греп-вариант отвергнут по прецеденту 839e5203 («чистая функция
  // вместо грепа исходника»): проверка текста файла зеленела бы и тогда, когда
  // ожидание физически на месте, но на поведение не влияет.

  /// Восстановление, момент завершения которого мы задаём вручную.
  ///
  /// Модель `initState`: future кладётся в поле сразу, а [PendingInviteCode]
  /// наполняется только когда чтение хранилища завершилось.
  ({Future<void> pending, void Function() complete}) delayedRestore(
    String inviteCode,
  ) {
    final gate = Completer<void>();
    final pending = gate.future.then((_) => PendingInviteCode.set(inviteCode));
    return (pending: pending, complete: () => gate.complete());
  }

  test('AC-10: инвайт доезжает, даже если кнопку нажали до конца чтения',
      () async {
    SharedPreferences.setMockInitialValues({});
    final restore = delayedRestore('p_race_login');

    // Кнопка нажата, когда хранилище ещё не прочитано: код не виден.
    expect(PendingInviteCode.current, isNull);
    final sent = inviteCodeAfterRestore(restore.pending);

    // Восстановление завершается уже ПОСЛЕ нажатия.
    restore.complete();

    // Без `await` внутри функции здесь пришёл бы null — сервер не получил бы
    // invite_code, register_via_invite не вызвался бы, и человек с валидной
    // ссылкой увидел бы «нет доступа».
    expect(await sent, 'p_race_login');
  });

  test('AC-10: код из персиста доезжает через реальный restore()', () async {
    SharedPreferences.setMockInitialValues({
      'pending_deep_link.current': 'invite:p_persisted2',
    });

    // Полный путь как в initState: future восстановления → чтение через гейт.
    final pendingRestore = PendingInviteCode.restore();
    expect(PendingInviteCode.current, isNull);

    expect(await inviteCodeAfterRestore(pendingRestore), 'p_persisted2');
  });

  test('AC-5: без сохранённого кода гейт не выдумывает инвайт', () async {
    SharedPreferences.setMockInitialValues({});

    expect(
      await inviteCodeAfterRestore(PendingInviteCode.restore()),
      isNull,
    );
  });
}
