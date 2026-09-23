import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/access_admin_service.dart';
import 'package:liza/widgets/avatar.dart';
import 'package:liza/widgets/matrix.dart';

/// Тип сущности для фильтрации досье чипами.
enum DossierTypeFilter { all, chats, bots, channels, spaces }

/// Раскрывающаяся панель управления доступами под строкой участника.
///
/// Получает готовое досье и колбэк, сам ничего не грузит — загрузка живёт
/// в контроллере экрана. Хранит только выбор чипа-фильтра по типу сущности.
class AccessAdminPanel extends StatefulWidget {
  final AccessDossier dossier;
  final VoidCallback onToggleActive;

  const AccessAdminPanel({
    required this.dossier,
    required this.onToggleActive,
    super.key,
  });

  @override
  State<AccessAdminPanel> createState() => _AccessAdminPanelState();
}

class _AccessAdminPanelState extends State<AccessAdminPanel> {
  DossierTypeFilter _filter = DossierTypeFilter.all;

  bool _visible(DossierTypeFilter group) =>
      _filter == DossierTypeFilter.all || _filter == group;

  @override
  void didUpdateWidget(AccessAdminPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Пришло новое досье (раскрыли другого участника) — выбранный чип-фильтр
    // может указывать на тип, которого в нём нет: иначе панель показала бы
    // заголовок над пустой секцией. Сбрасываем на «Все».
    if (!identical(oldWidget.dossier, widget.dossier) &&
        !_filterHasEntries(_filter)) {
      _filter = DossierTypeFilter.all;
    }
  }

  bool _filterHasEntries(DossierTypeFilter group) => switch (group) {
        DossierTypeFilter.all => true,
        DossierTypeFilter.chats => widget.dossier.chats.isNotEmpty,
        DossierTypeFilter.bots => widget.dossier.bots.isNotEmpty,
        DossierTypeFilter.channels => widget.dossier.channels.isNotEmpty,
        DossierTypeFilter.spaces => widget.dossier.spaces.isNotEmpty,
      };

  String _levelLabel(BuildContext context, AccessLevel level) =>
      switch (level) {
        AccessLevel.admin => L10n.of(context).accessLevelAdmin,
        AccessLevel.moderator => L10n.of(context).accessLevelModerator,
        AccessLevel.user => L10n.of(context).accessLevelUser,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final dossier = widget.dossier;
    final hasMemberships = dossier.spaces.isNotEmpty ||
        dossier.channels.isNotEmpty ||
        dossier.chats.isNotEmpty ||
        dossier.bots.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(72, 0, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle(theme, l10n.accessDossierServer),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    dossier.serverName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (dossier.roleLabel != null)
                  Text(
                    dossier.roleLabel!,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (hasMemberships) _typeFilters(context),
          if (_visible(DossierTypeFilter.spaces) && dossier.spaces.isNotEmpty)
            _group(context, theme, l10n.accessDossierSpaces, dossier.spaces,
                DossierTypeFilter.spaces),
          if (_visible(DossierTypeFilter.channels) &&
              dossier.channels.isNotEmpty)
            _group(context, theme, l10n.accessDossierChannels, dossier.channels,
                DossierTypeFilter.channels),
          if (_visible(DossierTypeFilter.bots) && dossier.bots.isNotEmpty)
            _group(context, theme, l10n.accessDossierBots, dossier.bots,
                DossierTypeFilter.bots),
          if (_visible(DossierTypeFilter.chats) && dossier.chats.isNotEmpty)
            _group(context, theme, l10n.accessDossierChats, dossier.chats,
                DossierTypeFilter.chats),
          if (!hasMemberships)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l10n.accessDossierEmpty,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 12),
          if (!dossier.isLocal)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                l10n.accessForeignServerAccount,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          _toggleButton(context, theme, l10n),
        ],
      ),
    );
  }

  Widget _typeFilters(BuildContext context) {
    final l10n = L10n.of(context);
    final labels = {
      DossierTypeFilter.all: l10n.accessFilterAll,
      DossierTypeFilter.chats: l10n.accessDossierChats,
      DossierTypeFilter.bots: l10n.accessDossierBots,
      DossierTypeFilter.channels: l10n.accessDossierChannels,
      DossierTypeFilter.spaces: l10n.accessDossierSpaces,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final entry in labels.entries)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(entry.value),
                  selected: _filter == entry.key,
                  onSelected: (_) => setState(() => _filter = entry.key),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _toggleButton(BuildContext context, ThemeData theme, L10n l10n) {
    final dossier = widget.dossier;
    final enabled = dossier.isLocal;
    final label = dossier.deactivated
        ? l10n.accessReactivateAccount
        : l10n.accessDeactivateAccount;
    final color =
        dossier.deactivated ? theme.colorScheme.primary : theme.colorScheme.error;

    return OutlinedButton(
      onPressed: enabled ? widget.onToggleActive : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(
          color: enabled ? color : theme.disabledColor,
        ),
      ),
      child: Text(label),
    );
  }

  Widget _sectionTitle(ThemeData theme, String title) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 2),
        child: Text(
          title,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );

  Widget _group(
    BuildContext context,
    ThemeData theme,
    String title,
    List<DossierEntry> entries,
    DossierTypeFilter group,
  ) {
    final client = Matrix.of(context).client;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(theme, title),
        // НИЧЕГО не скрываем: сервер (dossier) уже отсёк tombstoned/скрытые, а
        // остаточные «Без названия» — живые комнаты, где участник состоит; это
        // ровно то, что владелец компании хочет видеть. Различаем строки по
        // достижимости: где сам смотрящий состоит (membership=join, НЕ просто
        // getRoomById!=null — тот ловит и архивные/left из стора) — строку
        // делаем кликабельной, чтобы зайти и навести порядок штатным UI.
        // Пространства навигируются через setActiveSpace, а не /rooms — их из
        // этой панели не открываем (тап только для чат/канал/бот).
        ...entries.map((entry) {
          final room = client.getRoomById(entry.roomId);
          final reachable = room != null && room.membership == Membership.join;
          final tappable = reachable && group != DossierTypeFilter.spaces;
          final name = reachable && entry.name == null
              ? room.getLocalizedDisplayname()
              : entry.name;
          return _entryRow(context, theme, entry, name, tappable);
        }),
      ],
    );
  }

  Widget _entryRow(
    BuildContext context,
    ThemeData theme,
    DossierEntry entry,
    String? name,
    bool tappable,
  ) {
    final l10n = L10n.of(context);
    final avatar = Avatar(
      mxContent: entry.avatar == null ? null : Uri.tryParse(entry.avatar!),
      name: name,
      size: 24,
    );
    final level = Text(
      _levelLabel(context, entry.level),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    if (tappable) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 0,
        dense: true,
        visualDensity: VisualDensity.compact,
        leading: avatar,
        title: Text(
          name ?? l10n.unnamedRoom,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        trailing: level,
        onTap: () => context.push('/rooms/${entry.roomId}'),
      );
    }

    // Недостижимая (или пространство) — видима, но не кликабельна, приглушена.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          avatar,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name ?? l10n.unnamedRoom,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          level,
        ],
      ),
    );
  }
}
