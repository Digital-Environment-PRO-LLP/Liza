import 'package:flutter/material.dart';

import 'package:liza/pages/chat/events/media_caption.dart';
import 'package:matrix/matrix.dart';

import 'package:liza/config/app_config.dart';
import 'package:liza/utils/chat_topology.dart';
import 'package:liza/utils/file_description.dart';
import 'package:liza/utils/matrix_sdk_extensions/event_extension.dart';

class MessageDownloadContent extends StatelessWidget {
  final Event event;
  final Color textColor;
  final Color linkColor;

  /// Время сообщения (Liza-стиль) — в конце ряда, справа от кнопки
  /// скачивания, по центру по вертикали.
  final Widget? trailing;

  const MessageDownloadContent(
    this.event, {
    required this.textColor,
    required this.linkColor,
    this.trailing,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final filename = event.content.tryGet<String>('filename') ?? event.body;
    final filetype = filename.contains('.')
        ? filename.split('.').last.toUpperCase()
        : event.content
                  .tryGetMap<String, dynamic>('info')
                  ?.tryGet<String>('mimetype')
                  ?.toUpperCase() ??
              'UNKNOWN';
    final sizeString = event.sizeString ?? '?MB';
    final fileDescription = event.fileDescription;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 8,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
            // `openFile` — ТОЖЕ вынос контента, а не «просто просмотр»: на web
            // он делегирует прямо в `saveFile` (скачивание браузером), а на
            // нативных пишет РАСШИФРОВАННЫЕ байты во временный файл и открывает
            // во внешнем приложении, откуда доступны «Сохранить как» и
            // «Поделиться» средствами ОС (`event_extension.dart`). Поэтому гейт
            // тот же, что у кнопки «Скачать» ниже (LABA-2541).
            onTap: event.room.isContentProtected
                ? null
                : () => event.openFile(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    CircleAvatar(
                      backgroundColor: textColor.withAlpha(32),
                      child: Icon(_iconForFiletype(filetype), color: textColor),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            filename,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '$sizeString | $filetype',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: textColor, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Кнопка «Скачать» сохраняет файл на устройство — вынос
                    // контента, запрещённый владельцем защищённого чата. Тап по
                    // самой карточке (onTap выше) закрыт тем же гейтом: он
                    // выносит файл ничуть не меньше.
                    if (!event.room.isContentProtected)
                      IconButton(
                        onPressed: () => event.saveFile(context),
                        icon: Icon(
                          Icons.file_download_outlined,
                          color: textColor.withAlpha(180),
                          size: 20,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: null,
                      ),
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing!,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (fileDescription != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            // Подпись файла с разметкой (XL formatted_body) → HTML (LABA-2207).
            child: MediaCaption(
              event: event,
              textColor: textColor,
              linkColor: linkColor,
            ),
          ),
      ],
    );
  }

  IconData _iconForFiletype(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_outlined;
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_outlined;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_outlined;
      case 'txt':
      case 'md':
        return Icons.article_outlined;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }
}
