// Search equivalents only: never merge cards or alter nutritional values.
const foodSynonyms = <({String kind, List<String> terms, List<String> excluded})>[
  (kind: 'equivalent', terms: ['макароны', 'паста'], excluded: ['томатная', 'зубная', 'арахисовая', 'шоколадная', 'ореховая']),
  (kind: 'colloquial', terms: ['овсянка', 'овсяные хлопья'], excluded: []),
  (kind: 'colloquial', terms: ['греча', 'гречка'], excluded: []),
  (kind: 'colloquial', terms: ['пюрешка', 'картофельное пюре'], excluded: []),
];
