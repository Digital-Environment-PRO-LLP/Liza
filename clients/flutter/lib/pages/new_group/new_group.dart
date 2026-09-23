import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart' as sdk;
import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/new_group/new_group_view.dart';
import 'package:liza/utils/chat_topology.dart';
import 'package:liza/utils/file_selector.dart';
import 'package:liza/utils/wait_for_room_in_sync.dart';
import 'package:liza/widgets/matrix.dart';

/// power_levels нового канала.
///
/// `events_default: 100` — постить может только админ (это и есть канал).
/// Порог `m.reaction: 0` обязателен явно: иначе он унаследует
/// `events_default`, и подписчику реакции запретит сервер.
///
/// Порог `m.room.redaction: 0` — ПАРНЫЙ к `m.reaction`: снятие реакции это
/// не «отмена», а отправка события `m.room.redaction`. Без явного порога оно
/// тоже наследует `events_default: 100`, и подписчик, поставивший реакцию,
/// получал `M_FORBIDDEN` при попытке её снять («Нет прав доступа»).
///
/// ⚠️ Именно `events['m.room.redaction'] = 0`, а НЕ `redact: 0`. Это разные
/// права по auth-rules Matrix: `events['m.room.redaction']` — право ОТПРАВИТЬ
/// событие редакции (по нему пользователь удаляет СВОЁ событие, ветка
/// «sender редакции == sender цели»), а `redact` — право отредактировать
/// ЧУЖОЕ событие. Опустив `redact` до 0, мы дали бы любому подписчику удалять
/// посты канала и чужие реакции; поэтому `redact` остаётся шаблонным (50).
///
/// Порог `invite: moderatorPowerLevel` (50) обязателен явно: preset
/// `private_chat`/`trusted_private_chat` Synapse выставляет `invite: 0`
/// (`handlers/room.py`), и без явного порога ПРИВАТНЫЙ канал наследовал 0 —
/// любой подписчик (PL 0) мог приглашать посторонних. Публичный канал (preset
/// `public_chat`) уже получал 50 из шаблона Synapse, приватный — нет; это
/// расхождение выравниваем, чтобы приглашать в канал мог только модератор,
/// независимо от типа (проверено на локальном стеке 2026-08-24,
/// [[RL-channel-permissions-enforcement]]).
///
/// Шаблонные пороги переносим явно — см. [synapseDefaultEventPowerLevels].
Map<String, Object?> channelPowerLevelOverride() => {
      'events_default': 100,
      'invite': moderatorPowerLevel,
      'events': {
        ...synapseDefaultEventPowerLevels,
        'm.reaction': 0,
        'm.room.redaction': 0,
      },
    };

/// power_levels нового ГРУППОВОГО чата.
///
/// Задаёт ТОЛЬКО `invite: moderatorPowerLevel` (50). Preset `private_chat`
/// Synapse (`handlers/room.py`) выставляет `invite: 0`, и без явного порога
/// приватная группа наследовала 0 — любой участник (PL 0) мог приглашать
/// посторонних (тот же класс отклонения, что был у канала, см.
/// [channelPowerLevelOverride] и `howItWoks/chanels/rightsInChannel.md §6`).
/// Публичная группа (preset `public_chat`) уже получала 50 из шаблона Synapse —
/// расхождение выравниваем, чтобы приглашать в группу мог только модератор,
/// независимо от типа.
///
/// ⚠️ НАМЕРЕННО без ключа `events` и без `events_default`. Synapse применяет
/// override shallow-merge'ем top-level ключей: `invite` перекрывает preset-ный
/// `invite: 0`, НЕ трогая шаблонный блок `events`. Появись здесь ключ `events`
/// — он заменил бы весь блок ЦЕЛИКОМ (как в канале, где ради этого копируется
/// [synapseDefaultEventPowerLevels]), и неперечисленные типы упали бы на
/// `state_default: 50` → модератор группы переписал бы `m.room.power_levels`.
/// В отличие от канала, группе НЕЛЬЗЯ поднимать `events_default` до 100 — в
/// группе сообщения пишут ВСЕ участники (порог остаётся дефолтным 0).
Map<String, Object?> groupPowerLevelOverride() => {
      'invite': moderatorPowerLevel,
    };

class NewGroup extends StatefulWidget {
  final CreateGroupType createGroupType;
  const NewGroup({this.createGroupType = CreateGroupType.group, super.key});

  @override
  NewGroupController createState() => NewGroupController();
}

class NewGroupController extends State<NewGroup> {
  TextEditingController nameController = TextEditingController();

  // Компания/пространство создаётся ПРИВАТНОЙ по умолчанию (visibility:private):
  // публичность — сознательный опт-ин через свитч «Публичная компания», а не
  // дефолт. Раньше initState форсил publicGroup=true для space → все компании
  // рождались публичными и утекали в федеративный поиск.
  // См. docs/superpowers/specs/2026-08-25-companies-private-by-default-design.md.
  bool publicGroup = false;
  bool groupCanBeFound = false;
  bool enableEncryption = false;

  Uint8List? avatar;

  Uri? avatarUrl;

  Object? error;

  bool loading = false;

  CreateGroupType get createGroupType => widget.createGroupType;

  void setPublicGroup(bool b) => setState(() {
    publicGroup = groupCanBeFound = b;
    if (b) enableEncryption = false;
  });

  void setGroupCanBeFound(bool b) => setState(() => groupCanBeFound = b);

  void setEnableEncryption(bool b) => setState(() => enableEncryption = b);

  void selectPhoto() async {
    final photo = await selectFiles(
      context,
      type: FileType.image,
      allowMultiple: false,
    );
    final bytes = await photo.singleOrNull?.readAsBytes();

    setState(() {
      avatarUrl = null;
      avatar = bytes;
    });
  }

  Future<void> _createGroup() async {
    if (!mounted) return;
    final roomId = await Matrix.of(context).client.createGroupChat(
      enableEncryption: enableEncryption,
      visibility: groupCanBeFound
          ? sdk.Visibility.public
          : sdk.Visibility.private,
      preset: publicGroup
          ? sdk.CreateRoomPreset.publicChat
          : sdk.CreateRoomPreset.privateChat,
      // Приглашать может только модератор+ (invite:50). Иначе приватная группа
      // наследует preset invite:0 и любой участник приглашает посторонних.
      powerLevelContentOverride: groupPowerLevelOverride(),
      // trim для паритета с _createChannel/_createSpace: имя из одних пробелов
      // не должно уезжать на сервер вместо честного «безымянная группа».
      groupName: nameController.text.trim().isNotEmpty
          ? nameController.text.trim()
          : null,
      initialState: [
        if (avatar != null)
          sdk.StateEvent(
            type: sdk.EventTypes.RoomAvatar,
            content: {'url': avatarUrl.toString()},
          ),
      ],
    );
    if (!mounted) return;
    context.go('/rooms/$roomId/invite');
  }

  Future<void> _createChannel() async {
    if (!mounted) return;
    final roomId = await Matrix.of(context).client.createRoom(
      preset: publicGroup
          ? sdk.CreateRoomPreset.publicChat
          : sdk.CreateRoomPreset.privateChat,
      creationContent: {'com.liza.chat.type': 'channel'},
      visibility: publicGroup ? sdk.Visibility.public : sdk.Visibility.private,
      roomAliasName: publicGroup
          ? nameController.text.trim().toLowerCase().replaceAll(' ', '_')
          : null,
      name: nameController.text.trim(),
      powerLevelContentOverride: channelPowerLevelOverride(),
      initialState: [
        if (avatar != null)
          sdk.StateEvent(
            type: sdk.EventTypes.RoomAvatar,
            content: {'url': avatarUrl.toString()},
          ),
        if (!publicGroup)
          sdk.StateEvent(
            type: sdk.EventTypes.RoomJoinRules,
            content: {'join_rule': 'invite'},
          ),
        // Открытый канал читается БЕЗ вступления (как в Liza): пресет
        // publicChat даёт history_visibility=shared, при котором Synapse
        // отвечает 403 «room previews are disabled» неучастнику, и клиенту
        // приходилось джойнить комнату только чтобы показать ленту — канал
        // сразу попадал в список чатов, хотя на него не подписывались.
        // Закрытый канал видимость не меняет: его контент не публичен.
        if (publicGroup)
          sdk.StateEvent(
            type: sdk.EventTypes.HistoryVisibility,
            content: {'history_visibility': 'world_readable'},
          ),
      ],
    );
    // createRoom возвращает успех сразу после записи на сервере, но
    // getRoomById видит комнату только после /sync — без ожидания переход
    // натыкается на room==null (ChatPage: "вы больше не участвуете в чате").
    await waitForRoomInSync(Matrix.of(context).client, roomId);
    if (!mounted) return;
    context.go('/rooms/$roomId');
  }

  Future<void> _createSpace() async {
    if (!mounted) return;
    final spaceId = await Matrix.of(context).client.createRoom(
      preset: publicGroup
          ? sdk.CreateRoomPreset.publicChat
          : sdk.CreateRoomPreset.privateChat,
      creationContent: {'type': RoomCreationTypes.mSpace},
      visibility: publicGroup ? sdk.Visibility.public : sdk.Visibility.private,
      roomAliasName: publicGroup
          ? nameController.text.trim().toLowerCase().replaceAll(' ', '_')
          : null,
      name: nameController.text.trim(),
      powerLevelContentOverride: {'events_default': 100},
      initialState: [
        if (avatar != null)
          sdk.StateEvent(
            type: sdk.EventTypes.RoomAvatar,
            content: {'url': avatarUrl.toString()},
          ),
        if (!publicGroup)
          sdk.StateEvent(
            type: sdk.EventTypes.RoomJoinRules,
            content: {'join_rule': 'invite'},
          ),
      ],
    );
    if (!mounted) return;
    context.pop<String>(spaceId);
  }

  void submitAction([dynamic _]) async {
    final client = Matrix.of(context).client;

    try {
      // Компания и канал: пустое имя недопустимо. У публичного канала alias
      // выводится из имени (_createChannel), а Synapse пустой localpart НЕ
      // отвергает (handlers/room.py) — первый такой канал МОЛЧА получает
      // мусорный alias «#:<домен>» в директории, второй падает с M_ROOM_IN_USE
      // «Room alias already taken» сырой английской строкой.
      // ГРУППА исключена намеренно: безымянная группа легальна — _createGroup
      // шлёт groupName: null, и SDK считает имя по участникам.
      if (nameController.text.trim().isEmpty &&
          createGroupType != CreateGroupType.group) {
        setState(() => error = L10n.of(context).pleaseEnterAName);
        return;
      }

      setState(() {
        loading = true;
        error = null;
      });

      final avatar = this.avatar;
      avatarUrl ??= avatar == null ? null : await client.uploadContent(avatar);

      if (!mounted) return;

      switch (createGroupType) {
        case CreateGroupType.group:
          await _createGroup();
        case CreateGroupType.space:
          await _createSpace();
        case CreateGroupType.channel:
          await _createChannel();
      }
    } catch (e, s) {
      sdk.Logs().d('Unable to create group', e, s);
      setState(() {
        error = e;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => NewGroupView(this);
}

enum CreateGroupType { group, space, channel }
