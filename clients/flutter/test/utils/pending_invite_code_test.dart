import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/utils/pending_invite_code.dart';

/// Регресс 2026-08-04: `PendingInviteCode` держал код только в статике.
/// В вебе переход `/i/<code>` → форма логина — это полная перезагрузка
/// страницы, статика обнулялась, и `invite_code` не доезжал до
/// `/api/auth/registration`. Сессия создавалась без него → вместо
/// `register_via_invite` отрабатывала обычная классификация (`no_accounts`),
/// то есть «зарегистрировался, но не пускает».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PendingInviteCode.clear();
  });

  test('set() переживает потерю статики (перезагрузка страницы) '
      '[ledger:RL-pending-invite-persist] [AC:RL-pending-invite-persist/1]',
      () async {
    PendingInviteCode.set('d_rHAM5BjzHP');
    // Дать fire-and-forget персисту долететь до SharedPreferences.
    await Future<void>.delayed(Duration.zero);

    // Имитируем перезагрузку: статика обнулена, хранилище — нет.
    PendingInviteCode.debugResetInMemory();
    expect(PendingInviteCode.current, null);

    expect(await PendingInviteCode.restore(), 'd_rHAM5BjzHP');
    expect(PendingInviteCode.current, 'd_rHAM5BjzHP');
  });

  test('clear() стирает и персист — код не воскресает '
      '[AC:RL-pending-invite-persist/2]', () async {
    PendingInviteCode.set('d_rHAM5BjzHP');
    await Future<void>.delayed(Duration.zero);

    PendingInviteCode.clear();
    await Future<void>.delayed(Duration.zero);

    PendingInviteCode.debugResetInMemory();
    expect(await PendingInviteCode.restore(), null);
  });

  test('consume() возвращает код и стирает персист '
      '[AC:RL-pending-invite-persist/2]', () async {
    PendingInviteCode.set('p_X9CRwBb2rq');
    await Future<void>.delayed(Duration.zero);

    expect(PendingInviteCode.consume(), 'p_X9CRwBb2rq');
    await Future<void>.delayed(Duration.zero);

    PendingInviteCode.debugResetInMemory();
    expect(await PendingInviteCode.restore(), null);
  });

  test('restore() не перетирает более свежий код в памяти', () async {
    SharedPreferences.setMockInitialValues({
      'pending_invite.current': 'd_OLDcode123',
    });
    PendingInviteCode.set('d_NEWcode456');

    expect(await PendingInviteCode.restore(), 'd_NEWcode456');
  });

  test('restore() без сохранённого кода возвращает null', () async {
    expect(await PendingInviteCode.restore(), null);
  });
}
