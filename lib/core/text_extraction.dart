import 'longevity.dart';

/// How a date found in recognized text relates to an ad start date.
enum DateEvidence {
  startPhrase('Junto a uma frase de início'),
  generic('Data sem contexto de início');

  const DateEvidence(this.label);
  final String label;
}

class DateCandidate {
  const DateCandidate({
    required this.date,
    required this.excerpt,
    required this.evidence,
    required this.offset,
    this.ambiguousOrder = false,
  });
  final CivilDate date;
  final String excerpt;
  final DateEvidence evidence;
  final int offset;

  /// Numeric dates such as 05/10/2026 can be read as day/month or month/day.
  final bool ambiguousOrder;
}

/// Outcome the UI must respect: nothing is applied without user confirmation.
class DateSuggestion {
  const DateSuggestion(this.candidates);
  final List<DateCandidate> candidates;
  List<DateCandidate> get startCandidates =>
      candidates.where((c) => c.evidence == DateEvidence.startPhrase).toList();

  /// Several start phrases usually mean several ads in one screenshot.
  bool get multipleAds =>
      startCandidates.map((c) => c.offset).toSet().length > 1;
  bool get hasAmbiguity => candidates.any((c) => c.ambiguousOrder);

  /// Pre-selection only for a single, unambiguous start phrase.
  DateCandidate? get preselected {
    final starts = startCandidates;
    return starts.length == 1 && !starts.single.ambiguousOrder
        ? starts.single
        : null;
  }
}

const _months = <String, int>{
  'jan': 1, 'janeiro': 1, 'january': 1, //
  'fev': 2, 'fevereiro': 2, 'feb': 2, 'february': 2,
  'mar': 3, 'marco': 3, 'march': 3,
  'abr': 4, 'abril': 4, 'apr': 4, 'april': 4,
  'mai': 5, 'maio': 5, 'may': 5,
  'jun': 6, 'junho': 6, 'june': 6,
  'jul': 7, 'julho': 7, 'july': 7,
  'ago': 8, 'agosto': 8, 'aug': 8, 'august': 8,
  'set': 9, 'setembro': 9, 'sep': 9, 'sept': 9, 'september': 9,
  'out': 10, 'outubro': 10, 'oct': 10, 'october': 10,
  'nov': 11, 'novembro': 11, 'november': 11,
  'dez': 12, 'dezembro': 12, 'dec': 12, 'december': 12,
};

// Phrases Meta uses next to an ad start date (accents already removed).
const _startPhrases = [
  'iniciado em',
  'iniciada em',
  'iniciou em',
  'comecou a circular em',
  'comecou a ser veiculado em',
  'comecou a ser veiculada em',
  'veiculacao iniciada em',
  'em veiculacao desde',
  'data de inicio',
  'started running on',
  'began running on',
  'started running',
  'start date',
];

String _fold(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const to = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().toLowerCase();
}

/// Finds dates in Portuguese and English. Folding keeps string offsets stable
/// because every replacement is a single character.
List<DateCandidate> findDateCandidates(String raw) {
  if (raw.length > 200000) raw = raw.substring(0, 200000);
  final text = _fold(raw.replaceAll(RegExp(r'\s'), ' '));
  final monthNames =
      (_months.keys.toList()..sort((a, b) => b.length.compareTo(a.length)))
          .join('|');
  // Matches first, evidence later: the start phrase is searched only between
  // the previous date and this one, so it never leaks to the next ad.
  final matches = <(int, int, List<CivilDate>)>[];
  void add(int start, int end, List<CivilDate?> dates) {
    final valid = dates.whereType<CivilDate>().toList();
    if (valid.isEmpty || matches.any((t) => start < t.$2 && end > t.$1)) {
      return;
    }
    matches.add((start, end, valid));
  }

  // 12 de outubro de 2026 · 12 out. 2026 · 12 October 2026
  for (final m in RegExp(
    '\\b(\\d{1,2})(?:º)?\\s*(?:de\\s+)?($monthNames)\\.?,?\\s*(?:de\\s+)?(\\d{4})\\b',
  ).allMatches(text)) {
    add(m.start, m.end, [
      CivilDate.of(int.parse(m[3]!), _months[m[2]]!, int.parse(m[1]!)),
    ]);
  }
  // October 12, 2026 · Oct 12 2026
  for (final m in RegExp(
    '\\b($monthNames)\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})\\b',
  ).allMatches(text)) {
    add(m.start, m.end, [
      CivilDate.of(int.parse(m[3]!), _months[m[1]]!, int.parse(m[2]!)),
    ]);
  }
  // 2026-10-12
  for (final m in RegExp(r'\b(\d{4})-(\d{2})-(\d{2})\b').allMatches(text)) {
    add(m.start, m.end, [
      CivilDate.of(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!)),
    ]);
  }
  // 12/10/2026 is read as day/month (pt-BR). When both parts are <= 12 the
  // month/day reading is offered too and the user must choose.
  for (final m in RegExp(
    r'\b(\d{1,2})[/.](\d{1,2})[/.](\d{4})\b',
  ).allMatches(text)) {
    final a = int.parse(m[1]!), b = int.parse(m[2]!), y = int.parse(m[3]!);
    add(m.start, m.end, [
      CivilDate.of(y, b, a),
      if (a <= 12 && b <= 12 && a != b) CivilDate.of(y, a, b),
    ]);
  }
  matches.sort((a, b) => a.$1.compareTo(b.$1));

  final found = <DateCandidate>[];
  var previousEnd = 0;
  for (final (start, end, dates) in matches) {
    final from = start - 60 < previousEnd ? previousEnd : start - 60;
    final before = text.substring(from, start);
    previousEnd = end;
    final evidence = _startPhrases.any(before.contains)
        ? DateEvidence.startPhrase
        : DateEvidence.generic;
    final excerptFrom = start - 40 < 0 ? 0 : start - 40;
    final excerpt = raw
        .substring(excerptFrom, end)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    for (final date in dates) {
      found.add(
        DateCandidate(
          date: date,
          excerpt: excerpt,
          evidence: evidence,
          offset: start,
          ambiguousOrder: dates.length > 1,
        ),
      );
    }
  }
  return found;
}

class PriceCandidate {
  const PriceCandidate(this.cents, this.currency, this.excerpt);
  final int cents;
  final String currency;
  final String excerpt;
}

const currencies = <String, String>{
  'BRL': 'R\$',
  'USD': 'US\$',
  'EUR': '€',
  'GBP': '£',
};

/// Parses a typed amount: 9,90 · 9.90 · 1.234,56 · 1,234.56 · 97.
int? parseMoneyToCents(String input) {
  var s = input.trim().replaceAll(RegExp(r'[^\d.,]'), '');
  if (s.isEmpty || s.length > 15) return null;
  final lastComma = s.lastIndexOf(','), lastDot = s.lastIndexOf('.');
  final decimalAt = lastComma > lastDot ? lastComma : lastDot;
  String whole = s, fraction = '';
  if (decimalAt >= 0 && s.length - decimalAt - 1 <= 2) {
    whole = s.substring(0, decimalAt);
    fraction = s.substring(decimalAt + 1);
  }
  whole = whole.replaceAll(RegExp(r'[.,]'), '');
  if (whole.isEmpty) whole = '0';
  final cents = int.tryParse(whole);
  if (cents == null) return null;
  final value = cents * 100 + int.parse(fraction.padRight(2, '0'));
  return value > 100000000 ? null : value;
}

String formatMoney(int cents, String currency) {
  final whole = (cents ~/ 100).toString();
  final grouped = whole.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  return '${currencies[currency] ?? currency} $grouped,${(cents % 100).toString().padLeft(2, '0')}';
}

/// Price suggestions from recognized text. Always shown as "sugerido por OCR".
List<PriceCandidate> findPriceCandidates(String raw) {
  final text = raw.replaceAll(RegExp(r'\s+'), ' ');
  final result = <PriceCandidate>[];
  for (final m in RegExp(
    r'(R\$|US\$|€|£)\s?(\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{2})?)',
  ).allMatches(text)) {
    final cents = parseMoneyToCents(m[2]!);
    if (cents == null || cents == 0) continue;
    final currency = switch (m[1]) {
      'R\$' => 'BRL',
      'US\$' => 'USD',
      '€' => 'EUR',
      _ => 'GBP',
    };
    if (!result.any((p) => p.cents == cents && p.currency == currency)) {
      result.add(PriceCandidate(cents, currency, m[0]!));
    }
    if (result.length == 10) break;
  }
  return result;
}
