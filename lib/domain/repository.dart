import 'records.dart';

/// Domain boundary; neither Flutter nor SQL is needed by business consumers.
abstract interface class DiaryRepository {
  Future<List<Record>> records({String? kind, bool deleted = false});
  Future<Record?> find(String kind, String id);
  Future<Record> save(Record value);
}
