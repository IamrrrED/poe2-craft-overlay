/*
 * PoE2 Market MCP : lib/scout.js
 *
 * poe2scout.com canonical API (https://api.poe2scout.com/openapi/v1.json):
 *   GET /Realms
 *   GET /{realm}/Leagues                        -> DivinePrice / ChaosDivinePrice per league
 *   GET /{realm}/Leagues/{league}/Uniques/ByCategory?category=&page=&perPage=&referenceCurrency=
 *   GET /{realm}/Leagues/{league}/Items/{itemId}/History?logCount=&referenceCurrency=
 *
 * The realm for Path of Exile 2 is "poe2". Unique categories: armour, weapon,
 * accessory, jewel, flask. Prices come back in the requested reference currency
 * (chaos by default; Exalted is the league's base unit, so both are kept).
 */

'use strict';

const { fetchJson } = require('./http.js');

const BASE = 'https://api.poe2scout.com';
const REALM = 'poe2';

async function realms() {
  return fetchJson(`${BASE}/Realms`, { cacheTtlMs: 24 * 60 * 60 * 1000 });
}

async function leagues() {
  return fetchJson(`${BASE}/${REALM}/Leagues`, { cacheTtlMs: 15 * 60 * 1000 });
}

/** League row: divine price in exalted, chaos per divine, default currency. */
async function leagueInfo(league) {
  const rows = await leagues();
  const wanted = String(league || '').toLowerCase();
  return (rows || []).find(
    (r) => String(r.Value).toLowerCase() === wanted || String(r.ShortName).toLowerCase() === wanted,
  ) || null;
}

/**
 * Conversion helper: everything -> divine, using the league's own numbers.
 *
 * @param {string} league
 * @returns {Promise<{league: string|null, baseCurrency: string, divineInExalted: number|null,
 *   divineInChaos: number|null, toDivine: (amount: number, currency: string) => number|null}>}
 */
async function ratesFor(league) {
  const info = await leagueInfo(league);
  const divineInExalted = info ? Number(info.DivinePrice) : null;
  const divineInChaos = info ? Number(info.ChaosDivinePrice) : null;

  return {
    league: info ? info.Value : null,
    baseCurrency: info ? info.BaseCurrencyApiId : 'exalted',
    divineInExalted,
    divineInChaos,
    toDivine(amount, currency) {
      if (amount === null || amount === undefined) return null;
      const c = String(currency || 'exalted').toLowerCase();
      if (c === 'divine') return amount;
      if (c === 'exalted' && divineInExalted) return amount / divineInExalted;
      if (c === 'chaos' && divineInChaos) return amount / divineInChaos;
      return null;
    },
  };
}

/** poe2scout only accepts 7 or 8 data points; anything else is a 400. */
function safeDataPoints(value) {
  const n = Number(value);
  return n === 8 ? 8 : 7;
}

/**
 * One page of uniques for a category.
 * @param {object} opts
 * @param {string} opts.league
 * @param {string} opts.category accessory|armour|weapon|jewel|flask
 * @param {number} [opts.page]
 * @param {number} [opts.perPage] max 250
 * @param {string} [opts.referenceCurrency] chaos|exalted|divine
 * @param {number} [opts.dataPoints] 7 or 8 (API constraint, other values are clamped)
 */
async function uniquesPage(opts) {
  const params = new URLSearchParams({
    category: opts.category,
    page: String(opts.page || 1),
    perPage: String(Math.min(opts.perPage || 250, 250)),
    referenceCurrency: opts.referenceCurrency || 'chaos',
    dataPoints: String(safeDataPoints(opts.dataPoints)),
    frequencyHours: String(opts.frequencyHours || 24),
  });
  const url = `${BASE}/${REALM}/Leagues/${encodeURIComponent(opts.league)}/Uniques/ByCategory?${params}`;
  return fetchJson(url, { cacheTtlMs: 10 * 60 * 1000 });
}

/** Every page of a category, flattened (scout ships 80-120 uniques per category). */
async function allUniques(opts) {
  const first = await uniquesPage({ ...opts, page: 1 });
  const items = [...(first.Items || [])];
  for (let page = 2; page <= (first.Pages || 1); page += 1) {
    const next = await uniquesPage({ ...opts, page });
    items.push(...(next.Items || []));
  }
  return items;
}

/** Latest traded quantity out of the price log (0 when the log is empty). */
function latestQuantity(item) {
  const logs = (item && item.PriceLogs) || [];
  for (let i = logs.length - 1; i >= 0; i -= 1) {
    const log = logs[i];
    if (log && log.Quantity) return log.Quantity;
  }
  return 0;
}

/** 7d change in percent from the price log, or null when there is not enough data. */
function change7d(item) {
  const logs = ((item && item.PriceLogs) || []).filter((l) => l && typeof l.Price === 'number');
  if (logs.length < 2) return null;
  const first = logs[0].Price;
  const last = logs[logs.length - 1].Price;
  if (!first) return null;
  return ((last - first) / first) * 100;
}

/**
 * Uniques ranked by price and liquidity — the demand shortlist.
 * @param {object} opts league, categories[], minLots, sortBy price|lots|trend, limit
 */
async function topUniques(opts) {
  const categories = opts.categories && opts.categories.length ? opts.categories : ['accessory'];
  const rates = await ratesFor(opts.league);
  const rows = [];

  for (const category of categories) {
    const items = await allUniques({ league: opts.league, category, dataPoints: 7 });
    for (const item of items) {
      const price = item.CurrentPrice;
      if (price === null || price === undefined) continue;
      const lots = item.CurrentQuantity === null || item.CurrentQuantity === undefined
        ? latestQuantity(item)
        : item.CurrentQuantity;
      if (opts.minLots && lots < opts.minLots) continue;
      rows.push({
        name: item.Name,
        baseType: item.Type,
        category: item.CategoryApiId || category,
        priceChaos: Number(price),
        priceDivine: rates.toDivine(Number(price), 'chaos'),
        lots,
        change7d: change7d(item),
        chanceable: item.IsChanceable === true,
      });
    }
  }

  const sortBy = opts.sortBy || 'price';
  rows.sort((a, b) => {
    if (sortBy === 'lots') return b.lots - a.lots;
    if (sortBy === 'trend') return (b.change7d || -1e9) - (a.change7d || -1e9);
    return b.priceChaos - a.priceChaos;
  });

  return {
    league: rates.league || opts.league,
    divineInChaos: rates.divineInChaos,
    total: rows.length,
    rows: rows.slice(0, opts.limit || 25),
  };
}

/** Price history for one unique (by name; the API wants the numeric item id). */
async function uniqueHistory(opts) {
  const items = await allUniques({
    league: opts.league,
    category: opts.category || 'accessory',
    dataPoints: 30,
    frequencyHours: 24,
  });
  const wanted = String(opts.name || '').toLowerCase();
  const item = items.find((i) => String(i.Name).toLowerCase() === wanted)
    || items.find((i) => String(i.Name).toLowerCase().includes(wanted));

  if (!item) {
    return {
      league: opts.league,
      name: opts.name,
      found: false,
      available: items.slice(0, 40).map((i) => i.Name),
    };
  }

  const params = new URLSearchParams({
    logCount: String(opts.logCount || 30),
    referenceCurrency: opts.referenceCurrency || 'chaos',
  });
  const url = `${BASE}/${REALM}/Leagues/${encodeURIComponent(opts.league)}`
    + `/Items/${item.ItemId}/History?${params}`;
  const history = await fetchJson(url, { cacheTtlMs: 10 * 60 * 1000 }).catch(() => null);

  const logs = (item.PriceLogs || []).filter(Boolean).map((l) => ({
    time: l.Time,
    price: l.Price,
    quantity: l.Quantity,
  }));

  return {
    league: opts.league,
    name: item.Name,
    baseType: item.Type,
    itemId: item.ItemId,
    found: true,
    priceChaos: item.CurrentPrice,
    lots: item.CurrentQuantity,
    change7d: change7d(item),
    logs,
    // poe2scout returns empty price logs for many items; say it instead of looking broken.
    logsNote: logs.length
      ? null
      : 'poe2scout не отдал историю сделок по этому предмету: ориентируйтесь на цену и диапазон живых лотов',
    itemHistory: history,
  };
}

module.exports = {
  realms,
  leagues,
  leagueInfo,
  ratesFor,
  uniquesPage,
  allUniques,
  topUniques,
  uniqueHistory,
  change7d,
  latestQuantity,
  safeDataPoints,
  REALM,
};
