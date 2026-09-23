import 'package:flutter/material.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/demo_auth/demo_auth_service.dart';

/// Форма обращения в поддержку с экранов входа.
///
/// Человек сюда попадает из тупика (код не приходит, попытки исчерпаны),
/// поэтому форма минимальна: обратный адрес и текст.
Future<void> showSupportDialog(
  BuildContext context, {
  String? ticket,
  String? step,
  String? errorCode,
  String? initialEmail,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _SupportDialog(
      ticket: ticket,
      step: step,
      errorCode: errorCode,
      initialEmail: initialEmail,
    ),
  );
}

class _SupportDialog extends StatefulWidget {
  const _SupportDialog({
    this.ticket,
    this.step,
    this.errorCode,
    this.initialEmail,
  });

  final String? ticket;
  final String? step;
  final String? errorCode;
  final String? initialEmail;

  @override
  State<_SupportDialog> createState() => _SupportDialogState();
}

class _SupportDialogState extends State<_SupportDialog> {
  final DemoAuthService _service = DemoAuthService();
  late final TextEditingController _email =
      TextEditingController(text: widget.initialEmail ?? '');
  final TextEditingController _text = TextEditingController();

  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _text.dispose();
    super.dispose();
  }

  bool get _isValid =>
      _email.text.contains('@') && _text.text.trim().isNotEmpty;

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _service.sendSupportRequest(
        email: _email.text.trim(),
        text: _text.text.trim(),
        ticket: widget.ticket,
        step: widget.step,
        errorCode: widget.errorCode,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).supportContactSent)),
      );
    } on DemoAuthException catch (err) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = err.code;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.supportContactTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: l10n.supportContactEmail),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            maxLines: 4,
            decoration: InputDecoration(labelText: l10n.supportContactText),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _sending || !_isValid ? null : _send,
          child: Text(l10n.supportContactSend),
        ),
      ],
    );
  }
}
