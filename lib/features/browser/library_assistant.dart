import 'dart:convert';
import '../../core/longevity.dart';
import '../../core/meta_ads_library_url_builder.dart';
import '../../core/text_extraction.dart';
import '../../data/models.dart';
import '../../data/offer.dart';

/// One ad card as rendered by the Library and read from its visible text.
/// Everything is bounded and validated: the page is untrusted input.
class LibraryCard {
  const LibraryCard({
    required this.id,
    this.startText = '',
    this.active,
    this.advertiser = '',
    this.text = '',
    this.variations,
    this.multipleVersions = false,
    this.video = false,
    this.profile,
    this.cta,
  });
  final String id, startText, advertiser, text;
  final bool? active;
  final int? variations;
  final bool multipleVersions, video;
  final Uri? profile, cta;

  CivilDate? get start {
    final found = findDateCandidates(startText);
    return found.isEmpty ? null : found.first.date;
  }

  static String _clip(Object? v, int max) {
    final s = (v is String ? v : '').replaceAll('\u0000', '').trim();
    return s.length > max ? s.substring(0, max) : s;
  }

  static LibraryCard? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || !RegExp(r'^\d{5,40}$').hasMatch(id)) return null;
    final variations = raw['variations'];
    Uri? https(Object? v) =>
        v is String ? MetaAdsLibraryUrlBuilder.safeHttps(v) : null;
    return LibraryCard(
      id: id,
      startText: _clip(raw['start'], 160),
      active: raw['active'] is bool ? raw['active'] as bool : null,
      advertiser: _clip(raw['advertiser'], 200),
      text: _clip(raw['text'], 2000),
      variations: variations is int && variations > 0 && variations <= 10000
          ? variations
          : null,
      multipleVersions: raw['multiple'] == true,
      video: raw['video'] == true,
      profile: https(raw['profile']),
      cta: https(raw['cta']),
    );
  }

  /// Saved reference with every field the card shows; nothing is invented.
  Offer toOffer({String? pageId, DateTime? now}) {
    final at = (now ?? DateTime.now()).toUtc();
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final first = lines.isEmpty ? '' : lines.first;
    String cut(String s, int max) =>
        s.length <= max ? s : '${s.substring(0, max - 1).trimRight()}…';
    final date = start;
    final offer = Offer(
      id: localId(),
      name: cut(
        first.isNotEmpty
            ? first
            : advertiser.isNotEmpty
            ? 'Anúncio de $advertiser'
            : 'Anúncio $id',
        120,
      ),
      createdAt: at,
      updatedAt: at,
      advertiser: cut(advertiser, 200),
      pageId: pageId,
      adId: id,
      url: MetaAdsLibraryUrlBuilder.home
          .replace(queryParameters: {'id': id})
          .toString(),
      startDate: date,
      dateSource: date == null ? null : DateSource.library,
      mediaType: video ? MediaType.video : MediaType.unknown,
      salesUrl: cta?.toString(),
      hook: cut(first, 500),
      notes: '',
      variations: variations,
    );
    return active == null
        ? offer
        : offer.confirmStatus(
            active! ? AdStatus.active : AdStatus.inactive,
            at,
          );
  }
}

class AssistantStats {
  const AssistantStats({
    this.loaded = 0,
    this.visible = 0,
    this.active = 0,
    this.results = '',
    this.scrolling = false,
    this.url,
  });
  final int loaded, visible, active;

  /// Page where the counter was read; counts are tied to that view only.
  final Uri? url;

  /// Meta's own result count as displayed, e.g. "~180".
  final String results;
  final bool scrolling;

  static AssistantStats fromJson(Map raw) {
    int n(Object? v) => v is int && v >= 0 && v < 1000000 ? v : 0;
    final results = raw['results'];
    final match = RegExp(
      r'~?\s?[\d.,]+\s?[KkMm]?',
    ).firstMatch(results is String ? results : '');
    return AssistantStats(
      loaded: n(raw['loaded']),
      visible: n(raw['visible']),
      active: n(raw['active']),
      results: match?.group(0)?.replaceAll(' ', '') ?? '',
      scrolling: raw['scrolling'] == true,
      url: raw['url'] is String
          ? MetaAdsLibraryUrlBuilder.safeHttps(raw['url'] as String)
          : null,
    );
  }
}

/// Messages from the page script. Returns null for anything unexpected.
({
  String type,
  List<LibraryCard> cards,
  AssistantStats? stats,
  String? id,
  int found,
  String? page,
  String? name,
  bool pick,
})?
parseAssistantMessage(Object? raw) {
  if (raw is! String || raw.length > 2000000) return null;
  final Object? json;
  try {
    json = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (json is! Map || json['type'] is! String) return null;
  final cards = <LibraryCard>[
    for (final c
        in (json['cards'] is List ? json['cards'] as List : const []).take(500))
      ?LibraryCard.fromJson(c),
  ];
  final stats = json['stats'] is Map
      ? AssistantStats.fromJson(json['stats'] as Map)
      : null;
  final id = json['id'];
  final page = json['page'];
  final name = json['name'];
  return (
    type: json['type'] as String,
    cards: cards,
    stats: stats,
    id: id is String && RegExp(r'^\d{5,40}$').hasMatch(id) ? id : null,
    found: json['found'] is int && (json['found'] as int) >= 0
        ? json['found'] as int
        : 0,
    page: page is String && RegExp(r'^\d{5,40}$').hasMatch(page) ? page : null,
    name: name is String && name.trim().isNotEmpty
        ? LibraryCard._clip(name, 200)
        : null,
    pick: json['pick'] == true,
  );
}

/// Command sent to the page script after the app computed civil ages.
String assistantApply({
  required Map<String, int?> ages,
  required Iterable<String> saved,
  required int? minDays,
  required bool includeUndated,
  required int? minAds,
  Map<String, String> pages = const {},
}) =>
    'window.AdsPocketAssist && window.AdsPocketAssist.apply(${jsonEncode({'ages': ages, 'saved': saved.toList(), 'minDays': minDays, 'includeUndated': includeUndated, 'minAds': minAds, 'pages': pages})});';

/// Page script. It finds cards by their visible "Library ID" text instead of
/// CSS classes, adds a small action row (save, Page, copy, share, age) to
/// each card, hides cards outside the local filter (reversible) and can scroll
/// on request. On a Page tap it opens the ad details and reads the Page ID
/// shown under "Sobre o anunciante". It sends only what the page shows; it
/// never reads cookies, forms or credentials.
const assistantScript = r'''
(() => {
  if (window.AdsPocketAssist || !/^\/ads\/library\/?$/.test(location.pathname)) return;
  const ID = /(Library ID|Identificação da biblioteca|ID da biblioteca)\s*:?\s*(\d{5,40})/;
  const IDG = new RegExp(ID.source, 'g');
  const START = /(Started running on|Veiculação iniciada em|Começou a ser veiculad[oa] em|Iniciado em)[^\n]{0,80}/;
  const RANGE = /^[^\n]{0,40}\d{4}\s*[-–]\s*[^\n]{0,40}\d{4}$/m;
  // "Sobre o anunciante" in the ad details shows the Library Page ID.
  const DETAILS = /^(Ver detalhes do anúncio|See ad details)$/;
  const ABOUT = /(Sobre o anunciante|About the advertiser)/;
  const PAGE_ID = /(?:Identificação|ID da Página|Page ID|(?<!Library )ID)\s*:\s*(\d{5,40})/;
  const s = {cards: new Map(), roots: new WeakSet(), ages: {}, saved: new Set(), pages: {},
    minDays: null, includeUndated: true, minAds: null, timer: null, enabled: true, busy: null};
  const norm = (t) => (t || '').normalize ? (t || '').normalize('NFC') : (t || '');
  // Ads sharing this creative, as Meta prints it on the card (1 when absent).
  const ads = (c) => c.data.variations || 1;
  // The app bridge may appear after this script; queue early messages.
  const queue = [];
  const bridge = () => window.flutter_inappwebview && window.flutter_inappwebview.callHandler;
  const send = (m) => {
    if (!bridge()) { if (queue.length < 50) queue.push(m); return; }
    try { window.flutter_inappwebview.callHandler('adspocket', JSON.stringify(m)); } catch (e) {}
  };
  window.addEventListener('flutterInAppWebViewPlatformReady', () => { while (queue.length) send(queue.shift()); });
  const ids = (el) => (norm(el.textContent).match(IDG) || []).length;

  function rootOf(el) {
    let n = el;
    while (n.parentElement && n.parentElement !== document.body && ids(n.parentElement) === 1) n = n.parentElement;
    return n;
  }

  function parse(root, id) {
    const t = norm(root.innerText);
    const lines = t.split('\n').map((l) => l.trim()).filter(Boolean);
    const head = lines.slice(0, 4).join(' ');
    const sp = lines.findIndex((l) => /^(Sponsored|Patrocinado)$/.test(l));
    const start = (t.match(START) || t.match(RANGE) || [''])[0];
    // "24 ads use this creative and text" / "24 anúncios usam esse criativo e esse texto".
    const v = t.match(/(\d[\d.,]*)\s+(ads use this creative and text|anúncios usam (?:esse|este) criativo e (?:esse |este )?texto)/);
    let profile = null, cta = null;
    for (const a of root.querySelectorAll('a[href]')) {
      if (!profile && /^https:\/\/(www\.|web\.|m\.)?facebook\.com\/[^/?#]+\/?$/.test(a.href)) profile = a.href;
      if (!cta && a.href.indexOf('https://l.facebook.com/l.php') === 0) {
        try { const u = new URL(a.href).searchParams.get('u'); if (u && u.indexOf('https://') === 0) cta = u; } catch (e) {}
      }
    }
    return {
      id, start: start.slice(0, 160),
      active: /\b(Active|Ativo)\b/.test(head) ? true : /\b(Inactive|Inativo)\b/.test(head) ? false : null,
      advertiser: sp > 0 ? lines[sp - 1].slice(0, 200) : '',
      text: sp >= 0 ? lines.slice(sp + 1).filter((l) => !ID.test(l)).join('\n').slice(0, 2000) : '',
      variations: v ? parseInt(v[1].replace(/[.,]/g, ''), 10) : null,
      multiple: /multiple versions|várias versões/.test(t),
      video: !!root.querySelector('video'), profile, cta
    };
  }

  function visible() { let n = 0; for (const c of s.cards.values()) if (c.root.style.display !== 'none') n++; return n; }
  function stats() {
    let active = 0; for (const c of s.cards.values()) if (c.data.active === true) active++;
    // Meta keeps previous views in the DOM: use the visible counter only.
    let r = '';
    const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    while (w.nextNode()) {
      const t = (w.currentNode.nodeValue || '').trim();
      const el = w.currentNode.parentElement;
      if (/^~?\s?[\d.,]+\s?[KkMm]?\s+(results|resultados)$/.test(t) && el && el.getClientRects().length > 0) { r = t; break; }
    }
    return {loaded: s.cards.size, visible: visible(), active, results: r, scrolling: !!s.timer, url: location.href};
  }

  function scan() {
    if (!s.enabled || !document.body) return;
    // Meta swaps views without reloading; forget cards that left the page.
    for (const [id, c] of s.cards) if (!c.root.isConnected) s.cards.delete(id);
    const fresh = [];
    const w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
    const labels = [];
    while (w.nextNode()) {
      const v = norm(w.currentNode.nodeValue);
      if (/Library ID|Identificação da biblioteca|ID da biblioteca/.test(v)) labels.push(w.currentNode.parentElement);
    }
    for (let el of labels) {
      if (!el || el.closest('[data-adspocket]') || el.closest('[role=dialog]')) continue;
      let m = ID.exec(norm(el.textContent));
      if (!m && el.parentElement) { el = el.parentElement; m = ID.exec(norm(el.textContent)); }
      if (!m || s.cards.has(m[2])) continue;
      const root = rootOf(el);
      if (s.roots.has(root)) continue;
      s.roots.add(root);
      const data = parse(root, m[2]);
      s.cards.set(m[2], {root, data, display: root.style.display});
      badge(root, m[2]);
      fresh.push(data);
    }
    if (fresh.length) send({type: 'cards', cards: fresh, stats: stats()});
  }

  // Material icon paths; built with DOM calls (Trusted Types pages).
  const ICONS = {
    save: 'M17 3H7c-1.1 0-2 .9-2 2v16l7-3 7 3V5c0-1.1-.9-2-2-2z',
    saved: 'M9 16.17 4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z',
    page: 'M20 4H4v2h16V4zm1 10v-2l-1-5H4l-1 5v2h1v6h10v-6h4v6h2v-6h1zm-9 4H6v-4h6v4z',
    copy: 'M3.9 12c0-1.71 1.39-3.1 3.1-3.1h4V7H7c-2.76 0-5 2.24-5 5s2.24 5 5 5h4v-1.9H7c-1.71 0-3.1-1.39-3.1-3.1zM8 13h8v-2H8v2zm9-6h-4v1.9h4c1.71 0 3.1 1.39 3.1 3.1s-1.39 3.1-3.1 3.1h-4V17h4c2.76 0 5-2.24 5-5s-2.24-5-5-5z',
    share: 'M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11A2.99 2.99 0 0 0 21 5a3 3 0 1 0-5.91.7L8.04 9.81A2.99 2.99 0 0 0 3 12a2.99 2.99 0 0 0 5.04 2.19l7.12 4.16c-.05.21-.08.43-.08.65A2.92 2.92 0 1 0 18 16.08z'
  };
  function icon(name) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24'); svg.setAttribute('width', '18'); svg.setAttribute('height', '18');
    svg.style.cssText = 'display:block;fill:currentColor;pointer-events:none';
    const p = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    p.setAttribute('d', ICONS[name]); svg.appendChild(p);
    return svg;
  }
  function button(act, name, label, text, style) {
    const el = document.createElement('span');
    el.setAttribute('data-act', act); el.setAttribute('role', 'button');
    el.setAttribute('aria-label', label); el.title = label;
    el.appendChild(icon(name));
    if (text) { const t = document.createElement('span'); t.textContent = text; t.style.pointerEvents = 'none'; el.appendChild(t); }
    el.style.cssText = 'display:inline-flex;align-items:center;gap:4px;height:32px;' + (text ? 'padding:0 12px 0 9px;' : 'width:32px;justify-content:center;') + 'border-radius:16px;cursor:pointer;' + style;
    return el;
  }
  const onPage = () => /[?&]view_all_page_id=\d/.test(location.search);

  function badge(root, id) {
    let b = root.querySelector(':scope > [data-adspocket]');
    if (!b) {
      b = document.createElement('div');
      b.setAttribute('data-adspocket', id);
      b.style.cssText = 'display:flex;align-items:center;gap:6px;padding:10px 12px 4px;font:600 12px system-ui,sans-serif;color:#1c1e21';
      b.addEventListener('click', (e) => {
        const act = e.target && e.target.closest ? e.target.closest('[data-act]') : null;
        if (!act) return;
        e.preventDefault(); e.stopPropagation();
        const a = act.getAttribute('data-act');
        if (a === 'page') findPage(id); else send({type: a, id});
      }, true);
      root.insertBefore(b, root.firstChild);
    }
    const age = s.ages[id];
    const saved = s.saved.has(id);
    b.textContent = '';
    const brand = 'background:#5053d8;color:#fff;';
    b.appendChild(button('save', saved ? 'saved' : 'save', saved ? 'Salvo no AdsPocket' : 'Salvar no AdsPocket', '',
      saved ? 'background:#1a7f4b;color:#fff;' : brand));
    if (!onPage()) {
      b.appendChild(button('page', 'page', 'Ver todos os anúncios ativos desta Página', s.busy === id ? 'Abrindo…' : 'Página', brand));
    }
    b.appendChild(button('copy', 'copy', 'Copiar link do anúncio', '', 'background:#eef0f3;color:#1c1e21;'));
    b.appendChild(button('share', 'share', 'Compartilhar anúncio', '', 'background:#eef0f3;color:#1c1e21;'));
    const n = s.cards.has(id) ? ads(s.cards.get(id)) : 1;
    const parts = [];
    if (age != null) parts.push(age < 0 ? 'data futura' : age === 1 ? '1 dia' : age + ' dias');
    if (n > 1) parts.push(n + ' anúncios');
    if (parts.length) {
      const pill = document.createElement('span');
      pill.textContent = parts.join(' · ');
      const hit = s.minDays != null && age != null && age >= s.minDays;
      pill.style.cssText = 'margin-left:auto;padding:5px 10px;border-radius:14px;white-space:nowrap;text-transform:uppercase;letter-spacing:.3px;font-size:11px;' + (hit ? 'background:#1a7f4b;color:#fff' : 'background:#1c1e21;color:#fff');
      b.appendChild(pill);
    }
  }

  // The Page ID printed on a card link is the profile ID, which often differs
  // from the Library Page ID. The ad details show the real one under
  // "Sobre o anunciante": open them as the user would, read it, close them.
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));
  async function until(fn, ms) { for (let t = 0; t <= ms; t += 250) { const v = fn(); if (v) return v; await wait(250); } return null; }
  // The control itself (role=button) wins over wrappers with the same text.
  function byText(scope, re) {
    const hit = (e) => re.test(norm(e.textContent).trim()) && e.getClientRects().length;
    for (const e of scope.querySelectorAll('[role=button],a[href]')) if (hit(e)) return e;
    for (let e of scope.querySelectorAll('span,div')) {
      if (!hit(e)) continue;
      // Clicks bubble up, not down: target the innermost element with the text.
      for (let inner = e; inner; inner = [...e.children].find(hit)) e = inner;
      return e.closest('[role=button]') || e;
    }
    return null;
  }
  function dialogOf(id) {
    const all = [...document.querySelectorAll('[role=dialog]')].filter((d) => d.getClientRects().length && norm(d.textContent).indexOf(id) >= 0);
    return all.length ? all[all.length - 1] : null;
  }
  function pageIn(dlg) {
    const t = norm(dlg.innerText);
    const m = ABOUT.exec(t);
    if (!m) return null;
    const rest = t.slice(m.index + m[0].length);
    const p = PAGE_ID.exec(rest);
    if (!p) return null;
    const name = rest.split('\n').map((l) => l.trim()).filter(Boolean)[0] || '';
    return {page: p[1], name: PAGE_ID.test(name) ? '' : name.slice(0, 200)};
  }
  async function findPage(id) {
    const c = s.cards.get(id);
    const profile = c && c.data.profile;
    const known = s.pages[id] || (profile && s.pages['p:' + profile]);
    if (known) { send({type: 'page', id, page: known}); return; }
    if (s.busy || !c) return;
    s.busy = id; badge(c.root, id);
    let found = null, dlg = null;
    try {
      const open = byText(c.root, DETAILS);
      if (open) {
        open.click();
        dlg = await until(() => dialogOf(id), 6000);
      }
      if (dlg) {
        found = pageIn(dlg);
        if (!found) {
          const about = byText(dlg, /^(Sobre o anunciante|About the advertiser)$/);
          if (about) about.click();
          found = await until(() => pageIn(dlg), 3500);
        }
      }
    } catch (e) {}
    if (dlg) {
      const close = dlg.querySelector('[aria-label="Fechar"],[aria-label="Close"]') || byText(dlg, /^(Fechar|Close)$/);
      if (close) close.click();
    }
    let pick = false;
    if (!found) { await wait(600); pick = await suggest(c.data); }
    s.busy = null;
    if (found) { s.pages[id] = found.page; if (profile) s.pages['p:' + profile] = found.page; }
    if (s.cards.has(id)) badge(c.root, id);
    send({type: 'page', id, page: found ? found.page : null, name: found ? found.name : c.data.advertiser, pick});
  }

  // Older Pages show no ID in the details. Then do what the user would do:
  // type the advertiser in Meta's search and point at the matching entry in
  // its "Anunciantes" list. Meta only accepts a real tap there, so the user
  // makes the choice; nothing is selected on their behalf.
  async function suggest(card) {
    const name = (card.advertiser || '').trim();
    const input = document.querySelector('input[type=search], input[placeholder]');
    if (!name || !input) return false;
    window.scrollTo(0, 0);
    input.focus();
    const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    set.call(input, name);
    input.dispatchEvent(new Event('input', {bubbles: true}));
    const handle = (() => { const m = /facebook\.com\/([A-Za-z0-9.]{3,80})\/?$/.exec(card.profile || ''); return m && !/^\d+$/.test(m[1]) ? '@' + m[1].toLowerCase() : null; })();
    const options = await until(() => {
      const o = [...document.querySelectorAll('[role=listbox] [role=option]')].filter((e) => norm(e.innerText).trim().split('\n')[0].trim() === name);
      return o.length ? o : null;
    }, 6000);
    if (!options) return true;
    const exact = handle ? options.filter((e) => norm(e.innerText).toLowerCase().indexOf(handle) >= 0) : [];
    const target = exact.length === 1 ? exact[0] : options.length === 1 ? options[0] : null;
    if (target) {
      target.style.outline = '3px solid #5053d8';
      target.style.outlineOffset = '-3px';
      target.style.borderRadius = '8px';
      target.scrollIntoView({block: 'nearest'});
    }
    return true;
  }

  function filter() {
    for (const [id, c] of s.cards) {
      const age = s.ages[id];
      let hide = false;
      if (s.minDays != null) hide = age == null ? !s.includeUndated : age < s.minDays;
      if (s.minAds != null && ads(c) < s.minAds) hide = true;
      c.root.style.display = hide ? 'none' : c.display;
      badge(c.root, id);
    }
  }

  // Feed mode: Meta pins its header, search and filter bars (almost half of
  // a phone screen). They are unpinned, not hidden: they scroll with the page
  // and stay one swipe up. Card subtrees are skipped to keep this cheap.
  function unpin() {
    if (!document.body) return;
    const w = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT, {
      acceptNode: (n) => n.hasAttribute('data-adspocket') || s.roots.has(n) || n.getAttribute('role') === 'dialog' ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
    });
    while (w.nextNode()) {
      const el = w.currentNode;
      if (el.hasAttribute('data-adspocket-pin') || getComputedStyle(el).position !== 'sticky') continue;
      const r = el.getBoundingClientRect();
      if (r.width < window.innerWidth * 0.9 || r.height > window.innerHeight * 0.4) continue;
      el.setAttribute('data-adspocket-pin', el.style.position || '');
      el.style.position = 'static';
    }
  }
  function repin() {
    for (const el of document.querySelectorAll('[data-adspocket-pin]')) { el.style.position = el.getAttribute('data-adspocket-pin'); el.removeAttribute('data-adspocket-pin'); }
  }

  function moreButton() {
    for (const e of document.querySelectorAll('[role=button]')) {
      if (!/^(Ver mais|See more)$/.test(norm(e.textContent).trim()) || !e.getClientRects().length) continue;
      if (e.closest('[role=dialog]') || e.closest('[data-adspocket]')) continue;
      let inCard = false;
      for (const c of s.cards.values()) if (c.root.contains(e)) { inCard = true; break; }
      if (!inCard) return e;
    }
    return null;
  }

  function stop() { if (s.timer) { clearInterval(s.timer); s.timer = null; } }
  // Throttle, not debounce: videos and timers mutate the page all the time,
  // and a debounce would postpone the scan forever.
  let pending = null;
  const observer = new MutationObserver(() => { if (!pending) pending = setTimeout(() => { pending = null; scan(); }, 700); });

  window.AdsPocketAssist = {
    apply(cfg) {
      Object.assign(s.ages, cfg.ages || {});
      s.saved = new Set(cfg.saved || []);
      Object.assign(s.pages, cfg.pages || {});
      s.minDays = cfg.minDays; s.includeUndated = cfg.includeUndated !== false; s.minAds = cfg.minAds == null ? null : cfg.minAds;
      filter();
      send({type: 'stats', stats: stats()});
    },
    autoScroll(target) {
      stop();
      // Look for `target` more cards that pass the filter, from here on.
      const start = visible(), goal = start + target;
      let last = -1, idle = 0, steps = 0;
      s.timer = setInterval(() => {
        scan();
        const n = visible();
        const done = n >= goal ? 'target' : idle >= 10 ? 'end' : steps++ >= 300 ? 'limit' : null;
        if (done) { stop(); send({type: 'scrollDone', id: null, reason: done, found: n - start, stats: stats()}); return; }
        const el = document.scrollingElement || document.documentElement;
        const atEnd = el.scrollTop + window.innerHeight >= el.scrollHeight - 4;
        // Only count idle time at the bottom, where Meta loads the next page.
        if (s.cards.size !== last) { idle = 0; last = s.cards.size; } else if (atEnd) idle++;
        // Some result lists end with Meta's own "Ver mais" instead of loading
        // on scroll; press it like the user would (never one inside a card).
        if (atEnd && idle >= 2 && idle % 3 === 2) { const more = moreButton(); if (more) more.click(); }
        el.scrollTop = Math.min(el.scrollTop + Math.round(window.innerHeight * 1.5), el.scrollHeight);
        send({type: 'stats', stats: stats()});
      }, 1000);
      send({type: 'stats', stats: stats()});
    },
    stop() { stop(); send({type: 'stats', stats: stats()}); },
    feed(on) {
      clearInterval(s.feedTimer); s.feedTimer = null;
      if (on) { unpin(); s.feedTimer = setInterval(unpin, 1500); } else repin();
    },
    disable() {
      s.enabled = false; stop(); observer.disconnect();
      for (const c of s.cards.values()) { c.root.style.display = c.display; const b = c.root.querySelector(':scope > [data-adspocket]'); if (b) b.remove(); }
      s.cards.clear(); s.roots = new WeakSet();
    },
    enable() { s.enabled = true; if (document.body) observer.observe(document.body, {childList: true, subtree: true}); scan(); },
    rescan: scan
  };
  // Meta's automatic verification page may have no body yet.
  if (document.body) observer.observe(document.body, {childList: true, subtree: true});
  scan();
  send({type: 'ready', stats: stats()});
})();
''';
