/*
 * PoE2 Craft Overlay : tools/market_price.js
 *
 * Prices a RARE by "same base + same modifiers", for the craft-vs-buy comparison.
 *
 * The Lua engine parses the item and hands over a spec, because parsing in two languages is how the two sides
 * drift apart. This script only does the market half:
 *
 *   1. resolve each modifier to a trade stat id          (mcp-market/lib/trade.js)
 *   2. search that base with those stat filters           (same)
 *   3. read priced listings, convert each to chaos        (poe.ninja exchange rates)
 *   4. return the MEDIAN, not the minimum
 *
 * Why the median: the cheapest listings of any search are junk - a base with two matching stats and nothing
 * else, listed for one transmute. A minimum would tell every player their item is nearly worthless. The median
 * of what actually sells is the honest "what a comparable item costs".
 *
 * Reads the spec as JSON on stdin: { "base": "...", "mods": [{ "text": "...", "min": 80 }, ...], "league": "..." }
 * Writes JSON on stdout. Any failure is reported as { "ok": false, "reason": "..." } rather than a thrown stack,
 * because the caller is a GUI that has to show something either way.
 */

'use strict';

const path = require('path');
const MARKET = path.join(__dirname, '..', 'mcp-market');
const trade = require(path.join(MARKET, 'lib', 'trade.js'));
const ninja = require(path.join(MARKET, 'lib', 'ninja.js'));
const http = require(path.join(MARKET, 'lib', 'http.js'));

let TRADE_HOST = 'www.pathofexile.com';

/**
 * Every base type the trade site knows, lowercase -> the site's own spelling.
 *
 * The list is 3 129 names and changes rarely, so it is cached for six hours. Asking costs one request against
 * a data endpoint, which is far cheaper than a search that comes back 400 "unknown item base type" after the
 * ladder has already spent four rungs on it.
 */
async function tradeBaseTypes() {
  const data = await http.fetchJson(trade.baseUrl() + '/api/trade2/data/items', {
    cacheTtlMs: 6 * 60 * 60 * 1000,
  });
  const map = new Map();
  for (const group of (data && data.result) || []) {
    for (const entry of group.entries || []) {
      if (entry.type) map.set(String(entry.type).toLowerCase(), String(entry.type));
    }
  }
  return map;
}

/** Near matches for a base we do not recognise, so the refusal names something usable. */
function suggestBases(base, types) {
  const tokens = base.toLowerCase().split(/\s+/).filter(Boolean);
  const tail = tokens[tokens.length - 1];
  if (!tail) return [];
  const out = [];
  for (const [key, spelling] of types) {
    if (key.includes(tail) && key !== base.toLowerCase()) out.push(spelling);
    if (out.length >= 5) break;
  }
  return out;
}

/**
 * Can we ask right now, and if not, why?
 *
 * The market library already keeps the budget and the cooldowns on disk, and every request through it is
 * counted. The point of asking FIRST is that a request made during a cooldown is a wasted request: it will be
 * refused and it still costs budget. The caller gets a countdown instead of a failure.
 */
function quotaGate() {
  const cooldown = http.cooldownRemaining(TRADE_HOST);
  const budget = http.budgetStatus();
  if (cooldown > 0) {
    return {
      ok: false,
      reason: 'trade site is on cooldown',
      cooldownSeconds: cooldown,
      quota: budget,
    };
  }
  if (budget.remaining <= 0) {
    return {
      ok: false,
      reason: 'the hourly request budget is spent',
      cooldownSeconds: budget.freeInSeconds,
      quota: budget,
    };
  }
  return { ok: true, quota: budget };
}

/**
 * Prices from our own snapshot, in chaos, keyed by the item's full name.
 *
 * The trade site labels listings with short ids (transmute, alch, regal) and poe.ninja's rate table carries only
 * two keys - exalted and chaos - so converting from it fails for every other currency. Our snapshot is built
 * from the same API but keeps all 409 exchange lines, and the fetch tool refreshes it, so it is the right
 * source. The file is generated, which is what makes reading it with a pattern acceptable here.
 */
function loadPricesSnapshot() {
  const file = path.join(__dirname, '..', 'src', 'Data', 'prices.lua');
  const map = new Map();
  let text;
  try {
    text = require('fs').readFileSync(file, 'utf8');
  } catch (error) {
    return map;
  }
  const pattern = /\["([^"]+)"\]\s*=\s*([0-9.]+)/g;
  let match;
  while ((match = pattern.exec(text)) !== null) {
    map.set(match[1], Number(match[2]));
  }
  return map;
}

/** The trade site's short currency ids and the names our snapshot uses. */
const TRADE_ID_NAMES = {
  transmute: 'Transmutation Orb',
  transmutation: 'Transmutation Orb',
  aug: 'Augmentation Orb',
  augmentation: 'Augmentation Orb',
  alch: 'Orb of Alchemy',
  alchemy: 'Orb of Alchemy',
  chaos: 'Chaos Orb',
  regal: 'Regal Orb',
  exalted: 'Exalted Orb',
  divine: 'Divine Orb',
  annul: 'Orb of Annulment',
  alteration: 'Orb of Alteration',
  vaal: 'Vaal Orb',
  mirro: 'Mirror of Kalandra',
  mirror: 'Mirror of Kalandra',
};

/** Chaos per unit of a currency the trade site quoted, or null when we cannot know. */
function chaosForCurrency(currency, ninjaRates, snapshot) {
  const key = String(currency || '').toLowerCase();
  if (ninjaRates.chaosPerUnit[key]) return ninjaRates.chaosPerUnit[key];
  const name = TRADE_ID_NAMES[key];
  if (name && snapshot.has(name)) return snapshot.get(name);
  // Last resort: the trade id capitalised, in case it already matches a snapshot name.
  for (const [candidate, value] of snapshot) {
    if (candidate.toLowerCase() === key) return value;
  }
  return null;
}

/** Read all of stdin. */
function readStdin() {
  return new Promise((resolve, reject) => {
    let data = '';
    process.stdin.setEncoding('utf8');
    process.stdin.on('data', (chunk) => { data += chunk; });
    process.stdin.on('end', () => resolve(data));
    process.stdin.on('error', reject);
  });
}

/**
 * Chaos per unit for every currency poe.ninja lists.
 *
 * `core.rates` is "how many of this currency per ONE primary currency", and the primary is divine. So the
 * chaos rate is likewise "chaos per divine". Converting a listed price therefore divides: chaos per unit of X
 * is (chaos per divine) / (X per divine). Getting this the other way round inflated an exalted-priced item
 * from 0.014 chaos to 70 chaos - a factor of five thousand - and it looked entirely plausible on screen, which
 * is exactly why the check against our own snapshot matters.
 */
async function chaosRates(league) {
  const response = await ninja.exchangeOverview(league, 'Currency');
  const core = (response && response.core) || {};
  const perPrimary = { ...(core.rates || {}) };
  if (core.primary) perPrimary[core.primary] = 1;
  const chaos = Number(perPrimary.chaos) || null;
  if (!chaos) return { chaosPerUnit: {}, primary: core.primary || null, chaos: null };
  const chaosPerUnit = {};
  for (const [currency, value] of Object.entries(perPrimary)) {
    const number = Number(value);
    if (number > 0) chaosPerUnit[currency] = chaos / number;
  }
  return { chaosPerUnit, primary: core.primary || null, chaos };
}

/** Median of a numeric list, or null when empty. */
function median(values) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

async function main() {
  const raw = await readStdin();
  let spec;
  try {
    spec = JSON.parse(raw || '{}');
  } catch (error) {
    console.log(JSON.stringify({ ok: false, reason: 'spec is not valid JSON' }));
    return;
  }

  // The language of the query must match the language of the HOST: a Russian item goes to
  // ru.pathofexile.com with its Russian names (that catalogue knows bases the English one lacks), and an
  // English item goes to the main site. The engine decides from the panel language.
  if (spec.tradeHost) {
    TRADE_HOST = String(spec.tradeHost).replace(/^https?:\/\//,'').replace(/\/+$/,'');
    trade.setHost(TRADE_HOST);
  }
  const base = typeof spec.base === 'string' ? spec.base.trim() : '';
  const mods = Array.isArray(spec.mods) ? spec.mods.filter((m) => m && m.text) : [];
  if (!base) {
    console.log(JSON.stringify({ ok: false, reason: 'no base name to search' }));
    return;
  }
  if (!mods.length) {
    console.log(JSON.stringify({ ok: false, reason: 'no modifiers to match' }));
    return;
  }

  // Refuse before spending a request: a call made during a cooldown is refused AND still costs budget.
  const gate = quotaGate();
  if (!gate.ok) {
    console.log(JSON.stringify(gate));
    return;
  }

  // Is this a real base? A name the trade site does not know produces a bare 400 after the whole ladder has
  // been tried, which reads as "no market data" when the truth is "that name does not exist".
  //
  // Two of our own names are legitimately not trade bases, and refusing them made price checking look broken:
  //   * a Waystone arrives as "Waystone (Tier 15)" - the site calls the base "Waystone" and the tier lives in
  //     a filter;
  //   * a Magic item prints prefix + base + suffix in ONE line, so the base arrives as "Runed Slippers of the
  //     Whelpling".
  // So the name is repaired before anyone is told it does not exist: the parenthetical tail is dropped, and
  // otherwise the longest trade base contained in the name wins.
  let baseType = base;
  let mapTier = null;
  let unverifiedBase = false;

  try {
    const types = await tradeBaseTypes();
    if (types.size > 0) {
      const tierMatch = base.match(/\(\s*(?:tier|тир)\s*(\d+)\s*\)/i);
      if (tierMatch) mapTier = Number(tierMatch[1]);
      const withoutTail = base.replace(/\s*\([^)]*\)\s*$/, '').trim();
      const found = types.get(base.toLowerCase()) || types.get(withoutTail.toLowerCase());
      if (found) {
        baseType = found;
      } else {
        // Longest name that fits inside what we have: "Runed Slippers" inside "Runed Slippers of the
        // Whelpling". Longest first, so "Rattling Sceptre" wins over "Sceptre".
        let best = null;
        const haystack = base.toLowerCase();
        for (const [key, spelling] of types) {
          if (key.length < 4 || key === haystack) continue;
          if (!haystack.includes(key)) continue;
          if (!best || key.length > best.key.length) best = { key, spelling };
        }
        if (best) {
          baseType = best.spelling;
        } else {
          // The catalogue knows no base that fits. Searching WITHOUT the base would price a different item, so
          // the search refuses instead - but it says which name it sent and what the catalogue calls the near
          // matches, because the fix is the NAME, not the price.
          // The cached catalogue did not know this name, but the SEARCH is the real authority: "Pariah Mask"
          // is absent from /data/items yet the trade search returns 20 listings for it. Refusing here made the
          // panel report "base not found" for an item the site prices happily, so a miss is only a hint now.
          baseType = base;
          unverifiedBase = true;
        }
      }
    }
  } catch (error) {
    // The list is a convenience, not a requirement: without it the search simply runs as before.
    console.error('base list unavailable:', (error && error.message) || error);
  }

  // The league list is the source of truth for the exact spelling.
  const leagues = await trade.leagues();
  const ids = (leagues && (leagues.result || leagues.leagues || leagues)) || [];
  const names = Array.isArray(ids) ? ids.map((l) => (typeof l === 'string' ? l : l.id || l.name)) : [];
  const wanted = spec.league ? String(spec.league) : '';
  const league = names.find((name) => wanted && name.toLowerCase() === wanted.toLowerCase())
    || names.find((name) => /forbidden/i.test(name))
    || names[0];
  if (!league) {
    console.log(JSON.stringify({ ok: false, reason: 'no league available from the trade site' }));
    return;
  }

  const { filters, resolved } = await trade.buildStatFilters(
    mods.map((mod) => ({ text: mod.text, min: mod.min })),
  );
  if (!filters.length) {
    console.log(JSON.stringify({
      ok: false,
      reason: 'none of the modifiers resolved to a trade stat',
      resolved,
    }));
    return;
  }

  // Exact matching finds nothing on a real item. Requiring every modifier to be at least as good as the one in
  // hand means the search only returns items strictly better than ours, and for a six-mod rare that set is
  // usually empty - the price check failed for that reason, not because the market has no data.
  //
  // So the search walks a ladder and stops at the first rung that finds something:
  //   1. every modifier, at the item's own roll
  //   2. every modifier, but only 80% of the roll
  //   3. the two strongest-looking modifiers, at 80%
  //   4. the two strongest-looking modifiers, with no minimum at all
  // The rung that answered travels back with the price, so the number is never presented as an exact match when
  // it came from a loose one.
  const strict = mods.map((mod) => ({ text: mod.text, min: mod.min }));
  const relaxed = mods.map((mod) => ({
    text: mod.text,
    min: typeof mod.min === 'number' ? Math.floor(mod.min * 0.8) : undefined,
  }));
  // One prefix and one suffix, not "the first two lines": a helmet's first two modifiers are usually both
  // prefixes, and a price built from two prefixes describes a different item.
  const oneSide = (want) => mods.find((mod) => (mod.side || '') === want);
  const prefix = oneSide('prefix');
  const suffix = oneSide('suffix');
  const topTwo = (prefix && suffix) ? [prefix, suffix] : mods.slice(0, 2);

  const relaxedOf = (list) => list.map((mod) => ({
    text: mod.text,
    min: typeof mod.min === 'number' ? Math.floor(mod.min * 0.8) : undefined,
  }));

  // The floor of each modifier's own tier, when the item text carried the roll range ("33(30-34)%"): a listing
  // at the bottom of the same tier is still the same kind of item, which a made-up "-20%" is not.
  const tierFloor = (list) => list.map((mod) => ({
    text: mod.text,
    min: typeof mod.rangeMin === 'number' ? mod.rangeMin : undefined,
  }));

  // The BASE never changes: a price for a different base is a price for a different item. What loosens is the
  // modifier set, one step at a time, and the rung that answered travels back with the number.
  const ladder = [
    { at: 'exact', label: 'все моды, не ниже текущего ролла', specs: strict },
    { at: 'tier_floor', label: 'все моды, от нижней границы тира', specs: tierFloor(mods) },
    { at: 'relaxed', label: 'все моды, допуск −20%', specs: relaxed },
    { at: 'two_relaxed', label: 'главный префикс и главный суффикс, допуск −20%', specs: relaxedOf(topTwo) },
    { at: 'two_any', label: 'главный префикс и главный суффикс, без минимума',
      specs: topTwo.map((mod) => ({ text: mod.text })) },
    { at: 'one_any', label: 'один главный мод, без минимума',
      specs: [{ text: (prefix || suffix || mods[0]).text }] },
  ];

  let found = null;
  let rung = null;
  let winningUrl = null;
  let tightestUrl = null;
  for (const attempt of ladder) {
    const built = await trade.buildStatFilters(attempt.specs);
    if (!built.filters.length) continue;
    const body = trade.buildQuery({ type: baseType }, {
      statFilters: built.filters,
      status: 'any',
      mapTier: mapTier || undefined,
    });
    let result;
    try {
      result = await trade.search({ league, body, samples: 20 });
    } catch (error) {
      // A filter the site does not know must not lose the whole price: drop the tier and try once more.
      if (!mapTier) throw error;
      console.error('tier filter rejected:', (error && error.message) || error);
      mapTier = null;
      const retry = trade.buildQuery({ type: baseType }, { statFilters: built.filters, status: 'any' });
      result = await trade.search({ league, body: retry, samples: 20 });
    }
    if (result.listings.length) {
      found = result;
      rung = attempt;
      winningUrl = trade.searchUrl(league, body);
      break;
    }
  }

  if (!found) {
    console.log(JSON.stringify({
      ok: false,
      reason: 'no listing on this base matches even the loosest filter',
      base,
      league,
      url: tightestUrl,
      resolved,
      tried: ladder.map((step) => step.at),
    }));
    return;
  }

  const rates = await chaosRates(league);
  const snapshot = loadPricesSnapshot();
  const priced = [];
  const unpriced = [];
  for (const listing of found.listings) {
    if (!listing.price) continue;
    const perUnit = chaosForCurrency(listing.price.currency, rates, snapshot);
    if (!perUnit) {
      unpriced.push(listing.price.currency);
      continue;
    }
    priced.push({
      chaos: listing.price.amount * perUnit,
      amount: listing.price.amount,
      currency: listing.price.currency,
      ilvl: listing.ilvl,
    });
  }

  if (!priced.length) {
    console.log(JSON.stringify({
      ok: false,
      reason: 'listings were found but none could be converted to chaos',
      base,
      league,
      currencies: [...new Set(unpriced)],
    }));
    return;
  }

  const values = priced.map((row) => row.chaos);
  const lowest = Math.min(...values);
  const highest = Math.max(...values);

  console.log(JSON.stringify({
    ok: true,
    base,
    league,
    total: found.total,
    sampled: found.listings.length,
    priced: priced.length,
    medianChaos: median(values),
    lowestChaos: lowest,
    highestChaos: highest,
    resolved,
    // Which rung answered. "exact" means every modifier at our own roll; anything else is looser, and the
    // caller must say so rather than present the number as an exact comparison.
    matchedAt: rung.at,
    matchedLabel: rung.label,
    // A clickable search with exactly the filters that produced this number, so the player can check it.
    url: winningUrl,
    // True when the cached catalogue did not know the base and the search decided instead. and the price was built from the modifiers alone: a
    // number is then still useful, but it is not the same item's market.

    // What is left of the hourly budget, so the caller can warn before the next click is refused.
    quota: http.budgetStatus(),
    // The market library caches trade responses for two minutes, so a repeated click may not cost a request.
    cachedForSeconds: 120,
    // The raw rows travel too, so a caller can show what the number was built from instead of trusting it.
    rows: priced,
  }));
}

main().catch((error) => {
  console.log(JSON.stringify({ ok: false, reason: String((error && error.message) || error) }));
});
