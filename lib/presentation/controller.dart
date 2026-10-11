import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../data/database.dart';
import '../data/sync.dart';
import '../domain/nutrition.dart';
import '../domain/records.dart';

final diaryProvider = ChangeNotifierProvider<DiaryController>(
  (ref) => DiaryController(),
);

class DiaryController extends ChangeNotifier {
  DiaryDatabase? db;
  SyncEngine? sync;
  List<Record> records = [];
  List<Json> operations = [];
  String? userId;
  bool loading = true;
  int accountGeneration = 0;
  String? failure;
  DateTime day = DateTime.now();
  StreamSubscription<AuthState>? _auth;
  Future<void> _switchQueue = Future.value();
  bool _disposed = false;
  SupabaseClient get client => Supabase.instance.client;

  Future<void> initialize() async {
    await _auth?.cancel();
    _switchQueue = _switchQueue.then(
      (_) => _activate(client.auth.currentUser?.id),
    );
    _auth = client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.passwordRecovery) {
        needsPassword = true;
        notifyListeners();
      }
      final id = event.session?.user.id;
      _switchQueue = _switchQueue.then((_) => _activate(id));
    });
    await _switchQueue;
  }

  bool needsPassword = false;

  Future<void> _activate(String? id) async {
    if (_disposed || (userId == id && !loading)) return;
    loading = true;
    accountGeneration++;
    notifyListeners();
    await sync?.dispose();
    sync = null;
    await db?.close();
    db = null;
    records = [];
    operations = [];
    userId = id;
    try {
      if (id != null) {
        if (!uuidPattern.hasMatch(id)) {
          throw StateError('Неверный идентификатор аккаунта');
        }
        final dir = await getApplicationSupportDirectory();
        db = DiaryDatabase(File('${dir.path}/diary_$id.sqlite'));
        await reload();
        sync = SyncEngine(
          db!,
          SupabaseRemote(client),
          () => unawaited(reload()),
        );
        sync!.start();
      }
      failure = null;
    } catch (_) {
      failure = 'Не удалось открыть локальную базу. Данные не удалены.';
    }
    loading = false;
    if (!_disposed) notifyListeners();
  }

  Future<void> reload() async {
    final current = db;
    if (current == null) return;
    final loaded = await current.records();
    final pending = await current.operations();
    if (db != current || _disposed) return;
    records = loaded;
    operations = pending;
    notifyListeners();
  }

  List<Record> of(String kind) => records.where((r) => r.kind == kind).toList();
  List<Record> get entries =>
      of('entry').where((r) => r.data['day'] == dayKey(day)).toList();
  Record? get goal => goalForDay(records, day);

  String get theme => of('settings').isEmpty
      ? 'dark'
      : of('settings').first.data['theme'] as String;
  void selectDay(DateTime value) {
    day = value;
    notifyListeners();
  }

  Future<Record> save(
    String kind,
    Json data, {
    Record? previous,
    bool localOnly = false,
  }) async {
    final result = await db!.save(
      Record(
        id: previous?.id ?? _newId(kind, data),
        kind: kind,
        data: data,
        version: previous?.version ?? 0,
        localOnly: previous?.localOnly ?? localOnly,
      ),
    );
    await reload();
    unawaited(sync?.run());
    return result;
  }

  Future<Record> remove(Record value) async {
    final latest = await db!.find(value.kind, value.id);
    final removed = await db!.save(latest!.copy(deleted: true));
    await reload();
    unawaited(sync?.run());
    return removed;
  }

  Future<void> restore(Record original) async {
    final latest = await db!.find(original.kind, original.id);
    if (latest == null || latest.version != original.version + 1) {
      throw StateError(
        'После этой операции запись изменилась. Отмена не перезаписала новую правку.',
      );
    }
    await db!.save(original.copy(version: latest.version));
    await reload();
    unawaited(sync?.run());
  }

  Future<void> favorite(Record product) async {
    final existing = (await db!.records(
      kind: 'favorite',
      deleted: true,
    )).where((r) => r.data['product_id'] == product.id).firstOrNull;
    if (existing != null && !existing.deleted) {
      await remove(existing);
    } else {
      await save('favorite', {'product_id': product.id}, previous: existing);
    }
  }

  Record? lastPortion(String productId) =>
      of('portion').where((r) => r.data['product_id'] == productId).firstOrNull;
  String _newId(String kind, Json data) => switch (kind) {
    'favorite' || 'portion' => const Uuid().v5(
      Uuid.NAMESPACE_URL,
      '$userId/$kind/${data['product_id']}',
    ),
    'settings' => const Uuid().v5(Uuid.NAMESPACE_URL, '$userId/settings'),
    _ => const Uuid().v4(),
  };
  Future<void> addEntries(List<Json> values, Meal meal) async {
    final current = db!;
    await current.transaction(() async {
      for (final data in values) {
        final entry = {...data, 'day': dayKey(day), 'meal': meal.name};
        await current.save(
          Record(id: const Uuid().v4(), kind: 'entry', data: entry),
        );
        if (data['product_id'] != null) {
          final existing = (await current.records(kind: 'portion'))
              .where((r) => r.data['product_id'] == data['product_id'])
              .firstOrNull;
          await current.save(
            Record(
              id: existing?.id ?? _newId('portion', data),
              kind: 'portion',
              version: existing?.version ?? 0,
              data: {
                'product_id': data['product_id'],
                'amount': data['amount'],
                'portion_name': data['portion_name'],
                'portion_id': data['portion_id'],
                'unit': data['unit'],
              },
            ),
          );
        }
      }
    });
    await reload();
    unawaited(sync?.run());
  }

  Future<void> copyMeal(
    DateTime source,
    Meal sourceMeal,
    Meal targetMeal,
  ) async {
    final values = of('entry')
        .where(
          (r) =>
              r.data['day'] == dayKey(source) &&
              r.data['meal'] == sourceMeal.name,
        )
        .map((r) => r.data)
        .toList();
    if (values.isEmpty) throw StateError('В выбранном приеме пищи нет записей');
    await addEntries(values, targetMeal);
  }

  Future<void> signOut() async {
    await sync?.dispose();
    await client.auth.signOut(scope: SignOutScope.local);
    needsPassword = false;
    _switchQueue = _switchQueue.then((_) => _activate(null));
    await _switchQueue;
  }

  @override
  void dispose() {
    _disposed = true;
    _auth?.cancel();
    final engine = sync;
    final database = db;
    unawaited(() async {
      await engine?.dispose();
      await database?.close();
    }());
    super.dispose();
  }
}
