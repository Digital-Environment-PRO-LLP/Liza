import 'package:flutter/material.dart';

import 'package:matrix/matrix.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/pages/archive/archive_view.dart';
import 'package:liza/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:liza/widgets/future_loading_dialog.dart';
import 'package:liza/widgets/matrix.dart';

class Archive extends StatefulWidget {
  const Archive({super.key});

  @override
  ArchiveController createState() => ArchiveController();
}

class ArchiveController extends State<Archive> {
  List<Room> archive = [];

  Future<List<Room>> getArchive(BuildContext context) async {
    if (archive.isNotEmpty) return archive;
    return archive = await Matrix.of(context).client.loadArchive();
  }

  /// Принимает [Room], а не индекс: подтверждение — это пауза на решение
  /// человека, за которую список может перестроиться (параллельное «Очистить
  /// архив», новый архивный чат). Удаление по идентичности — SDK сравнивает
  /// `Room` по `id`.
  void forgetRoomAction(Room room) async {
    await showFutureLoadingDialog(
      context: context,
      future: () async {
        Logs().v('Forget room ${room.getLocalizedDisplayname()}');
        await room.forget();
        archive.remove(room);
      },
    );
    if (!mounted) return;
    setState(() {});
  }

  void forgetAllAction() async {
    final archive = this.archive;
    final client = Matrix.of(context).client;
    if (archive.isEmpty) return;
    if (await showOkCancelAlertDialog(
          useRootNavigator: false,
          context: context,
          title: L10n.of(context).areYouSure,
          okLabel: L10n.of(context).yes,
          cancelLabel: L10n.of(context).cancel,
          message: L10n.of(context).clearArchive,
          isDestructive: true,
        ) !=
        OkCancelResult.ok) {
      return;
    }
    await showFutureLoadingDialog(
      context: context,
      futureWithProgress: (onProgress) async {
        final count = archive.length;
        while (archive.isNotEmpty) {
          onProgress(1 - (archive.length / count));
          Logs().v('Forget room ${archive.last.getLocalizedDisplayname()}');
          await archive.last.forget();
          archive.removeLast();
        }
      },
    );
    client.clearArchivesFromCache();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ArchiveView(this);
}
