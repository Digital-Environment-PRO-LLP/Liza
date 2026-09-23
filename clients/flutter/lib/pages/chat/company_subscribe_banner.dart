import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/company_membership.dart';
import 'package:liza/utils/single_space_service.dart';
import 'package:liza/widgets/matrix.dart';

/// Плашка над сообщениями чата компании для внешнего юзера.
///
/// Показывается, когда чат прикреплён как m.space.child к чужой
/// (другого homeserver) компании, и юзер на эту компанию не подписан.
/// Клик: join пространства-компании.
class CompanySubscribeBanner extends StatefulWidget {
  const CompanySubscribeBanner({super.key, required this.room});

  final Room room;

  @override
  State<CompanySubscribeBanner> createState() => _CompanySubscribeBannerState();
}

class _CompanySubscribeBannerState extends State<CompanySubscribeBanner> {
  CompanyEntry? _parentCompany;
  bool _busy = false;
  bool _hidden = false;

  @override
  void initState() {
    super.initState();
    _resolveParent();
  }

  @override
  void didUpdateWidget(covariant CompanySubscribeBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _parentCompany = null;
      _hidden = false;
      _resolveParent();
    }
  }

  Future<void> _resolveParent() async {
    if (widget.room.isSpace) return;
    final service = Matrix.of(context).singleSpaceService;
    final company = await service.findParentCompanyFor(widget.room.id);
    if (!mounted) return;
    setState(() => _parentCompany = company);
  }

  Future<void> _subscribe() async {
    final company = _parentCompany;
    if (company == null || _busy) return;
    setState(() => _busy = true);
    try {
      await widget.room.client.joinRoom(
        company.roomId,
        serverName: company.via.isEmpty ? null : company.via,
      );
      if (!mounted) return;
      setState(() => _hidden = true);
    } catch (e, s) {
      Logs().w('[CompanySubscribeBanner] join failed', e, s);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden) return const SizedBox.shrink();
    final company = _parentCompany;
    if (company == null) return const SizedBox.shrink();

    final client = widget.room.client;
    final localCompanyRoom = client.getRoomById(company.roomId);
    if (!shouldShowCompanySubscribeBanner(
      parentCompanyId: company.roomId,
      userId: client.userID,
      localCompanyRoom: localCompanyRoom,
    )) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final companyName = company.name?.trim().isNotEmpty == true
        ? company.name!
        : L10n.of(context).company;

    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: InkWell(
        onTap: _busy ? null : _subscribe,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(
                Icons.business_outlined,
                color: theme.colorScheme.onSecondaryContainer,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  L10n.of(context).chatBelongsToCompanySubscribe(companyName),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
              if (_busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                )
              else
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSecondaryContainer,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
