import 'package:flutter/material.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/adaptive_bottom_sheet.dart';
import 'package:liza/utils/date_time_extension.dart';
import 'package:liza/utils/room_status_extension.dart';
import 'package:liza/widgets/avatar.dart';
import 'package:liza/widgets/matrix.dart';

/// Окно «кто и когда прочитал сообщение» — по тапу на кластер аватарок
/// прочтения. На десктопе (column mode) это центрированный диалог, на
/// мобильных — bottom sheet (см. [showAdaptiveBottomSheet]).
Future<void> showReadReceiptsSheet(
  BuildContext context,
  List<MessageReadReceipt> receipts,
) {
  return showAdaptiveBottomSheet(
    context: context,
    builder: (context) => ReadReceiptsList(receipts: receipts),
  );
}

class ReadReceiptsList extends StatelessWidget {
  final List<MessageReadReceipt> receipts;
  const ReadReceiptsList({required this.receipts, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(
                  Icons.done_all_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  L10n.of(context).readBy,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  '${receipts.length}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: receipts.length,
              itemBuilder: (context, i) {
                final receipt = receipts[i];
                final user = receipt.user;
                return ListTile(
                  leading: Avatar(
                    mxContent: user.avatarUrl,
                    name: user.calcDisplayname(),
                    isHexagonal: Matrix.of(context).isAiUser(user.id),
                  ),
                  title: Text(
                    user.calcDisplayname(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: receipt.ts > 0
                      ? Text(
                          DateTime.fromMillisecondsSinceEpoch(
                            receipt.ts,
                          ).localizedTime(context),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        )
                      : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
