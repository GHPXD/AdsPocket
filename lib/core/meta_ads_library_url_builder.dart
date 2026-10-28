enum SearchType {
  keyword('Palavra-chave'),
  advertiser('Anunciante / Página'),
  directLink('Link da Biblioteca'),
  pageId('ID público da Página');

  const SearchType(this.label);
  final String label;
}

const countries = <String, String>{
  'BR': 'Brasil',
  'US': 'Estados Unidos',
  'PT': 'Portugal',
  'GB': 'Reino Unido',
  'ALL': 'Todos os países',
};

class MetaAdsLibraryUrlBuilder {
  static final home = Uri.https('www.facebook.com', '/ads/library/');
  static const _hosts = {'facebook.com', 'www.facebook.com', 'm.facebook.com'};

  static String normalizeText(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ');

  static Uri? safeHttps(String text) {
    if (text.length > 8192 || RegExp(r'[\x00-\x20\\]').hasMatch(text)) {
      return null;
    }
    final uri = Uri.tryParse(text);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !uri.host.contains('.') ||
        uri.host.endsWith('.')) {
      return null;
    }
    return uri;
  }

  static bool isLibrary(Uri uri) =>
      safeHttps(uri.toString()) != null &&
      _hosts.contains(uri.host) &&
      (uri.path == '/ads/library' || uri.path.startsWith('/ads/library/'));

  static Uri validateLibrary(String text) {
    final uri = safeHttps(text.trim());
    if (uri == null || !isLibrary(uri)) {
      throw const FormatException(
        'Use um link HTTPS da Biblioteca oficial da Meta.',
      );
    }
    for (final key in ['view_all_page_id', 'id']) {
      final values = uri.queryParametersAll[key];
      if (values != null &&
          (values.length != 1 ||
              !RegExp(r'^\d{1,40}$').hasMatch(values.single))) {
        throw const FormatException(
          'O identificador público do link é inválido.',
        );
      }
    }
    return uri;
  }

  Uri build({
    required String text,
    SearchType type = SearchType.keyword,
    String country = 'BR',
    String status = 'active',
  }) {
    if (!countries.containsKey(country) ||
        !{'active', 'all'}.contains(status)) {
      throw const FormatException('Filtros inválidos.');
    }
    final query = normalizeText(text);
    if (query.isEmpty || query.length > 2000) {
      throw const FormatException(
        'Digite uma pesquisa com até 2.000 caracteres.',
      );
    }
    if (type == SearchType.directLink) return validateLibrary(query);
    final params = {
      'active_status': status,
      'ad_type': 'all',
      'country': country,
    };
    if (type == SearchType.pageId) {
      if (!RegExp(r'^\d{1,40}$').hasMatch(query)) {
        throw const FormatException('O Page ID deve conter apenas números.');
      }
      params.addAll({'view_all_page_id': query, 'search_type': 'page'});
    } else {
      // Advertiser selection remains in Meta's official autocomplete/UI.
      params.addAll({'q': query, 'search_type': 'keyword_unordered'});
    }
    return home.replace(queryParameters: params);
  }

  static String? pageId(Uri uri) {
    if (!isLibrary(uri)) return null;
    final values = uri.queryParametersAll['view_all_page_id'];
    return values?.length == 1 && RegExp(r'^\d{1,40}$').hasMatch(values!.single)
        ? values.single
        : null;
  }

  static SearchType identify(Uri uri) => pageId(uri) != null
      ? SearchType.pageId
      : uri.queryParameters.containsKey('q')
      ? SearchType.keyword
      : SearchType.directLink;

  static Map<String, String> parameters(Uri uri) =>
      Map.unmodifiable(uri.queryParameters);

  static String canonical(Uri uri) {
    final keys = uri.queryParameters.keys.toList()..sort();
    return uri
        .replace(
          host: isLibrary(uri) ? 'www.facebook.com' : uri.host,
          fragment: '',
          queryParameters: {
            for (final k in keys) k: uri.queryParametersAll[k]!,
          },
        )
        .toString();
  }

  static List<Uri> sharedLinks(String text) {
    if (text.length > 65536) {
      throw const FormatException('O texto compartilhado é muito grande.');
    }
    final result = <Uri>[];
    for (final match in RegExp(
      r'https://[^\s<>"\x00-\x1f]+',
      caseSensitive: false,
    ).allMatches(text)) {
      final candidate = match
          .group(0)!
          .replaceFirst(RegExp(r'[.,;!\)\]\}]+$'), '');
      try {
        final uri = validateLibrary(candidate);
        if (!result.any((u) => canonical(u) == canonical(uri))) result.add(uri);
      } on FormatException {
        /* Ignore unrelated or malformed links. */
      }
      if (result.length == 20) break;
    }
    return result;
  }
}
