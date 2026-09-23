import 'package:flutter/material.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/liza_share.dart';
import 'package:liza/widgets/avatar.dart';

/// Строка «Пригласить людей» под чатом «Лиза ИИ» в списке чатов.
/// Тап открывает нативное меню шеринга invite-ссылки (howItWoks/addContacts.md).
class InvitePeopleListTile extends StatefulWidget {
  const InvitePeopleListTile({super.key});

  @override
  State<InvitePeopleListTile> createState() => _InvitePeopleListTileState();
}

class _InvitePeopleListTileState extends State<InvitePeopleListTile> {
  // Гейт от двойного тапа: createUserInvite ходит в сеть, без гейта два тапа
  // открыли бы два параллельных запроса и два share-листа.
  bool _inviting = false;

  Future<void> _onTap() async {
    if (_inviting) return;
    setState(() => _inviting = true);
    try {
      await LizaShare.shareInvitePeople(context);
    } finally {
      if (mounted) setState(() => _inviting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Геометрия строки выровнена по ChatListItem, чтобы «Пригласить людей» стояла
    // на одном уровне с чатами: аватар 44 (Avatar.defaultSize) в фиксированном
    // SizedBox (ListTile мерит leading по intrinsic-ширине), тот же
    // visualDensity(-0.5) и левый край leading 16px. См.
    // docs/superpowers/specs/2026-08-20-invite-people-row-alignment-design.md.
    return ListTile(
      visualDensity: const VisualDensity(vertical: -0.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: SizedBox(
        width: Avatar.defaultSize,
        height: Avatar.defaultSize,
        child: CircleAvatar(
          radius: Avatar.defaultSize / 2,
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          child: const Icon(Icons.person_add_alt_1),
        ),
      ),
      title: Text(
        L10n.of(context).invitePeople,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      onTap: _onTap,
    );
  }
}
