import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/auth_proxy_service.dart';

/// Диалог "Получить ссылку-приглашение" для рума.
/// Открывается по кнопке в chat_details_view при PL >= 50 (room.canInvite).
class InviteLinkDialog extends StatefulWidget {
  final Room room;

  /// Аккаунт, реально СОСТОЯЩИЙ в комнате (call-site передаёт room.client).
  /// Его access_token используется и для create, и для revoke — оба запроса
  /// обязаны идти через ОДИН клиент. В cross-HS бандле это может быть аккаунт
  /// с другого HS, видящий комнату федеративно: auth-proxy резолвит его mxid
  /// по всем нашим HS и проверяет членство/PL через Admin API. server_name
  /// (домен хостящего HS) берётся отдельно из room.id.
  final Client client;

  /// ScaffoldMessenger из контекста, где открыли диалог: контекст самого
  /// диалога живёт в overlay без Scaffold под ним, поэтому
  /// ScaffoldMessenger.of(context) внутри диалога падает на _scaffolds.isNotEmpty.
  final ScaffoldMessengerState scaffoldMessenger;

  const InviteLinkDialog({
    super.key,
    required this.room,
    required this.client,
    required this.scaffoldMessenger,
  });

  /// server_name для invite-операции — домен хостящего комнату HS (из room.id),
  /// а НЕ домен аккаунта-члена: в cross-HS бандле член комнаты может быть с
  /// другого HS. auth-proxy требует server_name == домену room_id. Ортогонально
  /// выбору токена (room.client). Вынесено для стража RL-invite-link-host-client.
  static String inviteServerName(String roomId) => roomId.split(':').last;

  @override
  State<InviteLinkDialog> createState() => _InviteLinkDialogState();
}

class _InviteLinkDialogState extends State<InviteLinkDialog> {
  InviteLinkInfo? _info;
  Object? _error;
  bool _loading = true;
  bool _revoking = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = widget.client;
      final serverName = InviteLinkDialog.inviteServerName(widget.room.id);
      final accessToken = client.accessToken;
      if (accessToken == null) {
        throw StateError('No access_token in Matrix client');
      }
      final info = await AuthProxyService().createInvite(
        serverName: serverName,
        roomId: widget.room.id,
        accessToken: accessToken,
      );
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
    } catch (e) {
      Logs().e('[InviteLinkDialog] createInvite failed: $e');
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _copy() async {
    final url = _info?.url;
    if (url == null) return;
    final copiedText = L10n.of(context).inviteLinkCopied;
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    widget.scaffoldMessenger.showSnackBar(
      SnackBar(content: Text(copiedText)),
    );
  }

  Future<void> _revoke() async {
    final info = _info;
    if (info == null) return;
    setState(() {
      _revoking = true;
    });
    try {
      final client = widget.client;
      final accessToken = client.accessToken;
      if (accessToken == null) {
        throw StateError('No access_token in Matrix client');
      }
      await AuthProxyService().revokeInvite(
        code: info.code,
        accessToken: accessToken,
      );
      if (!mounted) return;
      // перегенерируем ссылку: createInvite вернёт новую (после revoke
      // активной ссылки нет, find-or-create создаст новую).
      setState(() {
        _info = null;
        _revoking = false;
      });
      await _load();
    } catch (e) {
      Logs().e('[InviteLinkDialog] revokeInvite failed: $e');
      if (!mounted) return;
      setState(() {
        _revoking = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(L10n.of(context).inviteLink),
      content: _buildBody(),
      actions: [
        if (_info != null && !_revoking) ...[
          TextButton(
            onPressed: _copy,
            child: Text(L10n.of(context).copy),
          ),
          TextButton(
            onPressed: _revoke,
            child: Text(L10n.of(context).revokeInviteLink),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(L10n.of(context).close),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading || _revoking) {
      return const SizedBox(
        width: 64,
        height: 64,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Text(
        L10n.of(context).inviteLinkLoadError(_error.toString()),
        style: TextStyle(
          color: Theme.of(context).colorScheme.error,
        ),
      );
    }
    final info = _info!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SelectableText(
          info.url,
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        const SizedBox(height: 8),
        Text(
          L10n.of(context).inviteLinkShareHint,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
