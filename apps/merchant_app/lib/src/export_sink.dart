/// Where an exported file goes once the server has produced it.
///
/// An interface for the same reason as `ImageSource` and `TicketPrinter`: the
/// real thing is a platform channel that cannot run in a widget test, and the
/// flow around it is worth testing anyway.
///
/// **The share sheet is not here yet.** Handing a file to WhatsApp or Gmail
/// needs a plugin (`share_plus`), and adding one to satisfy a slice nobody
/// can test on this machine would be shipping an unverified dependency into
/// the one screen that handles a venue's books. What is here writes the file
/// where the platform allows and reports its path, which is enough to prove
/// the export works end to end; swapping in a sharer is a constructor
/// argument on the day the plugin lands.
library;

import 'dart:convert';
import 'dart:io';

/// What happened to the file, in words the merchant can be shown.
class ExportResult {
  const ExportResult({required this.path, required this.bytes});

  final String path;
  final int bytes;
}

abstract class ExportSink {
  /// Save or share [contents] under [filename]. Throws on failure.
  Future<ExportResult> deliver(String filename, String contents);
}

/// Writes the file to the platform's temporary directory.
///
/// Temporary rather than documents: this file is a hand-off, not a record.
/// The venue's books live on the server, and a copy left on a shared phone
/// in a lounge is a copy of somebody's takings that nobody is looking after.
class FileExportSink implements ExportSink {
  FileExportSink({Directory? directory}) : _directory = directory;

  final Directory? _directory;

  @override
  Future<ExportResult> deliver(String filename, String contents) async {
    final directory = _directory ?? Directory.systemTemp;
    final file = File('${directory.path}${Platform.pathSeparator}$filename');
    // UTF-8 explicitly: the server already put a byte order mark in front for
    // Excel's sake, and re-encoding as anything else would undo it.
    await file.writeAsBytes(utf8.encode(contents));
    return ExportResult(path: file.path, bytes: contents.length);
  }
}
