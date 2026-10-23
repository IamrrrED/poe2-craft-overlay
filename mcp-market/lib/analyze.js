/*
 * PoE2 Market MCP : lib/analyze.js
 *
 * Turns a preset into an answer: what the item costs on poe2scout, what the cheapest
 * live listings are on the official trade site, and whether the gap is worth a flip.
 *
 * Honesty rules baked in:
 *  - the "market price" from poe2scout and the "median listing" from the trade site are
 *    asking prices, not sale prices. A thin order book inflates both.
 *  - a flip verdict is only issued when the preset has enough listings to matter.
 */

'use strict';

const scout = require('./scout.js');
const trade = require('./trade.js');
const { RateLimitError } = require('./http.js');
const { getPreset } = require('./presets.js');

function median(values) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

function round(value, digits = 2) {
  if (value === null || value === undefined || Number.isNaN(value)) return null;
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
}

/** Prices span 0.002 div (junk uniques) to 800 div — keep four decimals below 1. */
function roundPrice(value) {
  if (value === null || value === undefined || Number.isNaN(value)) return null;
  return round(value, Math.abs(value) < 1 ? 4 : 2);
}

/** Live listing stats for one query body. */
async function listingStats(opts) {
  const { league, body, rates, samples } = opts;
  const result = await trade.search({ league, body, samples: samples || 20, cacheTtlMs: opts.cacheTtlMs });
  const prices = result.listings
    .map((l) => (l.price ? rates.toDivine(l.price.amount, l.price.currency) : null))
    .filter((v) => v !== null && v !== undefined && v > 0)
    .sort((a, b) => a - b);

  const med = median(prices);
  // Bait listings (1 exalted for a 100 div item) are everywhere on the trade site.
  // Anything below a quarter of the median is noise, not an opportunity.
  const floor = med ? med * 0.25 : 0;
  const realistic = floor > 0 ? prices.filter((p) => p >= floor) : prices;
  const sortedForSpread = [...prices].sort((a, b) => a - b);
  const p90 = percentileOf(sortedForSpread, 0.9);
  const p50 = median(sortedForSpread);

  return {
    total: result.total,
    sampled: prices.length,
    honestSample: realistic.length,
    baitListings: prices.length - realistic.length,
    rawMinDivine: prices.length ? roundPrice(prices[0]) : null,
    minDivine: realistic.length ? roundPrice(realistic[0]) : null,
    medianDivine: roundPrice(med),
    priceStats: {
      p25: roundPrice(percentileOf(sortedForSpread, 0.25)),
      p50: roundPrice(p50),
      p75: roundPrice(percentileOf(sortedForSpread, 0.75)),
      p90: roundPrice(p90),
      // A tight cluster at the bottom plus a huge spread means price fixing, not a market.
      baitCluster: Boolean(looksLikeBaitCluster(sortedForSpread)),
      // Все дешёвые лоты по одной цене - стена, а не рынок.
      uniformWall: looksLikeUniformWall(sortedForSpread),
    },
    confidence: prices.length >= 5 ? 'ok' : 'low',
    // Разбивка по вариантам: «чистый / коррапченный / неопознанный» - разные рынки.
    variants: variantStats(result.listings, rates),
    url: trade.searchUrl(league, body),
    listings: result.listings,
  };
}

function percentileOf(sorted, p) {
  if (!sorted.length) return null;
  const index = Math.min(sorted.length - 1, Math.max(0, Math.round((sorted.length - 1) * p)));
  return sorted[index];
}

/**
 * Стена одинаковых цен. На Headhunter с мгновенным выкупом 1178 лотов стоят по 19 div, тогда
 * как реальный рынок ~60-95: выборка «20 самых дешёвых» состоит из стены целиком, и ни
 * справедливой цены, ни сделок по ней получить нельзя. Такую выборку нужно перезапросить выше стены.
 *
 * @param {number[]} sortedPrices цены лотов, по возрастанию
 * @returns {{price: number, atPrice: number, sample: number, share: number}|null}
 */
function looksLikeUniformWall(sortedPrices) {
  if (!sortedPrices || sortedPrices.length < 8) return null;
  const p25 = percentileOf(sortedPrices, 0.25);
  const p75 = percentileOf(sortedPrices, 0.75);
  if (!p25 || !p75) return null;
  if (p75 / p25 > 1.1) return null;
  const price = roundPrice(p25);
  const atPrice = sortedPrices.filter((p) => Math.abs(p - price) <= price * 0.1).length;
  return {
    price,
    atPrice,
    sample: sortedPrices.length,
    share: Math.round((atPrice / sortedPrices.length) * 100) / 100,
  };
}

/**
 * Вариант предмета. Коррапченный Headhunter стоит 13 div, чистый - 45-90 div: это разные
 * рынки, и общая медиана по ним бессмысленна.
 */
function variantKey(listing) {
  if (listing.identified === false) return 'unidentified';
  return listing.corrupted ? 'corrupted' : 'clean';
}

/**
 * Цены, разложенные по вариантам предмета: у каждого свой минимум и медиана.
 * Чистая функция - считается по уже прочитанным лотам, без лишних запросов к трейд-сайту.
 *
 * @param {object[]} listings лоты из trade.search()
 * @param {{toDivine: (amount: number, currency: string) => number|null}} rates
 */
function variantStats(listings, rates) {
  const buckets = new Map();
  for (const listing of listings || []) {
    if (!listing.price) continue;
    const divine = rates.toDivine(listing.price.amount, listing.price.currency);
    if (!divine || divine <= 0) continue;
    const key = variantKey(listing);
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push(divine);
  }

  const out = {};
  for (const [key, prices] of buckets) {
    const sorted = [...prices].sort((a, b) => a - b);
    out[key] = {
      sample: sorted.length,
      minDivine: roundPrice(sorted[0]),
      p25: roundPrice(percentileOf(sorted, 0.25)),
      p50: roundPrice(percentileOf(sorted, 0.5)),
      p75: roundPrice(percentileOf(sorted, 0.75)),
      medianDivine: roundPrice(median(sorted)),
    };
  }
  return out;
}

/**
 * True when the sampled prices look like a price-fixing wall: the bottom of the market
 * is a tight cluster while the top is an order of magnitude away (Ingenuity: 265 listings,
 * cheapest twelve at 1-5 exalted). Such a query must not produce "deals".
 */
function looksLikeBaitCluster(sortedPrices) {
  if (sortedPrices.length < 5) return false;
  const p50 = percentileOf(sortedPrices, 0.5);
  const p90 = percentileOf(sortedPrices, 0.9);
  if (!p50 || !p90) return false;
  return p90 / p50 >= 5;
}

/**
 * Live lookup that survives throttling: the trade site answers 429 with windows of
 * several minutes, and a market tool that dies instead of saying "не сейчас" is useless.
 * Returns { live } or { live: null, warning, url }.
 */
async function safeListingStats(opts, url) {
  try {
    return { live: await listingStats(opts) };
  } catch (error) {
    if (!(error instanceof RateLimitError)) throw error;
    return {
      live: null,
      warning: `торговый сайт ограничил запросы (${error.message}); подождите или откройте ссылку в браузере`,
      url,
    };
  }
}

/**
 * @param {number} margin (median - min) / median, outliers already dropped
 * @param {number} liquidity number of competing listings
 * @param {number} [sampled] listings actually read
 */
function verdict(margin, liquidity, sampled) {
  if (sampled !== undefined && sampled < 5) return 'мало данных: прочитано < 5 лотов';
  if (margin === null || liquidity === null) return 'нет данных';
  if (liquidity < 5) return 'риск: почти нет предложений';
  if (margin >= 0.3) return 'сильная маржа';
  if (margin >= 0.15) return 'есть маржа';
  if (margin >= 0.05) return 'тонкая маржа';
  return 'маржи нет';
}

function flipRow(name, market, live, minLots) {
  const margin = live.medianDivine && live.minDivine
    ? (live.medianDivine - live.minDivine) / live.medianDivine
    : null;
  const liquidity = market && market.lots !== undefined && market.lots !== null
    ? market.lots
    : live.total;
  const row = {
    name,
    marketPriceDivine: market ? roundPrice(market.priceDivine) : null,
    marketLots: market ? market.lots : null,
    change7d: market ? round(market.change7d) : null,
    cheapestListingDivine: live.minDivine,
    medianListingDivine: live.medianDivine,
    baitListingsDropped: live.baitListings,
    listingsOnTrade: live.total,
    sampled: live.sampled,
    confidence: live.confidence,
    margin: round(margin, 4),
    verdict: verdict(margin, liquidity, live.sampled),
    url: live.url,
  };
  if (minLots !== undefined && row.marketLots !== null && row.marketLots < minLots) {
    row.warning = `лишь ${row.marketLots} предложений на poe2scout - легко ошибиться в цене`;
  }
  return row;
}

/** Market snapshot (poe2scout) for a set of uniques, grouped by category. */
async function marketSnapshot(league, uniques) {
  const byCategory = new Map();
  for (const entry of uniques) {
    const category = entry.category || 'accessory';
    if (!byCategory.has(category)) byCategory.set(category, []);
    byCategory.get(category).push(entry);
  }

  const found = new Map();
  for (const [category, entries] of byCategory) {
    const items = await scout.allUniques({ league, category, dataPoints: 7 });
    for (const entry of entries) {
      const wanted = entry.name.toLowerCase();
      const item = items.find((i) => String(i.Name).toLowerCase() === wanted);
      if (item) found.set(entry.name, item);
    }
  }
  return found;
}

/**
 * The main question: "is there money in this preset right now?"
 *
 * @param {object} opts
 * @param {string} opts.presetId
 * @param {string} [opts.league]
 * @param {number} [opts.samples]   listings to read per query
 * @param {number} [opts.priceMax]  cap in divine (buyout filter)
 * @param {number} [opts.minLots]   warn below this many market offers
 */
async function flipReport(opts) {
  const { preset, leagueDefault, available } = getPreset(opts.presetId);
  if (!preset) {
    return { error: `unknown preset: ${opts.presetId}`, available };
  }
  const league = opts.league || leagueDefault;
  const rates = await scout.ratesFor(league);
  const minLots = opts.minLots === undefined ? 20 : opts.minLots;

  if (preset.kind === 'bulk') {
    return {
      preset: { id: preset.id, title: preset.title, kind: preset.kind, why: preset.why },
      league,
      exchangeUrl: trade.exchangeUrl(league, preset.exchange.have, preset.exchange.want),
      note: 'bulk-exchange работает только со стеклянными предметами: валюта, знамения, катализаторы, эссенции, осколки.',
    };
  }

  if (preset.kind === 'unique') {
    const uniques = preset.uniques || [{ name: preset.search.name, category: 'armour' }];
    const snapshot = await marketSnapshot(league, uniques);
    const rows = [];
    for (const entry of uniques) {
      const item = snapshot.get(entry.name);
      const market = item
        ? {
          priceChaos: item.CurrentPrice,
          priceDivine: rates.toDivine(item.CurrentPrice, 'chaos'),
          lots: item.CurrentQuantity,
          change7d: scout.change7d(item),
        }
        : null;
      const body = trade.buildQuery({ name: entry.name }, {
        priceMax: opts.priceMax,
        priceCurrency: opts.priceCurrency,
        statFilters: [],
      });
      const live = await safeListingStats(
        { league, body, rates, samples: opts.samples },
        trade.searchUrl(league, body),
      );
      if (!live.live) {
        rows.push({
          name: entry.name,
          marketPriceDivine: market ? roundPrice(market.priceDivine) : null,
          marketLots: market ? market.lots : null,
          unavailable: true,
          warning: live.warning,
          url: live.url,
        });
        continue;
      }
      rows.push(flipRow(entry.name, market, live.live, minLots));
    }
    return {
      preset: { id: preset.id, title: preset.title, kind: preset.kind, why: preset.why },
      league,
      divineInChaos: rates.divineInChaos,
      rows,
      caveat: 'Цена poe2scout и медиана лотов - это запросы продавцов, а не сделки. Тонкий стакан завышает обе величины. '
        + 'Лоты ниже 25% от медианы отброшены как приманки (1 exalted за предмет в 100 div - обычное дело на трейде).',
    };
  }

  // kind === 'rare'
  const { filters, resolved } = await trade.buildStatFilters(preset.stats || []);
  const unresolved = resolved.filter((r) => !r.resolvedId);
  const types = preset.types && preset.types.length ? preset.types : [null];
  const rows = [];

  for (const type of types) {
    const body = trade.buildQuery({ type: type || undefined }, {
      priceMax: opts.priceMax,
      priceCurrency: opts.priceCurrency,
      statFilters: filters,
    });
    const attempt = await safeListingStats(
      { league, body, rates, samples: opts.samples },
      trade.searchUrl(league, body),
    );
    if (!attempt.live) {
      rows.push({
        baseType: type || '(любая база)',
        unavailable: true,
        warning: attempt.warning,
        url: attempt.url,
      });
      continue;
    }
    const live = attempt.live;
    const margin = live.medianDivine && live.minDivine
      ? (live.medianDivine - live.minDivine) / live.medianDivine
      : null;
    rows.push({
      baseType: type || '(любая база)',
      cheapestListingDivine: live.minDivine,
      medianListingDivine: live.medianDivine,
      baitListingsDropped: live.baitListings,
      listingsOnTrade: live.total,
      sampled: live.sampled,
      confidence: live.confidence,
      margin: round(margin, 4),
      verdict: verdict(margin, live.total, live.sampled),
      url: live.url,
    });
  }

  return {
    preset: { id: preset.id, title: preset.title, kind: preset.kind, why: preset.why },
    league,
    divineInChaos: rates.divineInChaos,
    statFilters: resolved,
    unresolvedStats: unresolved.map((u) => u.text),
    rows,
    caveat: 'Лоты ниже 25% от медианы отброшены как приманки (1 exalted за предмет в 100 div - обычное дело на трейде). '
      + 'Для рарок медиана лотов - прокси рыночной цены: проверяйте по конкретным модам, а не по базе.',
  };
}

/** Built search: resolved filters, clickable URL, and optionally live listings. */
async function presetSearch(opts) {
  const { preset, leagueDefault, available } = getPreset(opts.presetId);
  if (!preset) return { error: `unknown preset: ${opts.presetId}`, available };
  const league = opts.league || leagueDefault;

  if (preset.kind === 'bulk') {
    return {
      preset: preset.id,
      league,
      exchangeUrl: trade.exchangeUrl(league, preset.exchange.have, preset.exchange.want),
    };
  }

  if (preset.kind === 'unique') {
    const stats = (preset.search && preset.search.stats) || [];
    const { filters, resolved } = await trade.buildStatFilters(stats);
    const body = trade.buildQuery({ name: preset.search.name }, {
      priceMax: opts.priceMax,
      priceCurrency: opts.priceCurrency,
      statFilters: filters,
    });
    const out = { preset: preset.id, league, statFilters: resolved, url: trade.searchUrl(league, body) };
    if (opts.includeLive) {
      const rates = await scout.ratesFor(league);
      const attempt = await safeListingStats({ league, body, rates, samples: opts.samples }, out.url);
      if (attempt.live) out.live = attempt.live;
      else out.warning = attempt.warning;
    }
    return out;
  }

  const { filters, resolved } = await trade.buildStatFilters(preset.stats || []);
  const out = {
    preset: preset.id,
    league,
    statFilters: resolved,
    searches: [],
  };
  for (const type of (preset.types && preset.types.length ? preset.types : [null])) {
    const body = trade.buildQuery({ type: type || undefined }, {
      priceMax: opts.priceMax,
      priceCurrency: opts.priceCurrency,
      statFilters: filters,
    });
    const entry = { baseType: type || '(любая база)', url: trade.searchUrl(league, body) };
    if (opts.includeLive) {
      const rates = await scout.ratesFor(league);
      const attempt = await safeListingStats({ league, body, rates, samples: opts.samples }, entry.url);
      if (attempt.live) entry.live = attempt.live;
      else entry.warning = attempt.warning;
    }
    out.searches.push(entry);
  }
  return out;
}

module.exports = {
  flipReport, presetSearch, listingStats, safeListingStats, median, verdict, looksLikeBaitCluster,
  variantKey, variantStats, looksLikeUniformWall,
};
