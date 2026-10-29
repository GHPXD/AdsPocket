import 'package:flutter_test/flutter_test.dart';
import 'package:ads_pocket/core/meta_ads_library_url_builder.dart';

void main() {
  final builder = MetaAdsLibraryUrlBuilder();
  test(
    'normalizes whitespace and preserves accents and reserved characters',
    () {
      final uri = builder.build(
        text: '  planilha   financeira & ação + 50% #1?  ',
      );
      expect(uri.scheme, 'https');
      expect(uri.host, 'www.facebook.com');
      expect(uri.queryParameters['q'], 'planilha financeira & ação + 50% #1?');
      expect(uri.queryParameters['country'], 'BR');
      expect(uri.queryParameters['active_status'], 'active');
      expect(uri.fragment, isEmpty);
    },
  );
  test(
    'public page identity is preserved without a fabricated name lookup',
    () {
      final uri = builder.build(
        text: '123456789',
        type: SearchType.pageId,
        country: 'PT',
        status: 'all',
      );
      expect(MetaAdsLibraryUrlBuilder.pageId(uri), '123456789');
      expect(MetaAdsLibraryUrlBuilder.identify(uri), SearchType.pageId);
      final advertiser = builder.build(
        text: 'Uma Página',
        type: SearchType.advertiser,
      );
      expect(advertiser.queryParameters['q'], 'Uma Página');
      expect(MetaAdsLibraryUrlBuilder.pageId(advertiser), isNull);
    },
  );
  test('direct link preserves all original parameters and fragment', () {
    const original =
        'https://www.facebook.com/ads/library/?id=12345&country=US&extra=ok#details';
    expect(
      builder.build(text: original, type: SearchType.directLink).toString(),
      original,
    );
  });
  for (final bad in [
    'http://www.facebook.com/ads/library/',
    'javascript:alert(1)',
    'https://facebook.com.evil.com/ads/library/',
    'https://web.facebook.com.evil.com/ads/library/',
    'https://webfacebook.com/ads/library/',
    'https://evilfacebook.com/ads/library/',
    'https://facebook.com@evil.com/ads/library/',
    'https://www.facebook.com/ads/libraryevil/',
    'https://user:pass@facebook.com/ads/library/',
    'https://facebook.com:8443/ads/library/',
    'https://facebook.com/ads/library/?view_all_page_id=nope',
    'https://facebook.com/ads/library/?id=1&id=2',
    'https://facebook.com\\@evil.com/ads/library/',
  ]) {
    test(
      'rejects unsafe or deceptive URL: $bad',
      () => expect(
        () => MetaAdsLibraryUrlBuilder.validateLibrary(bad),
        throwsFormatException,
      ),
    );
  }
  test('rejects invalid filters and IDs', () {
    expect(
      () => builder.build(text: 'x', country: 'INVALID'),
      throwsFormatException,
    );
    expect(
      () => builder.build(text: '1 OR 1=1', type: SearchType.pageId),
      throwsFormatException,
    );
    expect(() => builder.build(text: '  '), throwsFormatException);
  });
  test('shared text selects valid library links and removes duplicates', () {
    final links = MetaAdsLibraryUrlBuilder.sharedLinks(
      'Veja (https://www.facebook.com/ads/library/?id=123). https://www.facebook.com/ads/library/?id=123 https://evil.com https://www.facebook.com/ads/library/?view_all_page_id=456',
    );
    expect(links.length, 2);
    expect(MetaAdsLibraryUrlBuilder.pageId(links.last), '456');
    expect(
      MetaAdsLibraryUrlBuilder.sharedLinks(
        'javascript:alert(1) texto sem link',
      ),
      isEmpty,
    );
  });
  test('malformed inputs are bounded and parsed safely', () {
    expect(MetaAdsLibraryUrlBuilder.sharedLinks('https://%not_a_url'), isEmpty);
    expect(
      () => MetaAdsLibraryUrlBuilder.sharedLinks('x' * 65537),
      throwsFormatException,
    );
  });
  test(
    'canonical identity sorts keys and ignores fragment and mobile alias',
    () {
      expect(
        MetaAdsLibraryUrlBuilder.canonical(
          Uri.parse('https://m.facebook.com/ads/library/?q=x&country=BR#foo'),
        ),
        MetaAdsLibraryUrlBuilder.canonical(
          Uri.parse('https://www.facebook.com/ads/library/?country=BR&q=x'),
        ),
      );
    },
  );
  test('Page ID from a tapped advertiser profile link', () {
    String? id(String s) =>
        MetaAdsLibraryUrlBuilder.profilePageId(Uri.parse(s));
    expect(id('https://web.facebook.com/61569677676829/'), '61569677676829');
    expect(id('https://www.facebook.com/profile.php?id=1234567'), '1234567');
    expect(id('https://web.facebook.com/solides.rhportal/'), isNull);
    expect(id('https://evil.com/61569677676829/'), isNull);
    expect(id('http://www.facebook.com/61569677676829/'), isNull);
    expect(id('https://www.facebook.com/61569677676829/posts/1'), isNull);
    expect(id('https://www.facebook.com/profile.php?id=1&id=2'), isNull);
  });

  test('same view survives Meta URL rewrites', () {
    final typed = builder.build(text: 'planilha  financeira');
    final rewritten = Uri.parse(
      'https://web.facebook.com/ads/library/?active_status=active&ad_type=all&country=BR&is_targeted_country=false&media_type=all&q=planilha%20financeira&search_type=keyword_unordered&sort_data[mode]=total_impressions',
    );
    expect(MetaAdsLibraryUrlBuilder.sameView(typed, rewritten), isTrue);
    expect(
      MetaAdsLibraryUrlBuilder.sameView(
        typed,
        builder.build(text: 'planilha financeira', country: 'US'),
      ),
      isFalse,
    );
    expect(
      MetaAdsLibraryUrlBuilder.sameView(typed, builder.build(text: 'curso')),
      isFalse,
    );
    final page = builder.build(text: '123', type: SearchType.pageId);
    expect(
      MetaAdsLibraryUrlBuilder.sameView(
        page,
        Uri.parse(
          'https://web.facebook.com/ads/library/?view_all_page_id=123&sort_data[mode]=x',
        ),
      ),
      isTrue,
    );
    expect(MetaAdsLibraryUrlBuilder.sameView(page, typed), isFalse);
  });

  test('Meta regional redirect host is the same Library', () {
    final redirect = Uri.parse(
      'https://web.facebook.com/ads/library/?q=planilha&country=BR&_rdc=1&_rdr',
    );
    expect(MetaAdsLibraryUrlBuilder.isLibrary(redirect), isTrue);
    expect(
      MetaAdsLibraryUrlBuilder.canonical(redirect),
      startsWith('https://www.facebook.com/ads/library/'),
    );
  });
}
