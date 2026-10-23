/*
 * PoE2 Market MCP : lib/ninja.js
 *
 * poe.ninja public PoE2 endpoints:
 *   GET /poe2/api/data/build-index-state
 *        -> per-league class distribution of the ladder (the root cause of demand)
 *   GET /poe2/api/economy/exchange/current/overview?league=&type=
 *        -> traded lines with primaryValue (price in the primary currency) and
 *           volumePrimaryValue (turnover) for a whole category of stackables
 *
 * `type` is a category label such as Currency, Essences, Fragments, Catalysts, Omens.
 */

'use strict';

const { fetchJson } = require('./http.js');

const BASE = 'https://poe.ninja/poe2/api';

/** Ladder class distribution for every league poe.ninja tracks. */
async function buildIndexState() {
  return fetchJson(`${BASE}/data/build-index-state`, { cacheTtlMs: 30 * 60 * 1000 });
}

/**
 * One exchange category: prices + turnover for stackable items.
 *
 * The rates are a DAILY fact, not a per-query one: poe.ninja recomputes the market over the day, and pulling
 * the overview for every price check both wastes their endpoint and makes two clicks on the same item quote
 * two different numbers. So the answer is kept on disk for a day (http.js caches by URL, with the timestamp),
 * and the first request after that day refreshes it.
 *
 * @param {string} league
 * @param {string} type e.g. "Currency"
 */
async function exchangeOverview(league, type) {
  const url = `${BASE}/economy/exchange/current/overview`
    + `?league=${encodeURIComponent(league)}&type=${encodeURIComponent(type)}`;
  return fetchJson(url, { cacheTtlMs: 24 * 60 * 60 * 1000 });
}

/** Names for the ids inside an exchange response (core.items is a side table). */
function nameMap(response) {
  const map = new Map();
  for (const item of (response.core && response.core.items) || []) map.set(item.id, item.name);
  return map;
}

/** Divine/chaos/exalted conversion factors carried in every exchange response. */
function rates(response) {
  const core = response.core || {};
  const divineInPrimary = Number(core.rates && core.rates[core.primary]) || null;
  const chaosInPrimary = core.rates ? Number(core.rates.chaos) : null;
  return {
    primary: core.primary || null,
    secondary: core.secondary || null,
    // price(primary) per 1 unit, e.g. { divine: 1, exalted: 730.7, chaos: 10.1 }
    perPrimary: { ...(core.rates || {}), ...(core.primary ? { [core.primary]: 1 } : {}) },
    divineInChaos: divineInPrimary && chaosInPrimary ? divineInPrimary / chaosInPrimary : null,
  };
}

/**
 * Stackables ranked by turnover — the "what actually changes hands" list.
 * @param {string} league
 * @param {string[]} types exchange categories to merge
 * @param {{limit?:number, sortBy?:'volume'|'price', risingOnly?:boolean}} [options]
 */
async function consumableVolume(league, types, options = {}) {
  const limit = options.limit || 25;
  const sortBy = options.sortBy || 'volume';
  const rows = [];
  let conversion = null;

  for (const type of types) {
    const response = await exchangeOverview(league, type);
    if (!conversion) conversion = rates(response);
    const names = nameMap(response);
    for (const line of response.lines || []) {
      rows.push({
        id: line.id,
        name: names.get(line.id) || line.id,
        category: type,
        priceInPrimary: line.primaryValue,
        volume: line.volumePrimaryValue,
        volumeCurrency: line.maxVolumeCurrency || null,
        change7d: line.sparkline ? line.sparkline.totalChange : null,
      });
    }
  }

  if (options.risingOnly) rows.splice(0, rows.length, ...rows.filter((r) => (r.change7d || 0) > 0));
  rows.sort((a, b) => (sortBy === 'price' ? b.priceInPrimary - a.priceInPrimary : b.volume - a.volume));

  return { conversion, rows: rows.slice(0, limit) };
}

/** Ladder classes for one league, biggest share first. */
async function metaClasses(league) {
  const state = await buildIndexState();
  const wanted = String(league || '').toLowerCase();
  const entry = (state.leagueBuilds || []).find(
    (l) => String(l.leagueName).toLowerCase() === wanted
      || String(l.leagueUrl).toLowerCase() === wanted,
  );
  if (!entry) {
    return {
      league,
      total: 0,
      classes: [],
      available: (state.leagueBuilds || []).map((l) => l.leagueName),
    };
  }
  return {
    league: entry.leagueName,
    total: entry.total,
    hardcore: !!entry.hardcore,
    classes: (entry.statistics || []).map((s) => ({
      class: s.class,
      share: Number((s.percentage / 100).toFixed(4)),
      trend: s.trend,
    })),
  };
}

module.exports = { buildIndexState, exchangeOverview, consumableVolume, metaClasses, rates, nameMap };
