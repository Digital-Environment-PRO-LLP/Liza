import 'dart:async';

import 'package:flutter/material.dart';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/file_logger.dart';
import 'package:liza/utils/file_selector.dart';
import 'package:liza/utils/platform_infos.dart';
import 'package:liza/utils/show_scaffold_dialog.dart';
import 'package:liza/utils/user_handle_service.dart';
import 'package:liza/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:liza/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:liza/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:liza/widgets/future_loading_dialog.dart';
import 'package:liza/widgets/share_scaffold_dialog.dart';
import '../../widgets/matrix.dart';
import 'settings_view.dart';

/// Зеркалит серверный `MAX_DISPLAYNAME_LEN`
/// (`servers/synapse/src/synapse/handlers/profile.py:58`). Расхождение молча
/// вернёт 400 «Displayname is too long» уже после нажатия «Ок».
const int maxDisplaynameLength = 256;

/// Диалог смены отображаемого имени. Вынесен из [SettingsController], чтобы
/// страж реестра рендерил РЕАЛЬНЫЙ диалог, а не его реплику.
///
/// `maxLength` считает грапемные кластеры, а Synapse — кодпойнты, поэтому
/// лимит держат ДВА барьера: формматтер (обрезает ввод) и `validator` по
/// `runes` (ловит эмодзи-грапемы и подставленное `initialText`, которое
/// формматтер не трогает).
Future<String?> showDisplaynameInputDialog(
  BuildContext context, {
  required String? initialText,
}) => showTextInputDialog(
  useRootNavigator: false,
  context: context,
  title: L10n.of(context).editDisplayname,
  okLabel: L10n.of(context).ok,
  cancelLabel: L10n.of(context).cancel,
  initialText: initialText,
  minLines: 1,
  maxLines: 1,
  maxLength: maxDisplaynameLength,
  validator: (input) => input.runes.length > maxDisplaynameLength
      ? L10n.of(context).displaynameTooLong
      : null,
);

class Settings extends StatefulWidget {
  const Settings({super.key, this.handleService});

  /// Подменяется в тестах — по умолчанию контроллер создаёт свой сервис
  /// поверх `AppConfig.authProxyBaseUrl` и текущего Matrix-клиента.
  final UserHandleService? handleService;

  @override
  SettingsController createState() => SettingsController();
}

class SettingsController extends State<Settings> {
  Future<Profile>? profileFuture;
  bool profileUpdated = false;

  void updateProfile() => setState(() {
    profileUpdated = true;
    profileFuture = null;
  });

  void setDisplaynameAction() async {
    final profile = await profileFuture;
    final input = await showDisplaynameInputDialog(
      context,
      initialText:
          profile?.displayName ?? Matrix.of(context).client.userID!.localpart,
    );
    if (input == null) return;
    final matrix = Matrix.of(context);
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setProfileField(
        matrix.client.userID!,
        'displayname',
        {'displayname': input},
      ),
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  void logoutAction() async {
    final noBackup = showChatBackupBanner == true;
    if (await showOkCancelAlertDialog(
          useRootNavigator: false,
          context: context,
          title: L10n.of(context).areYouSureYouWantToLogout,
          message: L10n.of(context).noBackupWarning,
          isDestructive: noBackup,
          okLabel: L10n.of(context).logout,
          cancelLabel: L10n.of(context).cancel,
        ) ==
        OkCancelResult.cancel) {
      return;
    }
    final matrix = Matrix.of(context);
    matrix.markExplicitLogout();
    await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.logout(),
    );
  }

  void setAvatarAction() async {
    final profile = await profileFuture;
    final actions = [
      if (PlatformInfos.isMobile)
        AdaptiveModalAction(
          value: AvatarAction.camera,
          label: L10n.of(context).openCamera,
          isDefaultAction: true,
          icon: const Icon(Icons.camera_alt_outlined),
        ),
      AdaptiveModalAction(
        value: AvatarAction.file,
        label: L10n.of(context).openGallery,
        icon: const Icon(Icons.photo_outlined),
      ),
      if (profile?.avatarUrl != null)
        AdaptiveModalAction(
          value: AvatarAction.remove,
          label: L10n.of(context).removeYourAvatar,
          isDestructive: true,
          icon: const Icon(Icons.delete_outlined),
        ),
    ];
    final action = actions.length == 1
        ? actions.single.value
        : await showModalActionPopup<AvatarAction>(
            context: context,
            title: L10n.of(context).changeYourAvatar,
            cancelLabel: L10n.of(context).cancel,
            actions: actions,
          );
    if (action == null) return;
    final matrix = Matrix.of(context);
    if (action == AvatarAction.remove) {
      final success = await showFutureLoadingDialog(
        context: context,
        future: () => matrix.client.setAvatar(null),
      );
      if (success.error == null) {
        updateProfile();
      }
      return;
    }
    MatrixFile file;
    if (PlatformInfos.isMobile) {
      final result = await ImagePicker().pickImage(
        source: action == AvatarAction.camera
            ? ImageSource.camera
            : ImageSource.gallery,
        imageQuality: 50,
      );
      if (result == null) return;
      file = MatrixFile(bytes: await result.readAsBytes(), name: result.path);
    } else {
      final result = await selectFiles(context, type: FileType.image);
      final pickedFile = result.firstOrNull;
      if (pickedFile == null) return;
      file = MatrixFile(
        bytes: await pickedFile.readAsBytes(),
        name: pickedFile.name,
      );
    }
    final success = await showFutureLoadingDialog(
      context: context,
      future: () => matrix.client.setAvatar(file),
    );
    if (success.error == null) {
      updateProfile();
    }
  }

  @override
  void initState() {
    WidgetsBinding.instance.addPostFrameCallback((_) => checkBootstrap());
    WidgetsBinding.instance.addPostFrameCallback((_) => checkHandleGate());

    super.initState();
  }

  @override
  void dispose() {
    // Закрываем только сервис, созданный самим контроллером — переданный
    // извне (в тестах) остаётся под управлением вызывающей стороны.
    _ownHandleService?.dispose();
    super.dispose();
  }

  // Пока ответ не пришёл — пункт «Имя пользователя» не показываем (не
  // мигаем им); ошибка сети трактуется как «фича выключена», а не как
  // повод сломать экран настроек (см. task-6-brief).
  bool handleGateAvailable = false;

  // Свой ник, если он уже задан — заполняется тем же fetchOwn, что решает
  // гейт. Передаём его в userIdentifier() в шапке настроек третьим
  // параметром: точнее похода в кэш и сразу отражает свежее сохранение,
  // не дожидаясь резолва (см. task-6-brief, довесок B5).
  String? ownHandle;

  UserHandleService? _ownHandleService;

  void checkHandleGate() async {
    final matrix = Matrix.of(context);
    final service = widget.handleService ??
        (_ownHandleService ??= UserHandleService(
          baseUrl: AppConfig.authProxyBaseUrl,
          accessTokenProvider: () => matrix.client.accessToken,
          serverNameProvider: () =>
              matrix.client.userID?.split(':').last ?? '',
        ));
    HandleState state;
    try {
      state = await service.fetchOwn();
    } catch (_) {
      // fetchOwn сам ловит сетевые сбои и отдаёт HandleState.disabled —
      // этот catch страхует только от исключения из подставного сервиса в
      // тестах (available:false, пункта нет, экран настроек цел).
      state = HandleState.disabled;
    }
    if (!mounted) return;
    setState(() {
      handleGateAvailable = state.available;
      ownHandle = state.handle;
    });
  }

  void checkBootstrap() async {
    final client = Matrix.of(context).client;
    if (!client.encryptionEnabled) return;
    await client.accountDataLoading;
    await client.userDeviceKeysLoading;
    if (client.prevBatch == null) {
      await client.onSync.stream.first;
    }
    final crossSigning =
        await client.encryption?.crossSigning.isCached() ?? false;
    final needsBootstrap =
        await client.encryption?.keyManager.isCached() == false ||
        client.encryption?.crossSigning.enabled == false ||
        crossSigning == false;
    final isUnknownSession = client.isUnknownSession;
    setState(() {
      showChatBackupBanner = needsBootstrap || isUnknownSession;
    });
  }

  bool? crossSigningCached;
  bool? showChatBackupBanner;

  void firstRunBootstrapAction([dynamic _]) async {
    // Defence-in-depth: the toggle that triggers this is wrapped in
    // IfDeveloper, but never trust UI to be the only gate.
    if (!Matrix.of(context).isCurrentUserDeveloper) return;
    if (showChatBackupBanner != true) {
      showOkAlertDialog(
        context: context,
        title: L10n.of(context).chatBackup,
        message: L10n.of(context).onlineKeyBackupEnabled,
        okLabel: L10n.of(context).close,
      );
      return;
    }
    await context.push('/backup');
    checkBootstrap();
  }

  void logsMenuAction(BuildContext context) async {
    final action = await showModalActionPopup<LogAction>(
      context: context,
      title: L10n.of(context).appLogs,
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          value: LogAction.copy,
          label: L10n.of(context).copyLogs,
          isDefaultAction: true,
          icon: const Icon(Icons.content_copy_outlined),
        ),
        AdaptiveModalAction(
          value: LogAction.sendToChat,
          label: L10n.of(context).sendLogsToChat,
          icon: const Icon(Icons.send_outlined),
        ),
        AdaptiveModalAction(
          value: LogAction.shareFile,
          label: L10n.of(context).shareLogFile,
          icon: const Icon(Icons.share_outlined),
        ),
        AdaptiveModalAction(
          value: LogAction.view,
          label: L10n.of(context).openLogViewer,
          icon: const Icon(Icons.description_outlined),
        ),
      ],
    );
    if (action == null || !context.mounted) return;
    switch (action) {
      case LogAction.copy:
        await FileLogger.instance.copyLogsToClipboard(context);
      case LogAction.sendToChat:
        await sendLogsToChatAction(context);
      case LogAction.shareFile:
        await FileLogger.instance.shareLogs(context);
      case LogAction.view:
        context.go('/logs');
    }
  }

  /// Отправить лог-файл в чат Liza минуя системный шит. На Android это
  /// единственный надёжный путь: OS-share отдаёт content://-URI, а self-share
  /// в singleTask-приложение ненадёжен. Внутренний [ShareScaffoldDialog]
  /// (Liza-DM закреплён первым) → [SendFileDialog] читает файл in-process.
  Future<void> sendLogsToChatAction(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    final files = await FileLogger.instance.logXFiles();
    if (!context.mounted) return;
    if (files.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.logsEmpty)));
      return;
    }
    showScaffoldDialog(
      context: context,
      builder: (context) => ShareScaffoldDialog(
        items: files.map<ShareItem>(FileShareItem.new).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    profileFuture ??= client.getProfileFromUserId(client.userID!);
    return SettingsView(this);
  }
}

enum AvatarAction { camera, file, remove }

enum LogAction { copy, sendToChat, shareFile, view }
