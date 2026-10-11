import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../domain/records.dart';
import 'database.dart';

class BackupPreview {
  const BackupPreview(
    this.records,
    this.newCount,
    this.sameCount,
    this.conflicts,
  );
  final List<Record> records;
  final int newCount, sameCount;
  final List<Record> conflicts;
}

String _digest(Record r) => sha256
    .convert(
      utf8.encode(
        jsonEncode(
          _canonical({
            'kind': r.kind,
            'id': r.id,
            'data': r.data,
            'deleted': r.deleted,
          }),
        ),
      ),
    )
    .toString();
Object? _canonical(Object? v) {
  if (v is Map) {
    final keys = v.keys.cast<String>().toList()..sort();
    return {for (final k in keys) k: _canonical(v[k])};
  }
  if (v is List) return v.map(_canonical).toList();
  return v;
}

class BackupService {
  BackupService(this.db);
  final DiaryDatabase db;
  Future<String> export() async => jsonEncode({
    'format': 'calorie-diary',
    'version': 1,
    'created_at': DateTime.now().toUtc().toIso8601String(),
    'records': (await db.records(
      deleted: true,
    )).map((r) => r.toJson()).toList(),
  });

  Future<BackupPreview> preview(String source) async {
    if (utf8.encode(source).length > 20 * 1024 * 1024)
      throw const FormatException('Файл больше 20 МБ');
    final j = jsonDecode(source);
    if (j is! Map ||
        j['format'] != 'calorie-diary' ||
        j['version'] != 1 ||
        j['records'] is! List) {
      throw const FormatException('Неподдерживаемый формат резервной копии');
    }
    final values = <Record>[];
    final seen = <String>{};
    for (final raw in j['records'] as List) {
      final r = Record.fromJson(Map<String, dynamic>.from(raw as Map));
      validateRecord(r);
      if (!seen.add('${r.kind}:${r.id}'))
        throw const FormatException('Повторяющийся UUID');
      values.add(r);
    }
    var fresh = 0, same = 0;
    final conflicts = <Record>[];
    for (final r in values) {
      final existing = await db.find(r.kind, r.id);
      if (existing == null) {
        fresh++;
      } else if (_digest(existing) == _digest(r)) {
        same++;
      } else {
        conflicts.add(r);
      }
    }
    return BackupPreview(values, fresh, same, conflicts);
  }

  /// Safe merge inserts missing records only. Conflicts preserve current data.
  Future<void> merge(BackupPreview preview) => db.transaction(() async {
    for (final r in preview.records) {
      if (await db.find(r.kind, r.id) != null) continue;
      await db.save(r.copy(version: 0, localOnly: r.kind == 'product'));
    }
  });
}
