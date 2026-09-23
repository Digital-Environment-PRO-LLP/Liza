import 'dart:async';

import 'package:flutter/material.dart';

import 'package:async/async.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/auth_proxy_service.dart';
import 'package:liza/utils/direct_chat_draft.dart';
import 'package:liza/utils/liza_share.dart';
import 'package:liza/widgets/avatar.dart';
import 'package:liza/widgets/matrix.dart';

/// Одна строка контакта из телефонной книги в экране «Контакты».
///
/// matched (есть [mxid]) → кнопка «Написать»; unmatched → «Пригласить».
/// Вынесен отдельным виджетом ради тестируемости (страж рендерит реальный
/// виджет, а не реплику) — RL-contacts-screen-match-invite.
class ContactListTile extends StatelessWidget {
  final String displayName;
  final String? subtitle;

  /// mxid из lookup, если контакт уже в Liza; иначе null.
  final String? mxid;
  final void Function(String mxid) onWrite;
  final VoidCallback onInvite;

  const ContactListTile({
    super.key,
    required this.displayName,
    this.subtitle,
    required this.mxid,
    required this.onWrite,
    required this.onInvite,
  });

  bool get isOnLiza => mxid != null;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return ListTile(
      leading: Avatar(name: displayName),
      title: Text(
        displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: isOnLiza
          ? FilledButton.tonal(
              onPressed: () => onWrite(mxid!),
              child: Text(l10n.writeMessage),
            )
          : OutlinedButton.icon(
              onPressed: onInvite,
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: Text(l10n.invite),
            ),
    );
  }
}

/// Экран, когда доступ к контактам запрещён: объяснение + переход в настройки.
class ContactsPermissionView extends StatelessWidget {
  final VoidCallback onOpenSettings;

  const ContactsPermissionView({super.key, required this.onOpenSettings});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.contacts_outlined, size: 64),
            const SizedBox(height: 16),
            Text(
              l10n.contactsPermissionDenied,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onOpenSettings,
              child: Text(l10n.openSettings),
            ),
          ],
        ),
      ),
    );
  }
}

/// Разрешённый контакт из книги (после дедупа телефонов).
class _ContactEntry {
  final String displayName;
  final List<String> phones;
  String? mxid;

  _ContactEntry(this.displayName, this.phones);
}

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

enum _Stage { loading, denied, ready, error }

class _ContactsPageState extends State<ContactsPage> {
  _Stage _stage = _Stage.loading;
  List<_ContactEntry> _onLiza = const [];
  List<_ContactEntry> _toInvite = const [];
  CancelableOperation<Map<String, String>>? _lookupOp;

  @override
  void initState() {
    super.initState();
    // Разрешение спрашиваем ЛЕНИВО — при открытии экрана, а не на ремаунт
    // ChatList (иначе системный диалог всплывал бы на каждый ремаунт).
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _lookupOp?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!mounted) return;
    if (!granted) {
      setState(() => _stage = _Stage.denied);
      return;
    }
    try {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      if (!mounted) return;

      final entries = <_ContactEntry>[];
      final allPhones = <String>{};
      for (final c in contacts) {
        final phones = c.phones
            .map((p) => p.number.trim())
            .where((n) => n.isNotEmpty)
            .toSet()
            .toList();
        if (phones.isEmpty) continue;
        entries.add(_ContactEntry(c.displayName, phones));
        allPhones.addAll(phones);
      }

      final client = Matrix.of(context).client;
      final accessToken = client.accessToken ?? '';
      final phoneList = allPhones.toList();
      // Сервер ограничивает батч 500 номерами (anti-enumeration) — большую книгу
      // бьём на чанки, иначе >500 уникальных номеров → 429 → экран ошибки.
      const chunkSize = 500;
      final matches = <String, String>{};
      for (var i = 0; i < phoneList.length; i += chunkSize) {
        final end = (i + chunkSize).clamp(0, phoneList.length);
        _lookupOp = CancelableOperation.fromFuture(
          AuthProxyService()
              .lookupContacts(
                phones: phoneList.sublist(i, end),
                accessToken: accessToken,
              )
              .timeout(const Duration(seconds: 10)),
        );
        final part = await _lookupOp!.valueOrCancellation(null);
        if (!mounted || part == null) return; // размонтировано/отменено
        matches.addAll(part);
      }

      final onLiza = <_ContactEntry>[];
      final toInvite = <_ContactEntry>[];
      for (final e in entries) {
        for (final phone in e.phones) {
          final mxid = matches[phone];
          if (mxid != null) {
            e.mxid = mxid;
            break;
          }
        }
        (e.mxid != null ? onLiza : toInvite).add(e);
      }
      onLiza.sort((a, b) => a.displayName.compareTo(b.displayName));
      toInvite.sort((a, b) => a.displayName.compareTo(b.displayName));
      setState(() {
        _onLiza = onLiza;
        _toInvite = toInvite;
        _stage = _Stage.ready;
      });
    } catch (e, s) {
      Logs().w('[Contacts] load failed', e, s);
      if (mounted) setState(() => _stage = _Stage.error);
    }
  }

  void _write(String mxid) {
    // Чат/приглашение — только с первым сообщением: существующий DM открываем
    // сразу, иначе ведём в черновик (комната родится при отправке). Федерация
    // между нашими HS не полная — отказ startDirectChat теперь всплывёт при
    // первой отправке из черновика, не при тапе «Написать».
    openDirectChatOrDraft(GoRouter.of(context), Matrix.of(context).client, mxid);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.contactsTitle)),
      body: switch (_stage) {
        _Stage.loading => const Center(child: CircularProgressIndicator()),
        _Stage.denied => ContactsPermissionView(
            onOpenSettings: openAppSettings,
          ),
        _Stage.error => Center(child: Text(l10n.oopsSomethingWentWrong)),
        _Stage.ready => _buildList(context, l10n),
      },
    );
  }

  Widget _buildList(BuildContext context, L10n l10n) {
    if (_onLiza.isEmpty && _toInvite.isEmpty) {
      return Center(child: Text(l10n.noContactsToShow));
    }
    final children = <Widget>[
      if (_onLiza.isNotEmpty)
        _SectionHeader(title: l10n.contactsOnLiza),
      ..._onLiza.map(
        (e) => ContactListTile(
          displayName: e.displayName,
          subtitle: e.phones.first,
          mxid: e.mxid,
          onWrite: _write,
          onInvite: () => LizaShare.shareInvitePeople(context),
        ),
      ),
      if (_toInvite.isNotEmpty)
        _SectionHeader(title: l10n.contactsInviteHint),
      ..._toInvite.map(
        (e) => ContactListTile(
          displayName: e.displayName,
          subtitle: e.phones.first,
          mxid: null,
          onWrite: _write,
          onInvite: () => LizaShare.shareInvitePeople(context),
        ),
      ),
    ];
    return ListView.builder(
      itemCount: children.length,
      itemBuilder: (context, i) => children[i],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}
