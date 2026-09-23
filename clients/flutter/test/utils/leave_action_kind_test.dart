import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/utils/company_membership.dart';

// ledger:RL-leave-chat-not-delete
// ledger:RL-delete-company-via-support
//
// LABA-2540: пункт назывался «Удалить чат» с иконкой корзины, а вызывал
// room.leave() — чат оставался у остальных участников и уезжал в архив.
// Таблица решений — единственный источник правды для трёх точек входа
// (меню в шапке чата, контекстное меню плитки списка, меню пространства),
// которые до фикса разошлись между собой на четырёх ветках из шести.

/// Все типы комнат, которые проходят через один и тот же пункт «выхода».
/// Перечисление явное: квантор «ни один тип не подписан „Удалить“» проверяется
/// по ЭТОМУ списку, а не на одном примере.
const _kinds = <String, ({bool isChannel, bool isSpace})>{
  'личка': (isChannel: false, isSpace: false),
  'группа': (isChannel: false, isSpace: false),
  'чат-обсуждение канала': (isChannel: false, isSpace: false),
  'канал': (isChannel: true, isSpace: false),
  'пространство': (isChannel: false, isSpace: true),
};

void main() {
  group('leaveActionKind — таблица «тип комнаты → как подписать выход»', () {
    // AC:RL-leave-chat-not-delete/7
    test('своё главное пространство: пункта выхода нет вовсе', () {
      // single_space_guard отвечает на leave 403 (PROTECTED_MEMBERSHIPS).
      // Гейт был в chat_list и space_view, но потерян в меню шапки — а именно
      // туда ведёт «Настройки» пространства (chat_details_view).
      expect(
        leaveActionKind(
          membership: Membership.join,
          companyKind: CompanyMembershipKind.own,
          isMainRootSpace: false,
          isChannel: false,
          isSpace: true,
        ),
        LeaveActionKind.hidden,
      );
      expect(
        leaveActionKind(
          membership: Membership.join,
          companyKind: CompanyMembershipKind.none,
          isMainRootSpace: true,
          isChannel: false,
          isSpace: true,
        ),
        LeaveActionKind.hidden,
        reason: 'mainRootSpaceId — второй, независимый детектор своей компании',
      );
    });

    // AC:RL-delete-company-via-support/3
    test('админ своей компании: заявка в поддержку вместо пустоты', () {
      // LABA-2533: компания = инстанс, удаляет её поддержка. Оба детектора
      // «своей» компании (домен и mainRootSpaceId) дают одинаковый исход.
      for (final (companyKind, isMain) in [
        (CompanyMembershipKind.own, false),
        (CompanyMembershipKind.none, true),
      ]) {
        expect(
          leaveActionKind(
            membership: Membership.join,
            companyKind: companyKind,
            isMainRootSpace: isMain,
            isChannel: false,
            isSpace: true,
            isAdmin: true,
          ),
          LeaveActionKind.deleteCompanyViaSupport,
          reason: '$companyKind/main=$isMain',
        );
        expect(
          leaveActionKind(
            membership: Membership.invite,
            companyKind: companyKind,
            isMainRootSpace: isMain,
            isChannel: false,
            isSpace: true,
            isAdmin: true,
          ),
          LeaveActionKind.hidden,
          reason: 'по приглашению в свою компанию заявки нет — ещё не участник',
        );
      }
    });

    // AC:RL-delete-company-via-support/3 — права не расширяют пункт вовне.
    test('isAdmin влияет ТОЛЬКО на свою компанию', () {
      for (final companyKind in [
        CompanyMembershipKind.foreign,
        CompanyMembershipKind.none,
      ]) {
        for (final entry in _kinds.entries) {
          final withAdmin = leaveActionKind(
            membership: Membership.join,
            companyKind: companyKind,
            isMainRootSpace: false,
            isChannel: entry.value.isChannel,
            isSpace: entry.value.isSpace,
            isAdmin: true,
          );
          final withoutAdmin = leaveActionKind(
            membership: Membership.join,
            companyKind: companyKind,
            isMainRootSpace: false,
            isChannel: entry.value.isChannel,
            isSpace: entry.value.isSpace,
          );
          expect(
            withAdmin,
            withoutAdmin,
            reason:
                '${entry.key}/$companyKind: админ обычной комнаты или '
                'чужой компании не получает «удалить компанию»',
          );
          expect(withAdmin, isNot(LeaveActionKind.deleteCompanyViaSupport));
        }
      }
    });

    // AC:RL-leave-chat-not-delete/7
    test('приглашение: это отказ от приглашения, а не выход из чата', () {
      // Чата ещё нет: обещание «переместится в архив, другим будет видно, что
      // вы вышли» здесь ложно вдвойне.
      for (final entry in _kinds.entries) {
        expect(
          leaveActionKind(
            membership: Membership.invite,
            companyKind: CompanyMembershipKind.none,
            isMainRootSpace: false,
            isChannel: entry.value.isChannel,
            isSpace: entry.value.isSpace,
          ),
          LeaveActionKind.declineInvite,
          reason: '${entry.key}: приглашение важнее типа комнаты',
        );
      }
    });

    // AC:RL-leave-chat-not-delete/7
    test('чужая компания: выход — это отписка от компании', () {
      expect(
        leaveActionKind(
          membership: Membership.join,
          companyKind: CompanyMembershipKind.foreign,
          isMainRootSpace: false,
          isChannel: false,
          isSpace: true,
        ),
        LeaveActionKind.unsubscribeCompany,
      );
    });

    // AC:RL-leave-chat-not-delete/7
    test('канал, пространство и чат разведены', () {
      LeaveActionKind kindOf({
        required bool isChannel,
        required bool isSpace,
      }) => leaveActionKind(
        membership: Membership.join,
        companyKind: CompanyMembershipKind.none,
        isMainRootSpace: false,
        isChannel: isChannel,
        isSpace: isSpace,
      );

      expect(
        kindOf(isChannel: true, isSpace: false),
        LeaveActionKind.leaveChannel,
      );
      expect(
        kindOf(isChannel: false, isSpace: true),
        LeaveActionKind.leaveSpace,
      );
      expect(
        kindOf(isChannel: false, isSpace: false),
        LeaveActionKind.leaveChat,
        reason: 'группа, личка и чат-обсуждение — обычный выход из чата',
      );
    });

    // AC:RL-leave-chat-not-delete/7 — сквозной квантор по ВСЕМ комбинациям.
    test('ни одна комбинация не даёт действие с семантикой удаления', () {
      for (final membership in [Membership.join, Membership.invite]) {
        for (final companyKind in CompanyMembershipKind.values) {
          for (final isMainRootSpace in [false, true]) {
            for (final entry in _kinds.entries) {
              final kind = leaveActionKind(
                membership: membership,
                companyKind: companyKind,
                isMainRootSpace: isMainRootSpace,
                isChannel: entry.value.isChannel,
                isSpace: entry.value.isSpace,
              );
              // Единственное правдивое «Удалить» в клиенте — корзина экрана
              // «Архив» (Room.forget()). Она через эту таблицу не проходит,
              // значит ни один её исход не смеет означать удаление.
              expect(
                LeaveActionKind.values.contains(kind),
                isTrue,
                reason:
                    '${entry.key}/$membership/$companyKind/'
                    'main=$isMainRootSpace: исход вне таблицы',
              );
            }
          }
        }
      }
    });

    // AC:RL-leave-chat-not-delete/7 — порядок проверок, первый матч выигрывает.
    test('порядок приоритетов: hidden > invite > компания > тип комнаты', () {
      expect(
        leaveActionKind(
          membership: Membership.invite,
          companyKind: CompanyMembershipKind.own,
          isMainRootSpace: false,
          isChannel: false,
          isSpace: true,
        ),
        LeaveActionKind.hidden,
        reason: 'из своей компании выйти нельзя даже по приглашению',
      );
      expect(
        leaveActionKind(
          membership: Membership.invite,
          companyKind: CompanyMembershipKind.foreign,
          isMainRootSpace: false,
          isChannel: false,
          isSpace: true,
        ),
        LeaveActionKind.declineInvite,
        reason: 'непринятое приглашение в компанию — всё ещё отказ, не отписка',
      );
      expect(
        leaveActionKind(
          membership: Membership.join,
          companyKind: CompanyMembershipKind.foreign,
          isMainRootSpace: false,
          isChannel: true,
          isSpace: false,
        ),
        LeaveActionKind.unsubscribeCompany,
        reason: 'принадлежность к чужой компании важнее типа комнаты',
      );
    });
  });
}
