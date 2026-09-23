import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:liza/l10n/l10n.dart';
import 'package:liza/utils/monitoring.dart';

/// Persistent file logger that captures all [Logs] output events
/// and writes them to a rotating log file on disk.
///
/// Uses a [StringBuffer] + periodic sync writes instead of [IOSink] to avoid
/// "Bad state: StreamSink is bound to a stream" errors when log() is called
/// from zone error handlers while a flush is in progress.
class FileLogger {
  FileLogger._();
  static final FileLogger instance = FileLogger._();

  static const int _maxFileSizeBytes = 5 * 1024 * 1024; // 5 MB
  static const String _logFileName = 'liza.log';
  static const String _oldLogFileName = 'liza.old.log';

  File? _logFile;
  File? _oldLogFile;
  /// Mirror in user-visible documents directory so testers can retrieve
  /// the log from the Files app even when the UI is broken.
  File? _docsLogFile;

  final StringBuffer _buffer = StringBuffer();
  bool _initialized = false;
  bool _flushing = false;
  int _lastFlushedIndex = 0;

  /// Initialize the file logger. Safe to call multiple times.
  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    try {
      final dir = await getApplicationSupportDirectory();
      _logFile = File('${dir.path}/$_logFileName');
      _oldLogFile = File('${dir.path}/$_oldLogFileName');
      await _rotateIfNeeded();

      // Also set up documents directory mirror for Files app access
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        _docsLogFile = File('${docsDir.path}/$_logFileName');
        await _rotateDocsIfNeeded();
      } catch (e) {
        debugPrint('FileLogger: documents directory mirror failed: $e');
      }

      _initialized = true;

      final now = DateTime.now().toIso8601String();
      _buffer.writeln('\n=== Session started at $now ===\n');

      // Periodically drain the buffer to disk
      Timer.periodic(const Duration(seconds: 2), (_) => _drainBuffer());
    } catch (e) {
      debugPrint('FileLogger init failed: $e');
    }
  }

  /// Collect new SDK log events into the buffer.
  void _collectSdkLogs() {
    final events = Logs().outputEvents;
    if (_lastFlushedIndex >= events.length) return;
    for (var i = _lastFlushedIndex; i < events.length; i++) {
      final event = events[i];
      _formatLogEvent(event);
      // Мост в мониторинг: ошибки SDK, что не доходят до глобальных хендлеров
      // (sync, decrypt, парсинг). Monitoring сам фильтрует сеть/дубли/троттл.
      if (event.level == Level.error || event.level == Level.wtf) {
        Monitoring.captureSdkError(
          event.exception,
          event.stackTrace,
          event.title,
        );
      }
    }
    _lastFlushedIndex = events.length;
  }

  void _formatLogEvent(LogEvent event) {
    final timestamp = DateTime.now().toIso8601String();
    final level = event.level.toString().split('.').last.toUpperCase();
    _buffer.write('[$timestamp] [$level] ${event.title}');
    if (event.exception != null) {
      _buffer.write(' - ${event.exception}');
    }
    if (event.stackTrace != null) {
      _buffer.write('\n${event.stackTrace}');
    }
    _buffer.writeln();
  }

  /// Write a custom log line directly (for uncaught errors outside SDK).
  void log(String level, String message, [Object? error, StackTrace? stack]) {
    if (!_initialized) return;
    final timestamp = DateTime.now().toIso8601String();
    _buffer.write('[$timestamp] [$level] $message');
    if (error != null) _buffer.write(' - $error');
    if (stack != null) _buffer.write('\n$stack');
    _buffer.writeln();
  }

  /// Drain the buffer to disk. Uses synchronous file append to avoid
  /// IOSink state issues. Guarded against re-entrance.
  void _drainBuffer() {
    if (!_initialized || _flushing) return;
    _collectSdkLogs();
    if (_buffer.isEmpty) return;

    _flushing = true;
    try {
      final data = _buffer.toString();
      _buffer.clear();
      _logFile?.writeAsStringSync(data, mode: FileMode.append, flush: true);
      _docsLogFile?.writeAsStringSync(data, mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('FileLogger drain failed: $e');
    } finally {
      _flushing = false;
    }
  }

  Future<void> _rotateIfNeeded() async {
    if (_logFile == null) return;
    if (!await _logFile!.exists()) return;
    final size = await _logFile!.length();
    if (size > _maxFileSizeBytes) {
      if (await _oldLogFile!.exists()) {
        await _oldLogFile!.delete();
      }
      await _logFile!.rename(_oldLogFile!.path);
    }
  }

  Future<void> _rotateDocsIfNeeded() async {
    if (_docsLogFile == null) return;
    if (!await _docsLogFile!.exists()) return;
    final size = await _docsLogFile!.length();
    if (size > _maxFileSizeBytes) {
      await _docsLogFile!.delete();
    }
  }

  /// Лог-файлы (старый + текущий) как [XFile] для отправки.
  ///
  /// Источник — те же файлы, что и [readLogsText]; буфер сбрасывается перед
  /// чтением, чтобы попали последние записи. Пустой список — логов ещё нет.
  Future<List<XFile>> logXFiles() async {
    if (!_initialized || _logFile == null) return const [];
    // Drain any pending logs before sharing
    _drainBuffer();

    final files = <XFile>[];
    if (_oldLogFile != null && await _oldLogFile!.exists()) {
      files.add(XFile(_oldLogFile!.path, mimeType: 'text/plain'));
    }
    if (await _logFile!.exists()) {
      files.add(XFile(_logFile!.path, mimeType: 'text/plain'));
    }
    return files;
  }

  /// Share log files via the system share sheet.
  Future<void> shareLogs(BuildContext context) async {
    final files = await logXFiles();
    if (files.isEmpty) return;

    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        files: files,
        sharePositionOrigin:
            box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  /// Полный текст логов (старый + текущий файл), хронологически.
  ///
  /// Источник — ФАЙЛ, а не [Logs.outputEvents]: файл хранит всю историю
  /// (прошлые сессии, маркеры `=== Session started ===`, uncaught-ошибки),
  /// тогда как `outputEvents` — только текущая сессия в памяти.
  Future<String> readLogsText() async {
    if (!_initialized) return '';
    // Сбросить буфер перед чтением — иначе потеряем последние ~2с записей.
    _drainBuffer();
    final parts = <String>[];
    if (_oldLogFile != null && await _oldLogFile!.exists()) {
      parts.add(await _oldLogFile!.readAsString());
    }
    if (_logFile != null && await _logFile!.exists()) {
      parts.add(await _logFile!.readAsString());
    }
    return parts.join('\n');
  }

  // Консервативно ниже потолка Binder-транзакции (~1 МБ): больший ClipData
  // на Android роняет приложение через TransactionTooLargeException.
  static const int _clipboardSafeBytes = 256 * 1024;

  /// Скопировать текст лога в буфер обмена.
  ///
  /// Основной путь выгрузки на Android: share файла отдаёт `content://`-URI,
  /// из которого «Скопировать» кладёт в буфер ссылку, а не содержимое. Здесь
  /// в буфер ложится именно текст — его можно вставить в чат поддержки.
  Future<void> copyLogsToClipboard(BuildContext context) async {
    // Захватываем до await — нельзя трогать context через async gap.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    final full = await readLogsText();
    if (full.trim().isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.logsEmpty)));
      return;
    }
    var text = full;
    var truncated = false;
    // Порог считаем в БАЙТАХ (кириллица = 2 байта/символ), не в code units.
    if (utf8.encode(full).length > _clipboardSafeBytes) {
      // Хвост важнее головы — свежие ошибки в конце лога.
      var cut = full.length - (_clipboardSafeBytes ~/ 2);
      if (cut < 0) cut = 0;
      // Резать по границе строки, иначе можно разорвать UTF-8/стектрейс.
      final nl = full.indexOf('\n', cut);
      if (nl != -1) cut = nl + 1;
      text = '${l10n.logTruncated}${full.substring(cut)}';
      truncated = true;
    }
    await Clipboard.setData(ClipboardData(text: text));
    messenger.showSnackBar(
      SnackBar(
        content: Text(truncated ? l10n.logsCopiedTruncated : l10n.logsCopied),
      ),
    );
  }

  /// Get the total size of log files in bytes.
  Future<int> get logFilesSize async {
    if (!_initialized || _logFile == null) return 0;
    var size = 0;
    if (await _logFile!.exists()) size += await _logFile!.length();
    if (_oldLogFile != null && await _oldLogFile!.exists()) {
      size += await _oldLogFile!.length();
    }
    return size;
  }
}
