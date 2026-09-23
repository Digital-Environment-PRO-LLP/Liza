import 'package:liza/utils/chat_topology.dart';

enum MemberRoleFilter { all, admins, moderators, users }

bool matchesRoleFilter(int powerLevel, MemberRoleFilter filter) =>
    switch (filter) {
      MemberRoleFilter.all => true,
      MemberRoleFilter.admins => powerLevel >= adminPowerLevel,
      MemberRoleFilter.moderators =>
        powerLevel >= moderatorPowerLevel && powerLevel < adminPowerLevel,
      MemberRoleFilter.users => powerLevel < moderatorPowerLevel,
    };
