import 'dart:math' as math;
import 'records.dart';
import 'search_lexicon.dart';

class SearchNormalizer {
  static String normalize(String text) {
    var s = text
        .toLowerCase()
        .replaceAll('ё', 'е')
        .replaceAll(RegExp(r'[\u0300-\u036f]'), '');
    const accents = {
      'a': 'àáâãäåāăą',
      'c': 'çćč',
      'e': 'èéêëēėęě',
      'i': 'ìíîïīį',
      'n': 'ñńň',
      'o': 'òóôõöøō',
      's': 'śšş',
      'u': 'ùúûüūů',
      'y': 'ýÿ',
      'z': 'źżž',
    };
    accents.forEach((base, letters) {
      s = s.replaceAll(RegExp('[$letters]'), base);
    });
    s = s.replaceAllMapped(
      RegExp(r'\d+[.,]\d+'),
      (m) => double.parse(
        m[0]!.replaceAll(',', '.'),
      ).toString().replaceFirst(RegExp(r'\.0$'), ''),
    );
    return RegExp(
      r'[a-zа-я0-9]+(?:\.[0-9]+)?',
    ).allMatches(s).map((m) => m[0]!).join(' ');
  }

  static List<String> tokens(String text) =>
      normalize(text).split(' ').where((s) => s.isNotEmpty).toList();
  static String layout(String text) {
    const latin = "qwertyuiop[]asdfghjkl;'zxcvbnm,.";
    const russian = 'йцукенгшщзхъфывапролджэячсмитьбю';
    final s = text.toLowerCase();
    final toRussian = RegExp('[a-z]').hasMatch(s);
    final from = toRussian ? latin : russian, to = toRussian ? russian : latin;
    return List.generate(s.length, (index) {
      final c = s[index];
      if ((c == ',' || c == '.') &&
          index > 0 &&
          index + 1 < s.length &&
          RegExp(r'\d').hasMatch(s[index - 1]) &&
          RegExp(r'\d').hasMatch(s[index + 1])) {
        return c;
      }
      final i = from.indexOf(c);
      return i < 0 ? c : to[i];
    }).join();
  }

  static String phonetic(String token) => token
      .replaceAll(RegExp('[aeiouаеиоуыэюяьъ]'), '')
      .replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
  static Set<String> grams(String token) => {
    for (var i = 0; i + 1 < token.length; i++) token.substring(i, i + 2),
  };
  static String aliases(Record p) {
    final name = normalize(p.data['name'] as String? ?? '');
    final own = (p.data['aliases'] as List? ?? [])
        .whereType<String>()
        .map(normalize)
        .toList();
    for (final rule in foodSynonyms) {
      if (rule.excluded.any((word) => name.split(' ').contains(word))) {
        continue;
      }
      for (final term in rule.terms) {
        if (RegExp('(^| )${RegExp.escape(term)}( |\$)').hasMatch(name)) {
          own.addAll(
            rule.terms
                .where((t) => t != term)
                .map((t) => name.replaceFirst(term, t)),
          );
        }
      }
    }
    return own.join(' ');
  }
}

class SearchQuery {
  SearchQuery(this.raw) {
    final match = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(грамм(?:а|ов)?|гр|г|мл)(?=\s|[.,;!?)]|$)',
      caseSensitive: false,
    ).firstMatch(raw);
    var text = raw;
    if (match != null) {
      final quantity = double.tryParse(match[1]!.replaceAll(',', '.'));
      if (quantity != null && quantity > 0 && quantity <= 100000) {
        amount = quantity;
        unit = match[2]!.toLowerCase() == 'мл' ? 'milliliter' : 'gram';
        text = raw.replaceRange(match.start, match.end, ' ');
      }
    }
    if (text.length > 512) {
      text = text.substring(0, 512);
    }
    tokens = SearchNormalizer.tokens(text).take(16).toList();
    normalized = tokens.join(' ');
  }
  final String raw;
  late final String normalized;
  late final List<String> tokens;
  double? amount;
  String? unit;
}

class FoodPreference {
  int count = 0, week = 0, month = 0;
  bool favorite = false;
  DateTime? last;
  Json? lastPortion;
  final meals = <String, int>{};
  final portions = <String, int>{};
  double typicalAmount(String unit) {
    final ordered =
        portions.entries.where((e) => e.key.startsWith('$unit/')).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return ordered.isEmpty
        ? 100
        : double.parse(ordered.first.key.split('/').last);
  }

  double score(String? meal, DateTime now) {
    final recency = last == null
        ? 0.0
        : 15 / (1 + math.max(0, now.difference(last!).inDays) / 3);
    return math.min(
      90,
      math.log(1 + count) * 6 +
          week * 2 +
          month * 0.5 +
          recency +
          (favorite ? 12 : 0) +
          (meal == null ? 0 : (meals[meal] ?? 0) * 5),
    );
  }
}

Map<String, FoodPreference> foodPreferences(
  Iterable<Record> records,
  DateTime now,
) {
  final result = <String, FoodPreference>{};
  for (final r in records) {
    if (r.deleted) {
      continue;
    }
    final id = r.data['product_id'];
    if (id is! String) {
      continue;
    }
    final p = result.putIfAbsent(id, FoodPreference.new);
    if (r.kind == 'favorite') {
      p.favorite = true;
      continue;
    }
    if (r.kind != 'entry') {
      continue;
    }
    final date = DateTime.tryParse(
      r.data['day'] as String? ?? r.data['recorded_at'] as String? ?? '',
    );
    p.count++;
    final meal = r.data['meal'] as String?;
    if (meal != null) p.meals[meal] = (p.meals[meal] ?? 0) + 1;
    if (date != null) {
      final age = now.difference(date).inDays;
      if (age >= 0 && age < 7) p.week++;
      if (age >= 0 && age < 30) p.month++;
      if (p.last == null || date.isAfter(p.last!)) {
        p.last = date;
        p.lastPortion = r.data;
      }
    }
    final amount = r.data['amount'];
    if (amount is num) {
      final key = '${r.data['unit']}/$amount';
      p.portions[key] = (p.portions[key] ?? 0) + 1;
    }
  }
  return result;
}

class SearchHit {
  const SearchHit(
    this.product,
    this.textTier,
    this.personal,
    this.preference, {
    this.correction,
  });
  final Record product;
  final int textTier;
  final double personal;
  final FoodPreference? preference;
  final String? correction;
}

int editDistance(String a, String b, int maximum) {
  if ((a.length - b.length).abs() > maximum) {
    return maximum + 1;
  }
  var previous = List.generate(b.length + 1, (i) => i), before = previous;
  for (var i = 1; i <= a.length; i++) {
    final row = List<int>.filled(b.length + 1, 0);
    row[0] = i;
    for (var j = 1; j <= b.length; j++) {
      row[j] = math.min(
        math.min(row[j - 1] + 1, previous[j] + 1),
        previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1),
      );
      if (i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1]) {
        row[j] = math.min(row[j], before[j - 2] + 1);
      }
    }
    before = previous;
    previous = row;
  }
  return previous.last;
}

int textTier(Record p, SearchQuery q, {bool fuzzy = false}) {
  if (q.tokens.isEmpty) {
    return 0;
  }
  final name = SearchNormalizer.normalize(p.data['name'] as String? ?? '');
  final words = SearchNormalizer.tokens('$name ${p.data['brand'] ?? ''}');
  final aliases = SearchNormalizer.tokens(SearchNormalizer.aliases(p));
  if (name == q.normalized) {
    return 0;
  }
  if (q.tokens.every(words.contains)) {
    return 1;
  }
  bool exactNumber(String token) => double.tryParse(token) != null;
  if (q.tokens.every(
    (t) => words.any((w) => exactNumber(t) ? w == t : w.startsWith(t)),
  )) {
    return 2;
  }
  if (q.tokens.every(
    (t) => [
      ...words,
      ...aliases,
    ].any((w) => exactNumber(t) ? w == t : w.startsWith(t)),
  )) {
    return 3;
  }
  if (q.tokens.every(
    (t) => words.any((w) => exactNumber(t) ? w == t : w.contains(t)),
  )) {
    return 4;
  }
  if (!fuzzy) {
    return 99;
  }
  final ok = q.tokens.every(
    (t) => words.any(
      (w) => exactNumber(t)
          ? w == t
          : w.startsWith(t) ||
                (t.length >= 4 &&
                    editDistance(t, w, t.length >= 6 ? 2 : 1) <=
                        (t.length >= 6 ? 2 : 1)),
    ),
  );
  return ok ? 6 : 99;
}

List<SearchHit> rankFoodCandidates(
  List<Record> products,
  SearchQuery query,
  Map<String, FoodPreference> preferences,
  String? meal,
  DateTime now, {
  String filter = 'all',
  bool fallback = true,
}) {
  List<SearchHit> collect(
    SearchQuery q,
    bool fuzzy,
    int extra,
    String? correction,
  ) => products
      .where((p) {
        final pref = preferences[p.id];
        return filter == 'favorite'
            ? pref?.favorite == true
            : filter == 'recent' || filter == 'frequent'
            ? (pref?.count ?? 0) > 0
            : filter == 'meal'
            ? (pref?.meals[meal] ?? 0) > 0
            : true;
      })
      .map((p) {
        final tier = textTier(p, q, fuzzy: fuzzy);
        final pref = preferences[p.id];
        return SearchHit(
          p,
          tier == 99 ? 99 : math.max(tier, extra),
          pref?.score(meal, now) ?? 0,
          pref,
          correction: correction,
        );
      })
      .where((h) => h.textTier < 99)
      .toList();
  var result = collect(query, false, 0, null);
  if (result.isEmpty && query.tokens.isNotEmpty && fallback) {
    final layout = SearchQuery(SearchNormalizer.layout(query.raw));
    if (layout.normalized != query.normalized) {
      result = collect(layout, false, 5, layout.normalized);
    }
    if (result.isEmpty) result = collect(query, true, 6, null);
  }
  result.sort((a, b) {
    final tier = a.textTier.compareTo(b.textTier);
    if (tier != 0) {
      return tier;
    }
    if (filter == 'recent') {
      final recent = (b.preference?.last ?? DateTime(2000)).compareTo(
        a.preference?.last ?? DateTime(2000),
      );
      if (recent != 0) {
        return recent;
      }
    }
    final score = filter == 'frequent'
        ? (b.preference?.count ?? 0).compareTo(a.preference?.count ?? 0)
        : b.personal.compareTo(a.personal);
    if (score != 0) {
      return score;
    }
    final name = (a.product.data['name'] as String).compareTo(
      b.product.data['name'] as String,
    );
    return name != 0 ? name : a.product.id.compareTo(b.product.id);
  });
  return result;
}
