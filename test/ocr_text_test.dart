import 'dart:ui';
import 'package:ads_pocket/core/longevity.dart';
import 'package:ads_pocket/core/ocr_engine.dart';
import 'package:ads_pocket/core/text_extraction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final oct12 = CivilDate.of(2026, 10, 12)!;

  for (final text in [
    'Iniciado em 12 de outubro de 2026',
    'Começou a circular em 12 de outubro de 2026',
    'Veiculação iniciada em 12 de out de 2026',
    'Started running on October 12, 2026',
    'Started running on Oct 12, 2026',
    'Started running on 12 Oct 2026',
  ]) {
    test('start phrase recognized: $text', () {
      final s = DateSuggestion(findDateCandidates('Ativo\n$text\nID: 123'));
      expect(s.candidates.single.date, oct12);
      expect(s.candidates.single.evidence, DateEvidence.startPhrase);
      expect(s.preselected?.date, oct12);
      expect(s.multipleAds, isFalse);
    });
  }

  test('phrase split across OCR lines is still associated', () {
    final s = DateSuggestion(
      findDateCandidates('Started running on\nOctober 12, 2026'),
    );
    expect(s.preselected?.date, oct12);
  });

  test('numeric date is day/month and flagged when ambiguous', () {
    final c = findDateCandidates('Iniciado em 12/10/2026');
    expect(c.map((x) => x.date), [oct12, CivilDate.of(2026, 12, 10)]);
    expect(c.every((x) => x.ambiguousOrder), isTrue);
    // Ambiguity disables pre-selection: the user must choose.
    expect(DateSuggestion(c).preselected, isNull);
    final clear = findDateCandidates('Iniciado em 25/10/2026');
    expect(clear.single.date, CivilDate.of(2026, 10, 25));
    expect(clear.single.ambiguousOrder, isFalse);
  });

  test('a date without start phrase is never pre-selected', () {
    final s = DateSuggestion(
      findDateCandidates('Promoção válida até 30 de novembro de 2026'),
    );
    expect(s.candidates.single.evidence, DateEvidence.generic);
    expect(s.preselected, isNull);
  });

  test('several ads in one screenshot require explicit association', () {
    final s = DateSuggestion(
      findDateCandidates(
        'Iniciado em 12 de outubro de 2026\nPlanilha A\n'
        'Iniciado em 3 de setembro de 2026\nPlanilha B\n'
        'Oferta até 01/12/2026',
      ),
    );
    expect(s.startCandidates, hasLength(2));
    expect(s.multipleAds, isTrue);
    expect(s.preselected, isNull);
    expect(s.candidates.length, greaterThanOrEqualTo(3));
  });

  test('text without dates yields no candidates', () {
    expect(findDateCandidates('Compre agora por apenas R\$ 19,90'), isEmpty);
    expect(findDateCandidates(''), isEmpty);
    expect(findDateCandidates('31 de fevereiro de 2026'), isEmpty);
  });

  test('region selection limits the analysed text', () {
    const lines = [
      OcrLine(
        'Iniciado em 12 de outubro de 2026',
        Rect.fromLTWH(0, 0, 300, 20),
      ),
      OcrLine(
        'Iniciado em 3 de setembro de 2026',
        Rect.fromLTWH(0, 500, 300, 20),
      ),
    ];
    final top = DateSuggestion(
      findDateCandidates(linesText(lines, const Rect.fromLTWH(0, 0, 400, 100))),
    );
    expect(top.multipleAds, isFalse);
    expect(top.preselected?.date, oct12);
    expect(
      DateSuggestion(findDateCandidates(linesText(lines))).multipleAds,
      isTrue,
    );
  });

  test('money parsing and formatting', () {
    expect(parseMoneyToCents('9,90'), 990);
    expect(parseMoneyToCents('9.90'), 990);
    expect(parseMoneyToCents('97'), 9700);
    expect(parseMoneyToCents('1.234,56'), 123456);
    expect(parseMoneyToCents('1,234.56'), 123456);
    expect(parseMoneyToCents('R\$ 47,00'), 4700);
    expect(parseMoneyToCents('abc'), isNull);
    expect(formatMoney(990, 'BRL'), 'R\$ 9,90');
    expect(formatMoney(123456, 'USD'), 'US\$ 1.234,56');
  });

  test('OCR price suggestions keep currency and do not invent values', () {
    final p = findPriceCandidates('De R\$ 97,00 por R\$ 19,90 · US\$ 7');
    expect(p.map((x) => (x.cents, x.currency)), [
      (9700, 'BRL'),
      (1990, 'BRL'),
      (700, 'USD'),
    ]);
    expect(findPriceCandidates('Sem preço visível'), isEmpty);
  });
}
