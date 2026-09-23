// ledger:RL-user-invite-link-opens-profile
// AC:RL-user-invite-link-opens-profile/9 — незалогиненный web-вход по короткой
// ссылке (/i, /s, /c, /u) кладёт цель в PendingDeepLinkStore, и она переживает
// перезагрузку страницы до логина (redeemPendingInviteAfterLogin → /opening).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:liza/utils/deep_link_target.dart';
import 'package:liza/utils/pending_deep_link.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PendingDeepLinkStore.debugResetInMemory();
  });

  // AC:RL-deeplink-target-resolve/1 — покрывает часть инварианта редиректа
  // /opening/:code (routes.dart) для незалогиненного пользователя: код
  // сохраняется как DeepLinkKind.invite, а не молча теряется. Сам redirect
  // требует живого BuildContext/Matrix.of и здесь не воспроизводится —
  // это единственное, что тестируется отдельно от go_router.
  test('инвайт-код (как при редиректе /opening без сессии) переживает '
      'перезагрузку страницы', () async {
    PendingDeepLinkStore.set(DeepLinkKind.invite, 'p_AbCdEfGh');
    await Future<void>.delayed(Duration.zero);
    PendingDeepLinkStore.debugResetInMemory();
    final restored = await PendingDeepLinkStore.restore();
    expect(restored?.kind, DeepLinkKind.invite);
    expect(restored?.code, 'p_AbCdEfGh');
  });

  test('сторис переживает перезагрузку страницы', () async {
    PendingDeepLinkStore.set(DeepLinkKind.story, 'abc123');
    // Дать fire-and-forget персисту долететь до SharedPreferences —
    // set() пишет фоном (unawaited), см. pending_invite_code_test.dart.
    await Future<void>.delayed(Duration.zero);
    PendingDeepLinkStore.debugResetInMemory();
    final restored = await PendingDeepLinkStore.restore();
    expect(restored?.kind, DeepLinkKind.story);
    expect(restored?.code, 'abc123');
  });

  test('канал переживает перезагрузку страницы', () async {
    PendingDeepLinkStore.set(DeepLinkKind.channel, 'mychannel');
    await Future<void>.delayed(Duration.zero);
    PendingDeepLinkStore.debugResetInMemory();
    final restored = await PendingDeepLinkStore.restore();
    expect(restored?.kind, DeepLinkKind.channel);
    expect(restored?.code, 'mychannel');
  });

  test('clear убирает и из памяти, и из персиста', () async {
    PendingDeepLinkStore.set(DeepLinkKind.invite, 'p_AbCdEfGh');
    await Future<void>.delayed(Duration.zero);
    PendingDeepLinkStore.clear();
    await Future<void>.delayed(Duration.zero);
    PendingDeepLinkStore.debugResetInMemory();
    expect(await PendingDeepLinkStore.restore(), isNull);
  });

  test('повторный deep-link того же кода помечается как уже обработанный',
      () async {
    expect(await PendingDeepLinkStore.markDeepLinkHandled('p_AbCdEfGh'), isTrue);
    expect(await PendingDeepLinkStore.markDeepLinkHandled('p_AbCdEfGh'), isFalse);
  });

  test(
      'старый ключ pending_invite.current мигрирует в новый формат '
      'и удаляется', () async {
    SharedPreferences.setMockInitialValues({
      'pending_invite.current': 'p_AbCdEfGh',
    });

    final restored = await PendingDeepLinkStore.restore();
    expect(restored?.kind, DeepLinkKind.invite);
    expect(restored?.code, 'p_AbCdEfGh');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pending_invite.current'), isNull);
    expect(prefs.getString('pending_deep_link.current'), 'invite:p_AbCdEfGh');
  });

  test('новый ключ побеждает старый, если заданы оба', () async {
    SharedPreferences.setMockInitialValues({
      'pending_invite.current': 'p_OldCode00',
      'pending_deep_link.current': 'story:newCode99',
    });

    final restored = await PendingDeepLinkStore.restore();
    expect(restored?.kind, DeepLinkKind.story);
    expect(restored?.code, 'newCode99');
  });
}
