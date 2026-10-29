import 'dart:convert';
import 'package:ads_pocket/core/longevity.dart';
import 'package:ads_pocket/data/offer.dart';
import 'package:ads_pocket/features/browser/library_assistant.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> card({
  String id = '1175443257960186',
  String start = 'Started running on Jul 8, 2025',
  bool? active = true,
  String text = 'Diga adeus à bagunça!\nNossa planilha gratuita vai te ajudar',
  Object? cta = 'https://solides.com.br/planilha',
}) => {
  'id': id,
  'start': start,
  'active': active,
  'advertiser': 'Sólides Educação',
  'text': text,
  'variations': 3,
  'multiple': true,
  'video': true,
  'profile': 'https://web.facebook.com/solides.rhportal/',
  'cta': cta,
};

void main() {
  test('card text becomes a complete saved ad without typing', () {
    final c = LibraryCard.fromJson(card())!;
    expect(c.start, CivilDate.of(2025, 7, 8));
    final o = c.toOffer(pageId: '123', now: DateTime.utc(2026, 10, 28, 12));
    o.validate();
    expect(o.adId, '1175443257960186');
    expect(o.url, 'https://www.facebook.com/ads/library/?id=1175443257960186');
    expect(o.identity, 'ad:1175443257960186');
    expect(o.name, 'Diga adeus à bagunça!');
    expect(o.hook, 'Diga adeus à bagunça!');
    expect(o.advertiser, 'Sólides Educação');
    expect(o.pageId, '123');
    expect(o.startDate, CivilDate.of(2025, 7, 8));
    expect(o.dateSource, DateSource.library);
    expect(o.status, AdStatus.active);
    expect(o.lastCheckedAt, DateTime.utc(2026, 10, 28, 12));
    expect(o.mediaType, MediaType.video);
    expect(o.variations, 3);
    expect(o.salesUrl, 'https://solides.com.br/planilha');
    expect(o.priceCents, isNull, reason: 'preço não aparece no card');
  });

  test('Portuguese labels and inactive date ranges', () {
    final pt = LibraryCard.fromJson(
      card(start: 'Veiculação iniciada em 12 de out de 2025', active: null),
    )!;
    expect(pt.start, CivilDate.of(2025, 10, 12));
    expect(pt.toOffer().status, AdStatus.unknown);
    final range = LibraryCard.fromJson(
      card(start: 'Jul 8, 2025 - Oct 1, 2025', active: false),
    )!;
    expect(range.start, CivilDate.of(2025, 7, 8));
    expect(range.toOffer().status, AdStatus.inactive);
    final none = LibraryCard.fromJson(card(start: ''))!;
    expect(none.start, isNull);
    final o = none.toOffer();
    expect(o.startDate, isNull);
    expect(o.dateSource, isNull);
    o.validate();
  });

  test('page data is untrusted: invalid or unsafe values are dropped', () {
    expect(LibraryCard.fromJson(card(id: '12')), isNull);
    expect(LibraryCard.fromJson(card(id: '1 OR 1=1')), isNull);
    expect(LibraryCard.fromJson('x'), isNull);
    final c = LibraryCard.fromJson(
      card(cta: 'http://insecure.example.com', text: 'a' * 5000),
    )!;
    expect(c.cta, isNull);
    expect(c.text.length, 2000);
    expect(LibraryCard.fromJson(card(cta: 'javascript:alert(1)'))!.cta, isNull);
    final long = LibraryCard.fromJson(card(text: 'x' * 300))!.toOffer();
    expect(long.name.length, lessThanOrEqualTo(120));
    long.validate();
  });

  test('messages are parsed defensively', () {
    expect(parseAssistantMessage(null), isNull);
    expect(parseAssistantMessage('not json'), isNull);
    expect(parseAssistantMessage('[1,2]'), isNull);
    expect(parseAssistantMessage('{"type":"save","id":"x"}')!.id, isNull);
    final m = parseAssistantMessage(
      jsonEncode({
        'type': 'cards',
        'cards': [card(), card(id: 'bad'), 'junk'],
        'stats': {
          'loaded': 30,
          'visible': 12,
          'active': 28,
          'results': '~18,000 results',
          'scrolling': true,
        },
      }),
    )!;
    expect(m.type, 'cards');
    expect(m.cards, hasLength(1));
    expect(m.stats!.results, '~18,000');
    expect(m.stats!.visible, 12);
    expect(m.stats!.scrolling, isTrue);
    expect(AssistantStats.fromJson({'loaded': -4, 'results': 42}).loaded, 0);
  });

  test('apply command carries ages computed in Dart', () {
    final js = assistantApply(
      ages: {'111111': 30, '222222': null},
      saved: ['111111'],
      minDays: 14,
      includeUndated: false,
      minAds: 5,
    );
    expect(
      js,
      startsWith('window.AdsPocketAssist && window.AdsPocketAssist.apply('),
    );
    final payload =
        jsonDecode(js.substring(js.indexOf('(') + 1, js.lastIndexOf(')')))
            as Map;
    expect(payload['ages'], {'111111': 30, '222222': null});
    expect(payload['minDays'], 14);
    expect(payload['includeUndated'], isFalse);
    expect(payload['minAds'], 5);
    expect(payload['pages'], isEmpty);
    final known = assistantApply(
      ages: const {},
      saved: const [],
      minDays: null,
      includeUndated: true,
      minAds: null,
      pages: {'111111': '106480812544708'},
    );
    expect(known, contains('"pages":{"111111":"106480812544708"}'));
  });

  test('Page ID read from the ad details is validated', () {
    final m = parseAssistantMessage(
      jsonEncode({
        'type': 'page',
        'id': '2915138038839875',
        'page': '106480812544708',
        'name': ' Sublime Concursos ',
      }),
    )!;
    expect(m.type, 'page');
    expect(m.id, '2915138038839875');
    expect(m.page, '106480812544708');
    expect(m.name, 'Sublime Concursos');
    final bad = parseAssistantMessage(
      jsonEncode({
        'type': 'page',
        'id': '2915138038839875',
        'page': '1064; DROP',
        'name': '',
      }),
    )!;
    expect(bad.page, isNull, reason: 'só dígitos viram Page ID');
    expect(bad.name, isNull);
    expect(bad.pick, isFalse);
    final pick = parseAssistantMessage(
      jsonEncode({
        'type': 'page',
        'id': '1175443257960186',
        'page': null,
        'name': 'Sólides Educação',
        'pick': true,
      }),
    )!;
    expect(pick.page, isNull, reason: 'o usuário escolhe na lista da Meta');
    expect(pick.pick, isTrue);
    expect(pick.name, 'Sólides Educação');
    expect(
      parseAssistantMessage('{"type":"page","id":"2915138038839875"}')!.page,
      isNull,
      reason: 'falha ao ler os detalhes: nenhum ID é inventado',
    );
  });

  test('page script reads the Page ID from visible text, never from links', () {
    // "Sobre o anunciante" / "About the advertiser" in the ad details.
    expect(
      assistantScript,
      contains('Sobre o anunciante|About the advertiser'),
    );
    expect(assistantScript, contains('Ver detalhes do anúncio|See ad details'));
    // Fallback types the name in Meta's search and only highlights the entry;
    // the user's own tap selects it.
    expect(assistantScript, contains("target.style.outline"));
    expect(assistantScript.contains('target.click()'), isFalse);
    // The action row is built without innerHTML (Trusted Types pages).
    expect(assistantScript.contains('innerHTML'), isFalse);
    // Feed mode unpins bars (reversible) instead of hiding them.
    expect(assistantScript, contains("el.style.position = 'static'"));
    // Mutations are throttled so videos cannot postpone the scan forever.
    expect(assistantScript.contains('clearTimeout(pending)'), isFalse);
  });

  test('page script never touches credentials or storage', () {
    for (final forbidden in [
      'document.cookie',
      'localStorage',
      'sessionStorage',
      'XMLHttpRequest',
      'fetch(',
      'input[type=password]',
    ]) {
      expect(assistantScript.contains(forbidden), isFalse, reason: forbidden);
    }
  });
}
