import 'package:flutter_test/flutter_test.dart';
import 'package:calorie_diary/domain/records.dart';
import 'package:calorie_diary/domain/food_search.dart';

Record food(
  int id,
  String name, {
  String brand = '',
  List<String> aliases = const [],
}) => Record(
  id: '00000000-0000-4000-8000-${id.toString().padLeft(12, '0')}',
  kind: 'product',
  data: {
    'name': name,
    'brand': brand,
    'aliases': aliases,
    'unit': 'gram',
    'nutrition': {'kcal': 100, 'protein': 5, 'fat': 5, 'carbs': 10},
    'portions': [],
    'active': true,
  },
);
Record use(
  int id,
  Record p, {
  String meal = 'breakfast',
  String day = '2026-10-12',
  double amount = 180,
  bool deleted = false,
  String unit = 'gram',
}) => Record(
  id: '00000000-0000-4000-8001-${id.toString().padLeft(12, '0')}',
  kind: 'entry',
  deleted: deleted,
  data: {
    'product_id': p.id,
    'meal': meal,
    'day': day,
    'amount': amount,
    'unit': unit,
  },
);
final now = DateTime(2026, 10, 12);
List<SearchHit> search(
  List<Record> products,
  String query, {
  List<Record> history = const [],
  String meal = 'breakfast',
}) => rankFoodCandidates(
  products,
  SearchQuery(query),
  foodPreferences(history, now),
  meal,
  now,
);

void main() {
  final catalog = [
    food(1, 'Молоко 2,5%'),
    food(2, 'Молоко 3.2%'),
    food(3, 'Творог 5%'),
    food(4, 'Куриная грудка'),
    food(5, 'Гречка'),
    food(6, 'Рис варёный'),
    food(7, 'Рис сухой'),
    food(8, 'Паста'),
    food(9, 'Томатная паста'),
    food(10, 'Овсяные хлопья'),
    food(11, 'Картофельное пюре'),
  ];
  final cases = {
    'молоко': [1, 2],
    'мол': [1, 2],
    'малако': [1, 2],
    'vjkjrj': [1, 2],
    'творог': [3],
    'тварог': [3],
    'творог 5%': [3],
    'молоко 2.5': [1],
    'кур груд': [4],
    'греча': [5],
    'рис вареный': [6],
    'макароны': [8],
    'овсянка': [10],
    'пюрешка': [11],
    'гречкаа': [5],
    'куринная грудка': [4],
  };
  for (final pair in cases.entries) {
    test('local relevance: ${pair.key}', () {
      expect(
        search(
          catalog,
          pair.key,
        ).map((h) => int.parse(h.product.id.split('-').last)).toSet(),
        pair.value.toSet(),
      );
    });
  }
  test(
    'normalization leaves original intact and handles accents, punctuation, decimals',
    () {
      expect(
        SearchNormalizer.normalize('  Ёж, Café; МОЛОКО 2,50%  '),
        'еж cafe молоко 2.5',
      );
      expect(catalog.first.data['name'], 'Молоко 2,5%');
    },
  );
  test(
    'numbers are not guessed as portions or fat; explicit unit is required',
    () {
      expect(SearchQuery('молоко 2.5').amount, isNull);
      expect(SearchQuery('творог 180').amount, isNull);
      final q = SearchQuery('творог 5% 180 г');
      expect(q.normalized, 'творог 5');
      expect(q.amount, 180);
      expect(q.unit, 'gram');
      expect(SearchQuery('молоко 200 мл').unit, 'milliliter');
      expect(
        search(
          catalog,
          'рис вареный',
        ).any((h) => h.product.id == catalog[6].id),
        isFalse,
      );
    },
  );
  test(
    'personal histories and meal context stay independent; delete changes scores',
    () {
      final a = catalog[0], b = catalog[1];
      final history = [
        for (var i = 0; i < 4; i++) use(i, a),
        for (var i = 4; i < 8; i++) use(i, b, meal: 'dinner'),
      ];
      expect(search([a, b], 'молоко', history: history).first.product.id, a.id);
      expect(
        search(
          [a, b],
          'молоко',
          history: history,
          meal: 'dinner',
        ).first.product.id,
        b.id,
      );
      expect(
        search([a, b], 'молоко', history: [use(1, b)]).first.product.id,
        b.id,
      );
      expect(foodPreferences([use(1, a, deleted: true)], now), isEmpty);
    },
  );
  test(
    'exact names always beat personal preference and layout does not override direct text',
    () {
      final exact = food(20, 'Молоко'), latin = food(21, 'vjkjrj');
      expect(
        search(
          [...catalog, exact],
          'молоко',
          history: [for (var i = 0; i < 100; i++) use(i, catalog[0])],
        ).first.product.id,
        exact.id,
      );
      expect(search([catalog[0], latin], 'vjkjrj').single.product.id, latin.id);
    },
  );
  test(
    'alias, brand, deterministic ties and unit-specific typical portions',
    () {
      final p = food(
        30,
        'Напиток',
        brand: 'Коровка',
        aliases: ['Молочный коктейль'],
      );
      expect(search([p], 'молочный кок').single.textTier, 3);
      expect(search([p], 'коровка').single.product.id, p.id);
      final pref = foodPreferences([
        use(1, p),
        use(2, p),
        use(3, p, amount: 300, unit: 'milliliter'),
      ], now)[p.id]!;
      expect(pref.typicalAmount('gram'), 180);
      expect(pref.typicalAmount('milliliter'), 300);
    },
  );
  test(
    'decimal comma survives wrong layout and explicit units allow punctuation',
    () {
      expect(SearchNormalizer.layout('vjkjrj 2,5'), 'молоко 2,5');
      expect(SearchQuery('творог 180 г,').amount, 180);
    },
  );
  test(
    'frequent suggestions emphasize recent weeks before distant lifetime counts',
    () {
      final a = FoodPreference()..count = 100;
      final b = FoodPreference()
        ..count = 1
        ..week = 1
        ..month = 1;
      expect(compareFoodFrequency(a, b), greaterThan(0));
    },
  );
  test(
    'invalid negative or embedded quantities are never proposed as positive portions',
    () {
      expect(SearchQuery('творог -180 г').amount, isNull);
      expect(SearchQuery('творог A180г').amount, isNull);
      expect(SearchQuery('творог 180 г').amount, 180);
    },
  );
}
