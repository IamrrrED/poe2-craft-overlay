/*
 * PoE2 Market MCP : lib/trade.js
 *
 * The official trade site. Verified from this workspace: a plain POST to
 * /api/trade2/search/poe2/{league} works without a session cookie, and the follow-up
 * GET /api/trade2/fetch/{ids}?query={id} returns listings with prices and mods.
 * That is what makes real "cheapest listing vs median" math possible without Playwright.
 *
 * Read-only by design: this module searches and reads. It never whispers, invites or
 * clicks - automation of trading is against GGG's third-party policy.
 */

'use strict';

const { fetchJson } = require('./http.js');

let BASE = 'https://www.pathofexile.com';
const STATS_TTL = 12 * 60 * 60 * 1000;

/**
 * Point the library at another language's trade site.
 *
 * The site is localised by HOST, not by a query parameter: ru.pathofexile.com serves Russian base names,
 * Russian stat texts and Russian league names, and it knows bases the English catalogue does not have at all
 * (the Russian list holds 3901 bases including "Mask of the Pariah", the English 3900 does not). Every cache
 * in http.js is keyed by URL, so switching hosts keeps the two catalogues apart.
 *
 * @param {string} host e.g. "ru.pathofexile.com"
 */
function setHost(host) {
  const clean = String(host || 'www.pathofexile.com').replace(/^https?:\/\//, '').replace(/\/+$/, '');
  BASE = 'https://' + clean;
}

/** The host currently in use, for callers that build their own URLs (the item catalogue). */
function baseUrl() {
  return BASE;
}

async function leagues() {
  return fetchJson(`${BASE}/api/trade2/data/leagues`, { cacheTtlMs: 60 * 60 * 1000 });
}

/** Flat list of trade stat entries: [{ id, text, type }]. ~30k rows, cached on disk. */
async function statIndex() {
  const data = await fetchJson(`${BASE}/api/trade2/data/stats`, { cacheTtlMs: STATS_TTL });
  const flat = [];
  for (const group of data.result || []) {
    for (const entry of group.entries || []) {
      flat.push({ id: entry.id, text: entry.text, type: group.id });
    }
  }
  return flat;
}

const normalize = (text) => String(text || '')
  .toLowerCase()
  .replace(/\r?\n/g, ' ')
  .replace(/[#%+]/g, ' ')
  // Only punctuation is stripped, NOT letters of other alphabets: the previous pattern kept a-z0-9 and
  // dropped everything else, so a Russian stat text normalised to an empty string and the search could never
  // resolve a single modifier on the Russian trade site.
  .replace(/[^\p{L}\p{N} ]+/gu, ' ')
  .replace(/\s+/g, ' ')
  .trim();

/**
 * Find the trade stat ids for a human mod string such as
 * "+# to Level of all Spell Skills" or "#% increased Movement Speed".
 * Exact matches win; otherwise the shortest containing line does.
 *
 * @param {string} text
 * @param {{limit?:number, types?:string[]}} [options]
 */
async function resolveStat(text, options = {}) {
  const index = await statIndex();
  const wanted = normalize(text);
  if (!wanted) return { query: text, matches: [] };
  const types = options.types || ['explicit', 'pseudo', 'implicit', 'desecrated', 'fractured'];

  const scored = [];
  for (const entry of index) {
    if (!types.includes(entry.type)) continue;
    const hay = normalize(entry.text);
    if (!hay) continue;
    let score = 0;
    if (hay === wanted) score = 1000;
    else if (hay.startsWith(wanted)) score = 700 - hay.length / 100;
    else if (hay.includes(wanted)) score = 500 - hay.length / 100;
    else continue;
    if (entry.type === 'explicit') score += 20;
    scored.push({ ...entry, score });
  }

  scored.sort((a, b) => b.score - a.score);
  return {
    query: text,
    matches: scored.slice(0, options.limit || 5).map(({ score, ...rest }) => rest),
  };
}

/** Turn preset stat specs ({ text, min, max }) into trade filters. */
async function buildStatFilters(specs) {
  const filters = [];
  const resolved = [];
  for (const spec of specs || []) {
    const { matches } = await resolveStat(spec.text, { limit: 1 });
    if (!matches.length) {
      resolved.push({ text: spec.text, resolvedId: null });
      continue;
    }
    const id = matches[0].id;
    const value = {};
    if (spec.min !== undefined && spec.min !== null) value.min = spec.min;
    if (spec.max !== undefined && spec.max !== null) value.max = spec.max;
    filters.push({ id, value, disabled: false });
    resolved.push({ text: spec.text, resolvedId: id, matchedText: matches[0].text, min: value.min, max: value.max });
  }
  return { filters, resolved };
}

/**
 * Статус торговли в запросе. Проверено на живом API (data/filters → status_filters):
 *   securable    - «Instant Buyout»: предмет забирается сразу, продавец не нужен
 *   available    - «Instant Buyout and In Person»: и то, и другое
 *   onlineleague - «In Person (Online in League)»: только личная встреча
 *   online       - личная встреча, продавец в сети
 *   any          - без ограничения (поле status в запрос не добавляется)
 *
 * Важно: раньше здесь жёстко стоял 'online' - то есть искали только в личной встрече.
 * На замере это 5-9 лотов против 4290-7484 у мгновенного выкупа.
 */
const TRADE_STATUSES = ['securable', 'available', 'onlineleague', 'online', 'any'];
const DEFAULT_TRADE_STATUS = 'securable';

/** JSON body for a trade search built from a preset definition. */
function buildQuery(preset, extra = {}) {
  const status = TRADE_STATUSES.includes(extra.status) ? extra.status : DEFAULT_TRADE_STATUS;

  // Вариант предмета. Коррапченный и неопознанный уникал стоят иначе, чем чистый,
  // поэтому их нужно уметь запрашивать отдельно, а не сваливать в одну медиану.
  /** @type {Record<string, { option: string }>} */
  const misc = {};
  if (extra.corrupted === true || extra.corrupted === false) misc.corrupted = { option: String(extra.corrupted) };
  if (extra.identified === true || extra.identified === false) misc.identified = { option: String(extra.identified) };

  /** @type {{ status?: { option: string }, name?: string, type?: string, filters: any, stats: any[] }} */
  const query = {
    ...(status === 'any' ? {} : { status: { option: status } }),
    ...(preset.name ? { name: preset.name } : {}),
    ...(preset.type ? { type: preset.type } : {}),
    filters: {
      trade_filters: {
        filters: {
          sale_type: { option: 'priced' },
          // Поиск по продавцу: так находятся свои лоты — их и мониторим (выставлен / продан).
          ...(extra.account ? { account: { input: extra.account } } : {}),
        },
      },
      ...(Object.keys(misc).length ? { misc_filters: { filters: misc } } : {}),
    },
    stats: [{ type: 'and', filters: extra.statFilters || [] }],
  };

  // A Waystone is priced by its TIER: a tier-15 map and a tier-1 map share the base name and nothing else.
  if (Number.isFinite(extra.mapTier)) {
    query.filters.map_filters = { filters: { map_tier: { min: extra.mapTier, max: extra.mapTier } } };
  }

  if (extra.priceMax) {
    query.filters.trade_filters.filters.price = {
      option: extra.priceCurrency || 'divine',
      max: extra.priceMax,
      ...(extra.priceMin ? { min: extra.priceMin } : {}),
    };
  } else if (extra.priceMin) {
    query.filters.trade_filters.filters.price = {
      option: extra.priceCurrency || 'divine',
      min: extra.priceMin,
    };
  }
  return { query, sort: { price: extra.sort || 'asc' } };
}

/** Clickable site URL for a query body (the reliable fallback for a human). */
function searchUrl(league, body) {
  return `${BASE}/trade2/search/poe2/${encodeURIComponent(league)}`
    + `?q=${encodeURIComponent(JSON.stringify(body))}`;
}

/** Bulk item exchange URL (stackables only: currency, omens, catalysts, essences). */
function exchangeUrl(league, have, want) {
  const body = {
    exchange: { status: { option: 'online' }, have: [have], want: [want] },
    sort: { have: 'asc' },
  };
  return `${BASE}/trade2/exchange/poe2/${encodeURIComponent(league)}`
    + `?q=${encodeURIComponent(JSON.stringify(body))}`;
}

/** Trade returns mods either as strings or as { text, ... } objects depending on item. */
function modText(entry) {
  if (typeof entry === 'string') return entry;
  if (entry && typeof entry === 'object') return entry.text || entry.description || JSON.stringify(entry);
  return String(entry);
}

/**
 * Run a search and read the listings.
 * @param {object} opts
 * @param {string} opts.league
 * @param {object} opts.body   query body from buildQuery()
 * @param {number} [opts.samples] how many listings to read (1..50)
 */
async function search(opts) {
  const samples = Math.max(1, Math.min(opts.samples || 20, 50));
  const url = `${BASE}/api/trade2/search/poe2/${encodeURIComponent(opts.league)}`;
  const response = await fetchJson(url, {
    method: 'POST',
    body: opts.body,
    cacheTtlMs: opts.cacheTtlMs === undefined ? 2 * 60 * 1000 : opts.cacheTtlMs,
  });

  const ids = (response.result || []).slice(0, samples);
  if (!ids.length) {
    return { total: response.total || 0, listings: [], queryId: response.id, fetchUrl: null };
  }

  const listings = [];
  for (let i = 0; i < ids.length; i += 10) {
    const chunk = ids.slice(i, i + 10);
    const fetchUrl = `${BASE}/api/trade2/fetch/${chunk.join(',')}?query=${response.id}`;
    const payload = await fetchJson(fetchUrl, { cacheTtlMs: 2 * 60 * 1000 });
    for (const entry of payload.result || []) {
      const listing = entry.listing || {};
      const item = entry.item || {};
      listings.push({
        price: listing.price ? { amount: Number(listing.price.amount), currency: listing.price.currency } : null,
        account: listing.account ? listing.account.name : null,
        // Продавец «в игре» и его персонаж: по этому видно, кому вообще есть смысл писать.
        online: Boolean(listing.account && listing.account.online),
        character: listing.account ? listing.account.lastCharacterName || null : null,
        indexed: listing.indexed || null,
        whisper: listing.whisper || null,
        name: item.name || null,
        typeLine: item.typeLine || item.baseType || null,
        ilvl: item.ilvl || null,
        corrupted: item.corrupted === true,
        // Unidentified uniques are legitimately cheaper, but they cannot be compared to
        // the price of identified ones - the flag travels with the listing.
        identified: item.identified !== false,
        mods: (item.explicitMods || []).map(modText),
      });
    }
  }

  return { total: response.total || 0, queryId: response.id, listings };
}

/**
 * Только поиск, без чтения лотов: нужен один total. Дёшево и точно - так строится
 * распределение рынка по диапазонам цен (у «20 самых дешёвых» всегда один и тот же кластер).
 */
async function searchCount(opts) {
  const url = `${BASE}/api/trade2/search/poe2/${encodeURIComponent(opts.league)}`;
  const response = await fetchJson(url, {
    method: 'POST',
    body: opts.body,
    cacheTtlMs: opts.cacheTtlMs === undefined ? 2 * 60 * 1000 : opts.cacheTtlMs,
  });
  return { total: response.total || 0, id: response.id };
}

module.exports = {
  setHost,
  baseUrl,
  leagues,
  statIndex,
  resolveStat,
  buildStatFilters,
  buildQuery,
  searchUrl,
  exchangeUrl,
  search,
  searchCount,
  TRADE_STATUSES,
  DEFAULT_TRADE_STATUS,
};
