import 'package:flutter_test/flutter_test.dart';

import 'package:liza/pages/chat_details/blocked_members.dart';
import 'package:liza/utils/auth_proxy_service.dart';

MemberBlockInfo _b(String mxid, String status, {String? name}) =>
    MemberBlockInfo(mxid: mxid, status: status, displayName: name);

void main() {
  final blocks = [
    _b('@nadezhda:hs', 'banned', name: 'Надя Розенталь'),
    _b('@daniel:hs', 'removed', name: 'Даниэль Фурман'),
    _b('@anton:hs', 'invite_revoked', name: 'Антон Орлов'),
  ];

  group('filterMemberBlocks', () {
    test('без фильтров возвращает всех', () {
      expect(filterMemberBlocks(blocks).length, 3);
    });

    test('фильтр по статусу', () {
      final banned = filterMemberBlocks(blocks, statusFilter: 'banned');
      expect(banned.length, 1);
      expect(banned.single.mxid, '@nadezhda:hs');
    });

    test('поиск по имени (регистронезависимо)', () {
      final r = filterMemberBlocks(blocks, query: 'даниэль');
      expect(r.length, 1);
      expect(r.single.mxid, '@daniel:hs');
    });

    test('поиск по логину (mxid)', () {
      final r = filterMemberBlocks(blocks, query: 'anton');
      expect(r.length, 1);
      expect(r.single.status, 'invite_revoked');
    });

    test('статус + поиск комбинируются', () {
      expect(
        filterMemberBlocks(blocks, statusFilter: 'banned', query: 'даниэль'),
        isEmpty,
      );
      expect(
        filterMemberBlocks(blocks, statusFilter: 'banned', query: 'надя')
            .length,
        1,
      );
    });

    test('нет совпадений — пустой список', () {
      expect(filterMemberBlocks(blocks, query: 'неттакого'), isEmpty);
    });
  });
}
