import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/records.dart';
import 'database.dart';

abstract interface class SyncRemote {
  Future<Json> apply(Json operation);
  Future<Json> changes(int cursor);
}

class SupabaseRemote implements SyncRemote {
  SupabaseRemote(this.client);
  final SupabaseClient client;
  @override
  Future<Json> apply(Json op) async => Map<String, dynamic>.from(
    await client.rpc(
          'apply_operation',
          params: {
            'p_operation_id': op['operation_id'],
            'p_kind': op['kind'],
            'p_id': op['record_id'],
            'p_expected': op['expected_version'],
            'p_record': jsonDecode(op['payload'] as String),
          },
        )
        as Map,
  );
  @override
  Future<Json> changes(int cursor) async => Map<String, dynamic>.from(
    await client.rpc(
          'pull_changes',
          params: {'p_cursor': cursor, 'p_limit': 200},
        )
        as Map,
  );
}

class SyncEngine {
  SyncEngine(this.db, this.remote, this.changed);
  final DiaryDatabase db;
  final SyncRemote remote;
  final void Function() changed;
  bool _running = false, _stopped = false;
  Timer? _timer;
  String? error;
  DateTime? lastSuccess;
  int _failures = 0;

  void start() {
    _stopped = false;
    unawaited(run());
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
  }

  Future<void> run() async {
    if (_running || _stopped) return;
    _running = true;
    _timer?.cancel();
    try {
      final blocked = <String>{};
      for (final operation in await db.operations()) {
        if (_stopped) return;
        final key = '${operation['kind']}:${operation['record_id']}';
        if (operation['status'] == 'conflict' || blocked.contains(key)) {
          blocked.add(key);
          continue;
        }
        final response = await remote
            .apply(operation)
            .timeout(const Duration(seconds: 15));
        if (_stopped) return;
        if (response['status'] == 'conflict') {
          await db.conflict(
            operation,
            Map<String, dynamic>.from(response['record'] as Map? ?? {}),
            'На сервере появилась другая версия',
          );
          blocked.add(key);
        } else {
          await db.acknowledge(
            operation,
            Record.fromJson(
              Map<String, dynamic>.from(response['record'] as Map),
            ),
          );
        }
      }
      var cursor = await db.cursor();
      while (!_stopped) {
        final page = await remote
            .changes(cursor)
            .timeout(const Duration(seconds: 15));
        if (_stopped) return;
        final next = page['cursor'] as int;
        if (next < cursor) throw StateError('Сервер вернул неверный курсор');
        await db.applyPage(
          (page['records'] as List)
              .map((r) => Record.fromJson(Map<String, dynamic>.from(r as Map)))
              .toList(),
          next,
        );
        if (page['has_more'] != true) break;
        if (next == cursor) {
          throw StateError('Курсор синхронизации не продвигается');
        }
        cursor = next;
      }
      lastSuccess = DateTime.now();
      error = null;
      _failures = 0;
    } catch (e) {
      error = e is AuthException
          ? 'Нужен повторный вход. Локальные данные сохранены.'
          : 'Синхронизация недоступна. Изменения сохранены на устройстве.';
      _failures++;
    } finally {
      _running = false;
      if (!_stopped) {
        changed();
        final seconds = _failures == 0
            ? 45
            : min(300, 5 * pow(2, min(_failures, 5)).toInt()) +
                  Random().nextInt(5);
        _timer = Timer(Duration(seconds: seconds), () => unawaited(run()));
      }
    }
  }

  Future<void> dispose() async {
    stop();
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
  }
}
