import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// File + app helpers for Vektor on Android.
class VektorTools {
  /// Workspace under app documents
  Future<Directory> workspace() async {
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'vektor_workspace'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<List<FileSystemEntity>> listFiles() async {
    final dir = await workspace();
    final list = dir.listSync().toList();
    list.sort((a, b) => a.path.compareTo(b.path));
    return list;
  }

  Future<String> writeFile(String name, String content) async {
    final dir = await workspace();
    final safe = name.replaceAll(RegExp(r'[/\\]'), '_');
    final f = File(p.join(dir.path, safe));
    await f.writeAsString(content, encoding: utf8);
    return f.path;
  }

  Future<String?> readFile(String name) async {
    final dir = await workspace();
    final f = File(p.join(dir.path, name));
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  Future<String?> importFile() async {
    final r = await FilePicker.platform.pickFiles(withData: true);
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.single;
    final dir = await workspace();
    final dest = File(p.join(dir.path, f.name));
    if (f.bytes != null) {
      await dest.writeAsBytes(f.bytes!);
    } else if (f.path != null) {
      await File(f.path!).copy(dest.path);
    }
    return dest.path;
  }

  Future<String> buildZip({String? projectName}) async {
    final dir = await workspace();
    final archive = Archive();
    for (final e in dir.listSync()) {
      if (e is File) {
        final name = p.basename(e.path);
        final data = await e.readAsBytes();
        archive.addFile(ArchiveFile(name, data.length, data));
      }
    }
    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) throw Exception('ZIP encode failed');
    final outDir = await getTemporaryDirectory();
    final name = '${projectName ?? 'vektor-project'}-${DateTime.now().millisecondsSinceEpoch}.zip';
    final out = File(p.join(outDir.path, name));
    await out.writeAsBytes(bytes);
    return out.path;
  }

  Future<void> sharePath(String path) async {
    await Share.shareXFiles([XFile(path)], text: 'Vektor');
  }

  Future<void> openPath(String path) async {
    await OpenFilex.open(path);
  }

  /// Launch common Android apps / intents
  Future<String> openApp(String query) async {
    final q = query.toLowerCase().trim();
    // package map for common apps
    const packages = {
      'youtube': 'com.google.android.youtube',
      'ютуб': 'com.google.android.youtube',
      'chrome': 'com.android.chrome',
      'браузер': 'com.android.chrome',
      'telegram': 'org.telegram.messenger',
      'телеграм': 'org.telegram.messenger',
      'whatsapp': 'com.whatsapp',
      'ватсап': 'com.whatsapp',
      'настройки': 'com.android.settings',
      'settings': 'com.android.settings',
      'камера': 'com.android.camera',
      'camera': 'com.android.camera',
      'галерея': 'com.android.gallery3d',
      'карты': 'com.google.android.apps.maps',
      'maps': 'com.google.android.apps.maps',
      'почта': 'com.google.android.gm',
      'gmail': 'com.google.android.gm',
      'телефон': 'com.android.dialer',
      'phone': 'com.android.dialer',
    };

    for (final e in packages.entries) {
      if (q.contains(e.key)) {
        final intent = AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: e.value,
          category: 'android.intent.category.LAUNCHER',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        try {
          await intent.launch();
          return 'Открываю «${e.key}» (${e.value})';
        } catch (_) {
          // try view market
        }
      }
    }

    // Web search / URL
    if (q.startsWith('http://') || q.startsWith('https://')) {
      final intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: query.trim(),
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      );
      await intent.launch();
      return 'Открываю ссылку';
    }

    // Generic search intent
    final intent = AndroidIntent(
      action: 'android.intent.action.VIEW',
      data: 'https://www.google.com/search?q=${Uri.encodeComponent(query)}',
      flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
    );
    await intent.launch();
    return 'Ищу: $query';
  }

  Future<String> handleCommand(String text) async {
    final t = text.trim();
    final lower = t.toLowerCase();

    // open app
    final open = RegExp(r'^(открой|open)\s+(.+)$', caseSensitive: false).firstMatch(t);
    if (open != null) {
      return openApp(open.group(2)!);
    }

    // list files
    if (RegExp(r'^(файлы|list files|список файлов)\s*$', caseSensitive: false).hasMatch(t)) {
      final list = await listFiles();
      if (list.isEmpty) return 'Рабочая папка пуста.';
      return 'Файлы:\n${list.map((e) => '• ${p.basename(e.path)}').join('\n')}';
    }

    // save note as file
    final save = RegExp(r'^(сохрани файл|save file)\s+(\S+)\s*[:\n]\s*([\s\S]+)$', caseSensitive: false).firstMatch(t);
    if (save != null) {
      final path = await writeFile(save.group(2)!, save.group(3)!);
      return 'Сохранено: $path';
    }

    // import
    if (RegExp(r'^(импорт|import|загрузить файл)\s*$', caseSensitive: false).hasMatch(t)) {
      final path = await importFile();
      return path == null ? 'Отменено.' : 'Импортирован: $path';
    }

    // zip
    if (RegExp(r'^(zip|собрать zip|архив)\s*$', caseSensitive: false).hasMatch(lower)) {
      final path = await buildZip();
      await sharePath(path);
      return 'ZIP готов и открыт для отправки:\n$path';
    }

    return '';
  }
}
