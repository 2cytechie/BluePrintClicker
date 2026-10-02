import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/blueprint.dart';

/// 脚本 JSON 文件存储：应用文档目录/scripts/<名称>.bpc.json
class ScriptStorage {
  Directory? _dir;

  Future<Directory> get dir async {
    if (_dir != null) return _dir!;
    final doc = await getApplicationDocumentsDirectory();
    final d = Directory('${doc.path}/blueprint_clicker/scripts');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  Future<List<BlueprintScript>> listScripts() async {
    final d = await dir;
    final files = await d
        .list()
        .where((e) => e is File && e.path.endsWith('.bpc.json'))
        .cast<File>()
        .toList();
    final scripts = <BlueprintScript>[];
    for (final f in files) {
      try {
        final s = BlueprintScript.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
        scripts.add(s);
      } catch (_) {
        // 损坏文件跳过
      }
    }
    scripts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return scripts;
  }

  Future<void> save(BlueprintScript s) async {
    final d = await dir;
    s.updatedAt = DateTime.now();
    final f = File('${d.path}/${_safeName(s.name)}.bpc.json');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(s.toJson()));
  }

  Future<void> rename(BlueprintScript s, String newName) async {
    final d = await dir;
    final old = File('${d.path}/${_safeName(s.name)}.bpc.json');
    s.name = newName;
    await save(s);
    if (old.path != '${d.path}/${_safeName(newName)}.bpc.json' && await old.exists()) {
      await old.delete();
    }
  }

  Future<void> delete(String name) async {
    final d = await dir;
    final f = File('${d.path}/${_safeName(name)}.bpc.json');
    if (await f.exists()) await f.delete();
  }

  Future<BlueprintScript?> load(String name) async {
    final d = await dir;
    final f = File('${d.path}/${_safeName(name)}.bpc.json');
    if (!await f.exists()) return null;
    return BlueprintScript.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
  }

  Future<BlueprintScript> duplicate(BlueprintScript s, String newName) async {
    final copy = s.copy()..name = newName;
    await save(copy);
    return copy;
  }

  /// 导出到用户选择的文件（file_selector 由 UI 层提供目标路径）
  Future<String> exportToString(BlueprintScript s) async =>
      const JsonEncoder.withIndent('  ').convert(s.toJson());

  Future<BlueprintScript> importFromString(String json, {String? fallbackName}) async {
    final s = BlueprintScript.fromJson(jsonDecode(json) as Map<String, dynamic>);
    if (fallbackName != null && fallbackName.isNotEmpty && s.name.isEmpty) s.name = fallbackName;
    await save(s);
    return s;
  }

  String _safeName(String name) {
    final n = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return n.isEmpty ? '未命名' : n;
  }
}

/// 录制会话持久化：应用文档目录/recordings/*.json
class RecordingStorage {
  Directory? _dir;

  Future<Directory> get dir async {
    if (_dir != null) return _dir!;
    final doc = await getApplicationDocumentsDirectory();
    final d = Directory('${doc.path}/blueprint_clicker/recordings');
    if (!await d.exists()) await d.create(recursive: true);
    _dir = d;
    return d;
  }

  Future<void> save(Recording r) async {
    final d = await dir;
    final f = File('${d.path}/${r.id}.json');
    await f.writeAsString(jsonEncode(r.toJson()));
  }

  Future<List<Recording>> list() async {
    final d = await dir;
    final files = await d.list().cast<File>().toList();
    final out = <Recording>[];
    for (final f in files) {
      try {
        out.add(Recording.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {}
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> delete(String id) async {
    final d = await dir;
    final f = File('${d.path}/$id.json');
    if (await f.exists()) await f.delete();
  }
}

/// 数据存取节点的持久化 KV 存储：应用文档目录/data_store.json
class DataStore {
  static File? _file;
  static Directory? _overrideDir;

  /// 测试注入：覆盖存储目录（跳过 path_provider 插件）
  static void overrideDir(Directory dir) => _overrideDir = dir;

  static Future<File> get file async {
    if (_overrideDir != null) {
      final f = File('${_overrideDir!.path}/data_store.json');
      if (!await f.exists()) await f.create(recursive: true);
      return f;
    }
    if (_file != null) return _file!;
    final doc = await getApplicationDocumentsDirectory();
    final f = File('${doc.path}/blueprint_clicker/data_store.json');
    if (!await f.exists()) await f.create(recursive: true);
    _file = f;
    return f;
  }

  static Future<Map<String, Object>> _readAll() async {
    final f = await file;
    if (!await f.exists() || (await f.length()) == 0) return {};
    try {
      return Map<String, Object>.from(jsonDecode(await f.readAsString()) as Map);
    } catch (_) {
      return {};
    }
  }

  static Future<void> set(String key, Object value) async {
    final all = await _readAll();
    all[key] = value;
    final f = await file;
    await f.writeAsString(jsonEncode(all));
  }

  static Future<Object?> get(String key) async => (await _readAll())[key];
}
