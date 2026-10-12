import 'dart:isolate';
import '../domain/food_search.dart';
import 'database.dart';

class FoodSearchRepository {
  FoodSearchRepository(this.db);
  final DiaryDatabase db;
  int _revision = -1;
  String _date = '';
  Map<String, FoodPreference> _preferences = {};

  Future<List<SearchHit>> search(
    String raw, {
    String? meal,
    String filter = 'all',
    bool hidden = false,
    DateTime? date,
  }) async {
    final now = date ?? DateTime.now();
    final key = now.toIso8601String().substring(0, 10);
    if (_revision != db.searchRevision || _date != key) {
      final revision = db.searchRevision;
      final records = [
        ...await db.records(kind: 'entry'),
        ...await db.records(kind: 'favorite'),
      ];
      _preferences = await Isolate.run(() => foodPreferences(records, now));
      _revision = revision;
      _date = key;
    }
    final query = SearchQuery(raw);
    final candidates = await db.searchCandidates(query, hidden: hidden);
    if (query.tokens.isEmpty && _preferences.isNotEmpty) {
      final present = candidates.map((p) => p.id).toSet();
      final ids = _preferences.keys
          .where((id) => !present.contains(id))
          .toList();
      // Personal products must remain discoverable beyond the alphabetic starter page.
      candidates.addAll(await db.searchProductsByIds(ids, hidden: hidden));
    }
    final preferences = _preferences;
    return Isolate.run(
      () => rankFoodCandidates(
        candidates,
        query,
        preferences,
        meal,
        now,
        filter: filter,
      ),
    );
  }
}
