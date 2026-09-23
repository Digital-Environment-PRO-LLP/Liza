import 'package:flutter/widgets.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/chat_topology.dart';
import 'package:liza/utils/company_membership.dart';
import 'package:liza/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:liza/utils/support_chat.dart';
import 'package:liza/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:liza/widgets/matrix.dart';

/// Вид пункта «выхода» для комнаты с учётом прав текущего пользователя.
///
/// Одна точка, где к таблице [leaveActionKind] подмешивается [Room]: три меню
/// (шапка чата, плитка списка, пространство) до LABA-2540 разошлись именно
/// потому, что каждое собирало входы таблицы по-своему.
LeaveActionKind leaveActionKindFor(BuildContext context, Room room) =>
    leaveActionKind(
      membership: room.membership,
      companyKind: foreignCompanyKind(
        userId: room.client.userID,
        roomId: room.id,
        isTopLevelSpace: isTopLevelSpaceRoom(room),
      ),
      isMainRootSpace:
          room.id == Matrix.of(context).singleSpaceService.mainRootSpaceId,
      isChannel: room.isChannel,
      isSpace: room.isSpace,
      isAdmin: room.ownPowerLevel >= adminPowerLevel,
    );

/// «Удалить компанию через поддержку» (LABA-2533): подтверждение → DM с
/// `@support`, в композере — готовая заявка с именем и room_id компании.
///
/// Компания = Synapse-инстанс, из клиента её не удалить (single_space_guard
/// отвечает на leave 403, а «удалить» = вывести сервер из эксплуатации), поэтому
/// ни `leave()`, ни `forget()` здесь не вызываются и ничего не отправляется —
/// отправляет пользователь сам, проверив текст.
Future<void> requestCompanyDeletion(BuildContext context, Room room) async {
  final l10n = L10n.of(context);
  final name = room.getLocalizedDisplayname(MatrixLocals(l10n));
  final confirmed = await showOkCancelAlertDialog(
    context: context,
    title: l10n.deleteCompanyViaSupport,
    message: l10n.deleteCompanyViaSupportDescription(name),
    okLabel: l10n.deleteCompanyViaSupportConfirm,
    cancelLabel: l10n.cancel,
    isDestructive: true,
  );
  if (confirmed != OkCancelResult.ok || !context.mounted) return;
  await openSupportChat(
    context,
    composerDraft: l10n.deleteCompanyRequestDraft(name, room.id),
  );
}
