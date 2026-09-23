// ledger:RL-company-members-access
// AC:RL-company-members-access/14
import 'package:flutter_test/flutter_test.dart';
import 'package:liza/pages/chat_members/company_member_entry.dart';
import 'package:liza/pages/chat_members/member_role_filter.dart';
import 'package:liza/utils/access_admin_service.dart';

SpaceMember _member({
  String userId = '@u:company.ru',
  String? membershipInSpace,
  int maxPowerLevel = 0,
  List<ElevatedRoom> elevatedRooms = const [],
}) =>
    SpaceMember(
      userId: userId,
      membershipInSpace: membershipInSpace,
      maxPowerLevel: maxPowerLevel,
      elevatedRooms: elevatedRooms,
    );

void main() {
  group('effectiveMemberPowerLevel', () {
    test('без данных пространства берёт PL комнаты', () {
      expect(
        effectiveMemberPowerLevel(roomPowerLevel: 50, spaceMember: null),
        50,
      );
    });

    test('child-only участник без прав остаётся нулевым', () {
      // Баг: Мамуткин/Новокшонов — PL 0 везде, elevated_rooms пуст,
      // но попадали в таб «Модераторы».
      expect(
        effectiveMemberPowerLevel(
          roomPowerLevel: 0,
          spaceMember: _member(maxPowerLevel: 0),
        ),
        0,
      );
    });

    test('берёт максимум из PL комнаты и данных пространства', () {
      expect(
        effectiveMemberPowerLevel(
          roomPowerLevel: 0,
          spaceMember: _member(maxPowerLevel: 100),
        ),
        100,
      );
      expect(
        effectiveMemberPowerLevel(
          roomPowerLevel: 100,
          spaceMember: _member(maxPowerLevel: 50),
        ),
        100,
      );
    });
  });

  // AC:RL-company-members-access/12
  test(
    'участник с нулевым эффективным PL не проходит фильтр модераторов/'
    'администраторов, но проходит «все» и «пользователи»',
    () {
      final power = effectiveMemberPowerLevel(
        roomPowerLevel: 0,
        spaceMember: _member(maxPowerLevel: 0, elevatedRooms: const []),
      );

      expect(matchesRoleFilter(power, MemberRoleFilter.moderators), isFalse);
      expect(matchesRoleFilter(power, MemberRoleFilter.admins), isFalse);
      expect(matchesRoleFilter(power, MemberRoleFilter.all), isTrue);
      expect(matchesRoleFilter(power, MemberRoleFilter.users), isTrue);
    },
  );

  group('memberBelongsToServer', () {
    test('домен MXID совпадает с сервером компании', () {
      expect(
        memberBelongsToServer(
          userId: '@rozental.nadezhda:nadezhda.liza.ru',
          serverName: 'nadezhda.liza.ru',
        ),
        isTrue,
      );
    });

    test('федеративный аккаунт не принадлежит серверу', () {
      expect(
        memberBelongsToServer(
          userId: '@roman.mamutkin:synapse.liza.laba.prodamus.tech',
          serverName: 'nadezhda.liza.ru',
        ),
        isFalse,
      );
    });

    test('домен с портом разбирается целиком', () {
      expect(
        memberBelongsToServer(
          userId: '@user:matrix.example.com:8448',
          serverName: 'matrix.example.com:8448',
        ),
        isTrue,
      );
    });

    test('лишний сегмент в домене не совпадает с сервером компании', () {
      expect(
        memberBelongsToServer(
          userId: '@a:b:nadezhda.liza.ru',
          serverName: 'nadezhda.liza.ru',
        ),
        isFalse,
      );
    });
  });

  group('memberJoinedCompany', () {
    test('членство в самой комнате компании', () {
      expect(memberJoinedCompany(joinedRoom: true, spaceMember: null), isTrue);
    });

    test('membership_in_space из выдачи сервера', () {
      expect(
        memberJoinedCompany(
          joinedRoom: false,
          spaceMember: _member(membershipInSpace: 'join'),
        ),
        isTrue,
      );
    });

    test('child-only участник в компании не состоит', () {
      expect(
        memberJoinedCompany(joinedRoom: false, spaceMember: _member()),
        isFalse,
      );
    });
  });

  group('matchesMembershipCheckboxes', () {
    test('оба сняты — пропускает всех', () {
      expect(
        matchesMembershipCheckboxes(
          onServerOnly: false,
          inCompanyOnly: false,
          belongsToServer: false,
          joinedCompany: false,
        ),
        isTrue,
      );
    });

    test('«на сервере» отсекает федеративных', () {
      expect(
        matchesMembershipCheckboxes(
          onServerOnly: true,
          inCompanyOnly: false,
          belongsToServer: false,
          joinedCompany: true,
        ),
        isFalse,
      );
    });

    test('«в компании» отсекает child-only', () {
      expect(
        matchesMembershipCheckboxes(
          onServerOnly: false,
          inCompanyOnly: true,
          belongsToServer: true,
          joinedCompany: false,
        ),
        isFalse,
      );
    });

    // AC:RL-company-members-access/17 — мультивыбор чекбоксов сохранён (оба
    // можно включить), сужение по AND.
    test('оба включены — сужение по AND', () {
      expect(
        matchesMembershipCheckboxes(
          onServerOnly: true,
          inCompanyOnly: true,
          belongsToServer: true,
          joinedCompany: true,
        ),
        isTrue,
      );
      expect(
        matchesMembershipCheckboxes(
          onServerOnly: true,
          inCompanyOnly: true,
          belongsToServer: true,
          joinedCompany: false,
        ),
        isFalse,
      );
    });
  });
}
