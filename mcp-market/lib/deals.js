/*
 * PoE2 Market MCP : lib/deals.js
 *
 * The part that answers "что сейчас недооценено и сколько на этом заработать".
 *
 * For every candidate listing the trade site returns we need a fair value to compare
 * against. Two sources, in this order:
 *   1. poe2scout market price for the unique (impersonal, covers items not listed today);
 *   2. the median of the sampled listings themselves (rares have no market price at all).
 *
 * A listing is a deal when it is at least `threshold` below that fair value. Everything
 * below 10% of fair value is dropped as bait: those listings never sell, they only bait
 * whisper spam. Profit is computed against a realistic exit price (fair value minus 10%),
 * not against the dream price.
 *
 * Read-only, like the rest of the server. A human sends the whisper.
 */

'use strict';

const fs = require('fs');
const path = require('path');

const scout = require('./scout.js');
const trade = require('./trade.js');
const analyze = require('./analyze.js');
const history = require('./history.js');
const sellers = require('./sellers.js');
const { RateLimitError, quotaSnapshot, sleep } = require('./http.js');
const { getPreset } = require('./presets.js');

const STATE_DIR = process.env.POE2_MARKET_STATE || path.join(__dirname, '..', '.state');
const WATCH_FILE = path.join(STATE_DIR, 'watchlist.json');

const round = (value, digits = 2) => {
  if (value === null || value === undefined || Number.isNaN(value)) return null;
  const factor = 10 ** digits;
  return Math.round(value * factor) / factor;
};
const roundPrice = (value) => round(value, Math.abs(value) < 1 ? 4 : 2);

function percentile(sorted, p) {
  if (!sorted.length) return null;
  const index = Math.min(sorted.length - 1, Math.max(0, Math.round((sorted.length - 1) * p)));
  return sorted[index];
}

function minutesSince(iso) {
  if (!iso) return null;
  const at = Date.parse(iso);
  if (Number.isNaN(at)) return null;
  return Math.max(0, Math.round((Date.now() - at) / 60000));
}

/** Unique items for the categories a preset touches, with their full mod metadata. */
async function uniqueSnapshot(league, uniques) {
  const byCategory = new Map();
  for (const entry of uniques) {
    const category = entry.category || 'accessory';
    if (!byCategory.has(category)) byCategory.set(category, new Set());
    byCategory.get(category).add(entry.name);
  }

  const found = new Map();
  for (const [category, names] of byCategory) {
    const items = await scout.allUniques({ league, category, dataPoints: 7 });
    for (const item of items) {
      if (names.has(item.Name)) found.set(item.Name, item);
    }
  }
  return found;
}

/** Human-facing card: what the item is, what it does, what it costs. */
function cardFromScout(item) {
  const meta = (item && item.ItemMetadata) || {};
  return {
    name: item.Name,
    baseType: item.Type,
    itemLevel: meta.item_level || null,
    requirements: meta.requirements || null,
    implicitMods: meta.implicit_mods || [],
    explicitMods: meta.explicit_mods || [],
    flavour: meta.flavor_text ? String(meta.flavor_text).trim() : null,
    icon: item.IconUrl || meta.icon || null,
    chanceable: item.IsChanceable === true,
    marketPriceDivine: null,
    marketLots: item.CurrentQuantity,
    change7d: scout.change7d(item),
  };
}

/**
 * Choose the fair value out of the two sources.
 *
 * poe2scout occasionally carries junk prices (Ingenuity listed at 0.007 div while 266
 * live listings say otherwise). When the two disagree by more than 3x, the live market
 * wins: it is what a buyer can actually pay today.
 */
function pickFairValue(scoutDivine, listingMedian) {
  const scout = scoutDivine && scoutDivine > 0 ? scoutDivine : null;
  const median = listingMedian && listingMedian > 0 ? listingMedian : null;

  if (!scout && !median) return { fair: null, source: null };
  if (!scout) return { fair: median, source: 'median of listings' };
  if (!median) return { fair: scout, source: 'poe2scout' };

  const ratio = scout / median;
  if (ratio > 3 || ratio < 1 / 3) {
    return {
      fair: median,
      source: 'median of listings (poe2scout расходится)',
      note: `poe2scout: ${roundPrice(scout)} div, живой рынок: ${roundPrice(median)} div — беру живой рынок`,
    };
  }
  return { fair: scout, source: 'poe2scout' };
}

/**
 * Deals inside one search result.
 * @param {object} opts
 * @param {object} opts.body      trade query
 * @param {string} opts.label     what this query is (item or base type)
 * @param {number} [opts.fairDivine] fair value override (unique market price)
 */
async function dealsForQuery(opts) {
  const { league, body, rates, label } = opts;
  const samples = opts.samples || 20;
  const threshold = opts.threshold === undefined ? 0.25 : opts.threshold;
  const searchUrl = trade.searchUrl(league, body);

  let live;
  try {
    live = await analyze.listingStats({ league, body, rates, samples });
  } catch (error) {
    return { label, url: searchUrl, total: null, warning: error.message, deals: [] };
  }

  // Стена одинаковых цен: медиана по ней - не цена рынка, а цена стены. Тогда справедливую
  // берём из poe2scout (findDeals затем перезапрашивает выборку выше стены).
  const wall = live.priceStats ? live.priceStats.uniformWall : null;
  // Глубокая выборка без стены: живые данные надёжнее индекса, который может отставать вдвое
  // (Headhunter: индекс 98 div против медианы рынка ~50 при 1368 лотах).
  const deepSample = !wall && live.sampled >= 10 && live.total >= 50 && live.medianDivine;
  const indexDiverges = opts.fairDivine && live.medianDivine
    && (opts.fairDivine / live.medianDivine > 2 || opts.fairDivine / live.medianDivine < 0.5);

  let picked;
  if (wall) {
    picked = pickFairValue(opts.fairDivine, null);
  } else if (deepSample && indexDiverges) {
    picked = {
      fair: live.medianDivine,
      source: `медиана живого рынка (${live.sampled} лотов из ${live.total})`,
      note: `индекс давал ${roundPrice(opts.fairDivine)} div, живой рынок ${roundPrice(live.medianDivine)} div — беру живой`,
    };
  } else {
    picked = pickFairValue(opts.fairDivine, live.medianDivine);
  }
  const fair = picked.fair;
  const fairSource = picked.source;
  if (!fair) {
    return { label, url: searchUrl, total: live.total, sampled: live.sampled, fairDivine: null, deals: [], warning: 'нет данных для оценки' };
  }

  // Вариант предмета - отдельный рынок. Коррапченный Headhunter за 13 div и чистый за 60 div
  // не конкурируют друг с другом, поэтому и цена, и «следующий конкурент» считаются по варианту.
  const variants = live.variants || {};
  const variantName = (key) => (key === 'corrupted' ? 'corrupted' : key === 'unidentified' ? 'неопознанный' : 'чистый');
  const baitVariants = new Set(Object.entries(variants)
    .filter(([, bucket]) => bucket.baitCluster)
    .map(([key]) => key));
  const variantKeys = Object.keys(variants);
  const allVariantsBait = variantKeys.length > 0 && variantKeys.every((key) => baitVariants.has(key));

  if (allVariantsBait && !opts.forcePrices) {
    return {
      label,
      url: searchUrl,
      total: live.total,
      sampled: live.sampled,
      fairDivine: roundPrice(fair),
      fairSource,
      priceStats: live.priceStats,
      variants,
      deals: [],
      warning: 'цены недостоверны по всем вариантам: нижние лоты похожи на стену приманок '
        + `(p50 ${roundPrice(live.priceStats.p50)} div против p90 ${roundPrice(live.priceStats.p90)} div) — `
        + 'сделки по такому запросу не считаю',
    };
  }

  // Where the rest of the market sits — context for the "recommended price".
  const listingPrices = live.listings
    .map((l) => (l.price ? rates.toDivine(l.price.amount, l.price.currency) : null))
    .filter((v) => v !== null && v > 0)
    .sort((a, b) => a - b);
  const priceRange = {
    p25: roundPrice(percentile(listingPrices, 0.25)),
    p50: roundPrice(percentile(listingPrices, 0.5)),
    p75: roundPrice(percentile(listingPrices, 0.75)),
  };

  // Своя история: poe2scout не по всем предметам отдаёт логи, поэтому копим замеры сами.
  let trend = null;
  if (!label.startsWith('(')) {
    history.record({
      league,
      name: label,
      fairDivine: fair,
      minDivine: live.minDivine,
      medianDivine: live.medianDivine,
      p25: priceRange.p25,
      p75: priceRange.p75,
      lots: live.total,
    });
    trend = history.trendFor(league, label);
  }

  // Цены всех прочитанных лотов: нужен «следующий конкурент», от него считается выход.
  // Вариант хранится рядом с ценой: конкурента ищем среди своего варианта.
  const marketPrices = live.listings
    .map((l) => ({
      divine: l.price ? rates.toDivine(l.price.amount, l.price.currency) : null,
      key: `${l.account || '?'}|${l.price ? l.price.amount + l.price.currency : '?'}`,
      variant: analyze.variantKey(l),
    }))
    .filter((x) => x.divine !== null && x.divine > 0)
    .sort((a, b) => a.divine - b.divine);

  const deals = [];
  const candidates = [];
  let notCheapestSkipped = 0;
  let baitSkipped = 0;
  const minProfit = opts.minProfitDivine === undefined ? 0.1 : opts.minProfitDivine;
  for (const listing of live.listings) {
    if (!listing.price) continue;
    const price = rates.toDivine(listing.price.amount, listing.price.currency);
    if (price === null || price <= 0) continue;
    const variant = analyze.variantKey(listing);
    const bucket = variants[variant];
    if (baitVariants.has(variant) && !opts.forcePrices) {
      baitSkipped += 1;
      continue;
    }

    // Цена справедливости для этого лота: своя по варианту, если данных хватает.
    let fairForLot = fair;
    let fairForLotSource = fairSource;
    let variantNote;
    if (bucket && bucket.sample >= 5 && bucket.medianDivine) {
      fairForLot = bucket.medianDivine;
      fairForLotSource = `медиана «${variantName(variant)}» (${bucket.sample} лотов)`;
    } else if (bucket) {
      variantNote = `по варианту «${variantName(variant)}» мало данных (${bucket.sample} лот.) — сравнение по общей медиане`;
    }

    const myKey = `${listing.account || '?'}|${listing.price.amount}${listing.price.currency}`;
    const nextCompetitor = marketPrices.find((x) => x.key !== myKey && x.variant === variant);

    // Сделкой считается только лот, который дешевле всех остальных: если рядом есть такой же
    // по цене или дешевле, обходить некого. Такой лот не выбрасываем, а помечаем кандидатом:
    // в глубоком рынке он всё равно бывает интересен, но без иллюзии «мы самые дешёвые».
    let hasCompetitor = false;
    if (nextCompetitor && nextCompetitor.divine <= price) {
      notCheapestSkipped += 1;
      if (!opts.includeNotCheapest) hasCompetitor = true;
    }
    const competition = marketPrices.filter((x) => x.variant === variant && x.divine <= price).length;

    const discount = (fairForLot - price) / fairForLot;
    if (discount < threshold) continue;

    const suspicious = price < fairForLot * 0.1;
    if (suspicious && !opts.includeSuspicious) continue;

    // Exit price: 10% under fair value, so the item actually moves.
    const suggestedSell = fairForLot * 0.9;
    const profit = suggestedSell - price;
    // Percentages lie on cheap items: 654% of 0.004 div is three chaos. Money is the filter.
    if (profit < minProfit) continue;

    const ageMinutes = minutesSince(listing.indexed);
    const staleDays = ageMinutes === null ? null : Math.round(ageMinutes / 60 / 24);
    const unidentified = listing.identified === false;
    // Память о лоте и продавце: сколько раз видели и молчал ли он раньше.
    const memory = sellers.assess({
      league,
      name: label,
      account: listing.account,
      priceDivine: roundPrice(price),
      discountPct: discount,
    });
    if (unidentified && !opts.includeUnidentified) {
      // A 44% "discount" on an unid Mageblood is not a discount, it is a different item.
      continue;
    }
    // Ссылка ровно на этот лот: тот же запрос, но с зафиксированной ценой и валютой, поэтому
    // нужный лот оказывается в самом верху выдачи трейд-сайта. Дальше человек решает сам.
    let lotUrl = searchUrl;
    try {
      const pinned = JSON.parse(JSON.stringify(body));
      pinned.query.filters = pinned.query.filters || {};
      pinned.query.filters.trade_filters = pinned.query.filters.trade_filters || { filters: {} };
      pinned.query.filters.trade_filters.filters.price = {
        option: listing.price.currency,
        min: listing.price.amount,
        max: listing.price.amount,
      };
      lotUrl = trade.searchUrl(league, pinned);
    } catch {
      // не удалось собрать точную ссылку — остаётся ссылка на общий поиск
    }

    const entry = {
      id: `${label}|${price.toFixed(4)}${listing.price.currency}|${listing.account || '?'}`.slice(0, 120),
      label,
      category: opts.category || null,
      name: listing.name || label,
      baseType: listing.typeLine,
      itemLevel: listing.ilvl,
      corrupted: listing.corrupted,
      unidentified: unidentified || undefined,
      unidentifiedNote: unidentified
        ? 'предмет не опознан: его моды неизвестны, сравнивать с ценой опознанных нельзя'
        : undefined,
      mods: listing.mods,
      price: {
        amount: listing.price.amount,
        currency: listing.price.currency,
        divine: roundPrice(price),
      },
      fairValueDivine: roundPrice(fairForLot),
      fairValueSource: fairForLotSource,
      fairVariant: variant,
      fairVariantSample: bucket ? bucket.sample : 0,
      variantNote,
      suggestedSellDivine: roundPrice(suggestedSell),
      // Выход, который обгонит ближайшего конкурента: продавать дешевле него, а не «по медиане».
      undercutSellDivine: roundPrice(undercutPrice(price, nextCompetitor && nextCompetitor.divine)),
      undercutProfitDivine: undercutProfit(price, undercutPrice(price, nextCompetitor && nextCompetitor.divine)),
      nextCompetitorDivine: nextCompetitor ? roundPrice(nextCompetitor.divine) : null,
      profitDivine: roundPrice(profit),
      profitPct: round(profit / price, 4),
      discountPct: round(discount, 4),
      priceRange,
      liquidity: live.total,
      liquidityRisk: liquidityRisk(live.total),
      trend,
      sampled: live.sampled,
      listedAgoMinutes: ageMinutes,
      staleDays,
      online: listing.online === true,
      character: listing.character || null,
      sellerActivity: sellerActivity({ online: listing.online, ageMinutes }),
      timesSeen: memory.timesSeen,
      minutesSeen: memory.minutesSeen,
      sellerTrust: memory.sellerTrust,
      suspectedPriceFix: memory.suspectedPriceFix,
      memoryNote: memory.note,
      stale: staleDays !== null && staleDays >= 3
        ? `лот висит ${staleDays} дн.: дешёвая цена может означать не спрос, а отсутствие покупателей`
        : undefined,
      account: listing.account,
      whisper: listing.whisper,
      searchUrl,
      lotUrl,
      suspicious: suspicious || undefined,
      confidence: live.confidence,
      competition,
      candidate: hasCompetitor || undefined,
      // Уникал это или редкий: редкие ищутся по базе и модам, а не по сгенерированному имени.
      kind: opts.kind || null,
    };

    if (hasCompetitor) candidates.push(entry);
    else deals.push(entry);
  }

  // Money first: 0.5 div profit from a 2 div item beats 600% from a 3 exalted one.
  deals.sort((a, b) => b.profitDivine - a.profitDivine);
  candidates.sort((a, b) => b.profitDivine - a.profitDivine);
  return {
    label,
    url: searchUrl,
    total: live.total,
    sampled: live.sampled,
    fairDivine: roundPrice(fair),
    fairSource,
    fairNote: picked.note,
    priceRange,
    variants,
    wall,
    trend,
    notCheapestSkipped,
    baitSkipped,
    // Кандидаты: сильно дешевле рынка, но не единственные дешёвые. Не сделка, но заслуживают взгляда.
    candidates: candidates.slice(0, opts.perQueryLimit || 10),
    candidateCount: candidates.length,
    deals: deals.slice(0, opts.perQueryLimit || 10),
  };
}

/**
 * Медиана рынка по диапазонам цен: три запроса, каждый отдаёт только количество лотов.
 *
 * Почему так, а не по выборке: на Headhunter 1368 лотов, и «20 самых дешёвых» - это всегда
 * один кластер (19 div, затем 40, затем 48...), потому что продавцы ставят круглые цены.
 * Количества лотов по диапазонам дают настоящую форму рынка и честную медиану, причём
 * индекс poe2scout может отставать вдвое (98 div против реальных ~50).
 *
 * @param {object} opts
 * @param {number} opts.bottomDivine нижняя цена рынка (из выборки)
 */
async function locateMarketMedian(opts) {
  const bottom = opts.bottomDivine;
  if (!bottom || bottom <= 0) return null;
  const bounds = [2, 4];  // [b, 2b], [2b, 4b], [4b, ∞)
  const buckets = [];
  const edges = [1, ...bounds];
  for (let i = 0; i < edges.length; i += 1) {
    const from = roundPrice(bottom * edges[i]);
    const to = i + 1 < edges.length ? roundPrice(bottom * edges[i + 1]) : null;
    const body = trade.buildQuery(opts.preset || {}, {
      ...(opts.extra || {}),
      status: opts.status,
      priceMin: from,
      ...(to ? { priceMax: to } : {}),
    });
    const { total } = await trade.searchCount({ league: opts.league, body });
    buckets.push({ from, to, total });
  }

  const grand = buckets.reduce((sum, bucket) => sum + bucket.total, 0);
  if (!grand) return null;
  let cumulative = 0;
  let medianBucket = buckets[buckets.length - 1];
  for (const bucket of buckets) {
    cumulative += bucket.total;
    if (cumulative >= grand / 2) { medianBucket = bucket; break; }
  }
  // Медиана внутри диапазона: если он открыт сверху, берём полуторную нижнюю границу.
  const medianDivine = medianBucket.to
    ? roundPrice((medianBucket.from + medianBucket.to) / 2)
    : roundPrice(medianBucket.from * 1.5);
  return { medianDivine, total: grand, buckets };
}

/**
 * Мои лоты на площадке: поиск по аккаунту продавца (trade_filters.account).
 *
 * Зачем: игра не пишет в лог факт выставления, зато площадка знает. Если мой лот по этой цене
 * ещё есть в выдаче — он выставлен; если исчез — продан или снят. Это и есть мониторинг продажи.
 *
 * @param {object} opts
 * @param {string} opts.account аккаунт вида Имя#1234
 * @param {string} [opts.name] название предмета
 */
async function myListings(opts) {
  const league = opts.league || 'Forbidden Rites';
  const account = opts.account;
  if (!account) {
    return { error: 'нужен аккаунт продавца вида Имя#1234 — впишите его во вкладке «В работе»' };
  }
  const rates = await scout.ratesFor(league);
  const entry = {
    kind: opts.kind,
    name: opts.name,
    label: opts.label,
    baseType: opts.baseType,
    mods: opts.mods,
  };
  try {
    const found = await liveStatsFor(entry, {
      league,
      rates,
      samples: opts.samples || 20,
      cacheTtlMs: opts.cacheTtlMs,
      extra: { account, status: opts.status || 'any' },
    });
    const live = found.live;
    const prices = live.listings
      .filter((l) => l.price)
      .map((l) => ({
        amount: l.price.amount,
        currency: l.price.currency,
        // Цена всегда округляется: конвертация из хаоса даёт длинные дроби.
        divine: roundPrice(rates.toDivine(l.price.amount, l.price.currency)),
        indexed: l.indexed,
        ilvl: l.ilvl,
        // Личность предмета: нужна, чтобы добавить найденный свой лот в список работы.
        name: l.name,
        baseType: l.typeLine,
        corrupted: l.corrupted,
        identified: l.identified,
        mods: l.mods,
        // Совпал ли этот мой лот с отпечатком купленного предмета.
        sameItem: opts.fingerprint ? matchesFingerprint(l, opts.fingerprint) : undefined,
      }));
    const same = opts.fingerprint
      ? {
        checked: live.listings.filter((l) => l.price).length,
        found: prices.some((p) => p.sameItem === true),
        myPrice: (prices.find((p) => p.sameItem === true) || {}).divine || null,
      }
      : null;
    return {
      account,
      league,
      name: opts.name || null,
      onMarket: live.total > 0,
      total: live.total,
      sampled: live.sampled,
      myPrices: prices,
      cheapestOnMarket: live.minDivine,
      medianOnMarket: live.medianDivine,
      sameItem: same,
      url: live.url,
    };
  } catch (error) {
    // Ссылку собираем заново: тело запроса к этому моменту может быть не построено.
    let url = null;
    try {
      url = trade.searchUrl(league, await bodyForSpec(searchSpecFor(entry), entry, { account, status: opts.status || 'any' }));
    } catch {
      url = null;
    }
    return { error: error.message, account, url };
  }
}

/**
 * Отпечаток предмета: имя, база, ilvl, коррапт, опознан и текст модов. Цены здесь нет —
 * именно поэтому по отпечатку можно узнать «тот же самый предмет» в другой выдаче, например,
 * когда вы выставили купленную вещь на продажу под своим аккаунтом.
 */
function itemFingerprint(entry) {
  return {
    // Уникал это или редкий: определяет, как искать предмет (по имени или по базе с модами).
    kind: (entry && entry.kind) || null,
    name: entry.name || entry.label || null,
    baseType: entry.baseType || null,
    itemLevel: entry.itemLevel === undefined ? null : entry.itemLevel,
    corrupted: entry.corrupted === true,
    identified: entry.unidentified !== true && entry.identified !== false,
    mods: (entry.mods || [])
      .map((mod) => String(typeof mod === 'string' ? mod : (mod && mod.text) || '').replace(/\s+/g, ' ').trim())
      .filter(Boolean)
      .sort(),
  };
}

/** Совпадает ли лот с отпечатком: имя, база, ilvl (плюс-минус 1), коррапт и моды. */
function matchesFingerprint(listing, print) {
  if (!print || !listing) return false;
  if (print.name && listing.name && print.name.toLowerCase() !== listing.name.toLowerCase()) return false;
  if (print.baseType && listing.typeLine && print.baseType.toLowerCase() !== listing.typeLine.toLowerCase()) return false;
  if (print.itemLevel !== null && print.itemLevel !== undefined
    && listing.ilvl !== null && listing.ilvl !== undefined
    && Math.abs(Number(print.itemLevel) - Number(listing.ilvl)) > 1) return false;
  if (print.corrupted !== Boolean(listing.corrupted)) return false;
  if (!print.identified && listing.identified !== false) return false;
  const listingMods = (listing.mods || [])
    .map((mod) => String(mod).replace(/\s+/g, ' ').trim())
    .filter(Boolean)
    .sort();
  if (print.mods.length && listingMods.length && print.mods.join('|') !== listingMods.join('|')) return false;
  return true;
}

/**
 * Найти тот же предмет в текущей выдаче площадки. Нужен, чтобы понять, что лот на продаже — ваш,
 * даже если аккаунт ещё не указан (тогда это подсказка, а не факт).
 */
async function findByFingerprint(opts) {
  const league = opts.league || 'Forbidden Rites';
  const print = opts.fingerprint;
  if (!print || !print.name) return { error: 'нет отпечатка предмета' };
  const rates = await scout.ratesFor(league);
  const entry = {
    kind: print.kind || null,
    name: print.name,
    baseType: print.baseType,
    mods: print.mods,
  };
  try {
    const found = await liveStatsFor(entry, {
      league,
      rates,
      samples: opts.samples || 40,
      extra: {
        status: opts.status || 'any',
        corrupted: print.corrupted,
        ...(print.identified ? { identified: true } : {}),
      },
    });
    const live = found.live;
    const matches = live.listings
      .filter((listing) => matchesFingerprint(listing, print))
      .map((listing) => ({
        account: listing.account,
        online: listing.online,
        amount: listing.price ? listing.price.amount : null,
        currency: listing.price ? listing.price.currency : null,
        divine: listing.price ? rates.toDivine(listing.price.amount, listing.price.currency) : null,
        indexed: listing.indexed,
        ilvl: listing.ilvl,
      }));
    return {
      league,
      name: print.name,
      total: live.total,
      sampled: live.sampled,
      matches,
      mine: opts.account
        ? matches.filter((m) => String(m.account || '').toLowerCase() === String(opts.account).toLowerCase())
        : [],
      url: live.url,
    };
  } catch (error) {
    return { error: error.message, name: print.name };
  }
}

/**
 * Добавить в «В работе» все мои лоты с площадки. Это ответ на «не находит моих лотов»:
 * площадка отдаёт всё, что выставлено по аккаунту, а мы превращаем это в записи со статусом listed.
 * Повторно те же лоты не добавляются.
 *
 * @param {object} opts
 * @param {string} opts.account мой аккаунт вида Имя#1234
 * @param {string} [opts.league]
 */
async function syncMyListings(opts) {
  const account = opts.account;
  if (!account) return { error: 'нужен аккаунт продавца вида Имя#1234 — впишите его и сохраните' };
  const found = await myListings({ account, league: opts.league, samples: opts.samples || 40, status: 'any' });
  if (found.error) return { error: found.error };

  const existing = loadWatchlist().entries;
  const added = [];
  const skipped = [];
  for (const row of found.myPrices || []) {
    const name = row.name || row.baseType || 'предмет';
    const already = existing.some((entry) => entry.name === name
      && (entry.baseType || null) === (row.baseType || null)
      && Number(entry.buyPriceDivine) === Number(row.divine));
    if (already) {
      skipped.push(name);
      continue;
    }
    const record = watchAdd({
      name,
      label: row.baseType || name,
      baseType: row.baseType || null,
      itemLevel: row.ilvl || null,
      corrupted: row.corrupted === true,
      mods: row.mods || [],
      account,
      league: opts.league || null,
      status: 'listed',
      price: { amount: row.amount, currency: row.currency, divine: row.divine },
      listedAt: row.indexed || new Date().toISOString(),
      listedPriceAmount: row.amount,
      listedPriceCurrency: row.currency,
      listedPriceDivine: row.divine,      note: 'найдено на площадке по моему аккаунту',
    });
    added.push({ id: record.id, name, divine: row.divine });
  }
  return {
    account,
    found: (found.myPrices || []).length,
    total: found.total,
    added,
    skipped,
    url: found.url,
  };
}

/**
 * The main scan: walk a preset, price every candidate, return the deals.
 *
 * @param {object} opts
 * @param {string} opts.presetId
 * @param {string} [opts.league]
 * @param {number} [opts.threshold] 0.25 = ищем хотя бы на 25% ниже справедливой цены
 * @param {number} [opts.samples]   how many listings to read per query (>=5 for confidence)
 * @param {number} [opts.limit]     max deals in the answer
 * @param {number} [opts.minProfitDivine] абсолютный минимум профита (0.1 div по умолчанию):
 *        проценты на дешёвых предметах обманывают
 * @param {boolean} [opts.includeSuspicious] keep 10x-underpriced bait listings
 * @param {string} [opts.status]    торговля: securable (по умолчанию), available, onlineleague, any
 * @param {string} [opts.variant]   вариант предмета: clean (по умолчанию), corrupted, unidentified
 * @returns {Promise<object>} отчёт со сделками, карточками предметов и предупреждениями
 */
async function findDeals(opts) {
  const { preset, leagueDefault, available } = getPreset(opts.presetId);
  if (!preset) return { error: `unknown preset: ${opts.presetId}`, available };

  const league = opts.league || leagueDefault;
  const rates = await scout.ratesFor(league);
  const threshold = opts.threshold === undefined ? 0.25 : opts.threshold;
  const samples = Math.max(5, Math.min(opts.samples || 20, 50));
  const minProfitDivine = opts.minProfitDivine === undefined ? 0.1 : opts.minProfitDivine;
  // Торговля: по умолчанию только мгновенный выкуп (предмет забирается сразу, продавец не нужен).
  const status = opts.status || trade.DEFAULT_TRADE_STATUS;
  const variant = opts.variant || null;
  // Какие варианты сканировать. По умолчанию только «чистый»: дешёвая стена коррапченных
  // лотов по одной цене иначе подменяет медиану и справедливую цену (проверено на Headhunter:
  // 20 самых дешёвых с мгновенным выкупом - все corrupted по 14 div, при чистом рынке ~60-95).
  const variantsToScan = variant ? [variant] : ['clean'];
  // Порог цены в самом запросе: отсекает стену по 1 exalted. Ниже 25%, потому что дешёвый
  // вариант предмета (например коррапченный) - это законный рынок, а не приманка.
  const priceFloorPct = opts.priceFloorPct === undefined ? 0.05 : opts.priceFloorPct;

  const scanned = [];
  const deals = [];
  const candidates = [];
  const notes = [];
  let cards = {};

  // Пауза между запросами внутри одного пресета. Сборщик ставит её большой: серия запросов
  // подряд ловит 429 (проверено), а размазанные по времени проходят.
  const queryPauseMs = opts.pauseBetweenQueriesMs || 0;
  let queriesDone = 0;
  const pauseBeforeQuery = async () => {
    if (queriesDone > 0 && queryPauseMs > 0) await sleep(queryPauseMs);
    queriesDone += 1;
  };

  /**
   * Порог для повторного запроса выше стены одинаковых цен: сама стена + немного сверху,
   * но не ниже 40% справедливой цены. Иначе выборка «самые дешёвые» состоит только из стены.
   */
  const wallRetryFloor = (result, fairDivine) => {
    if (!result.wall || opts.noWallRetry) return null;
    const fromWall = result.wall.price * 1.2;
    const fromFair = fairDivine ? fairDivine * 0.4 : 0;
    const floor = Math.max(fromWall, fromFair);
    return floor > 0 ? roundPrice(floor) : null;
  };

  if (status === 'securable') {
    notes.push('торговля: только мгновенный выкуп (Instant Buyout) — виспер, пати и убежище не нужны');
  } else if (status === 'available') {
    notes.push('торговля: мгновенный выкуп и личная встреча');
  } else if (status !== 'any') {
    notes.push(`торговля: ${status} — только личная встреча, продавец должен быть в игре и ответить`);
  }
  if (variant) notes.push(`вариант предмета: ${variant}`);
  else notes.push('вариант предмета: чистый (не коррапченный и опознанный) — дешёвые коррапченные лоты '
    + 'считаются отдельным рынком и в эту выборку не попадают');

  if (preset.kind === 'unique') {
    const uniques = preset.uniques || [{ name: preset.search.name, category: 'armour' }];
    const snapshot = await uniqueSnapshot(league, uniques);
    cards = Object.fromEntries([...snapshot.entries()].map(([name, item]) => {
      const card = cardFromScout(item);
      card.marketPriceDivine = roundPrice(rates.toDivine(item.CurrentPrice, 'chaos'));
      return [name, card];
    }));

    for (const entry of uniques) {
      if (scanned.length >= (opts.maxQueries || 8)) {
        notes.push(`остановился на ${opts.maxQueries || 8} запросах, чтобы не ловить 429`);
        break;
      }
      const item = snapshot.get(entry.name);
      const fair = item ? rates.toDivine(item.CurrentPrice, 'chaos') : null;
      const stats = (preset.search && preset.search.stats) || [];
      const { filters } = await trade.buildStatFilters(stats);
      for (const scanVariant of variantsToScan) {
        if (scanned.length >= (opts.maxQueries || 8)) {
          notes.push(`остановился на ${opts.maxQueries || 8} запросах, чтобы не ловить 429`);
          break;
        }
        const label = scanVariant === 'clean' ? entry.name : `${entry.name} [${scanVariant}]`;
        const buildBody = (floor) => trade.buildQuery({ name: entry.name }, {
          priceMax: opts.priceMax,
          priceCurrency: opts.priceCurrency,
          status,
          ...variantFilters(scanVariant),
          // Нижний порог отсекает только откровенную стену по 1 exalted: у выбранного
          // варианта свой уровень цен, и низкий порог не мешает его увидеть.
          priceMin: floor || (fair ? roundPrice(fair * priceFloorPct) : undefined),
          statFilters: filters,
        });

        await pauseBeforeQuery();
        let result = await dealsForQuery({
          league, body: buildBody(null), rates, label, samples, threshold, category: entry.category,
          fairDivine: fair, includeSuspicious: opts.includeSuspicious, minProfitDivine, kind: 'unique',
        });
        scanned.push({
          ...result,
          variant: scanVariant,
          deals: undefined,
          dealCount: result.deals.length,
          marketLots: item ? item.CurrentQuantity : null,
        });
        deals.push(...result.deals);
        candidates.push(...(result.candidates || []));

        // Продавцы ставят круглые цены, поэтому «самые дешёвые» - всегда один кластер, и по нему
        // нельзя судить о рынке. Считаем настоящую медиану по количествам лотов в диапазонах цен
        // (три запроса без чтения лотов) и пересчитываем сделки уже от неё.
        const bottom = result.priceRange && result.priceRange.p25 ? result.priceRange.p25
          : (result.wall ? result.wall.price : null);
        const locate = opts.locateMedian === false || !bottom ? null : await locateMarketMedian({
          league,
          preset: { name: entry.name },
          extra: { priceCurrency: opts.priceCurrency, statFilters: filters },
          bottomDivine: bottom,
          status,
        }).catch(() => null);

        if (locate && locate.medianDivine && scanned.length < (opts.maxQueries || 8)) {
          const marketFair = locate.medianDivine;
          notes.push(`${label}: медиана живого рынка ≈ ${marketFair} div по ${locate.total} лотам `
            + `(${locate.buckets.map((b) => `${b.from}${b.to ? '-' + b.to : '+'}: ${b.total}`).join(', ')})`);
          if (fair && (fair / marketFair > 2 || fair / marketFair < 0.5)) {
            notes.push(`${label}: индекс давал ${roundPrice(fair)} div — расходится с рынком, считаю по рынку`);
          }
          const bandFloor = roundPrice(marketFair * 0.5);
          await pauseBeforeQuery();
          const band = await dealsForQuery({
            league, body: buildBody(bandFloor), rates, label, samples, threshold, category: entry.category,
            fairDivine: marketFair, includeSuspicious: opts.includeSuspicious, minProfitDivine, kind: 'unique',
          });
          scanned.push({
            ...band,
            variant: scanVariant,
            marketMedianDivine: marketFair,
            market: locate,
            floorUsed: bandFloor,
            deals: undefined,
            dealCount: band.deals.length,
            marketLots: item ? item.CurrentQuantity : null,
          });
          deals.push(...band.deals);
          candidates.push(...(band.candidates || []));
          result = band;
        }
      }
    }
  } else if (preset.kind === 'rare') {
    const { filters } = await trade.buildStatFilters(preset.stats || []);
    for (const type of (preset.types && preset.types.length ? preset.types : [null])) {
      if (scanned.length >= (opts.maxQueries || 8)) {
        notes.push(`остановился на ${opts.maxQueries || 8} запросах, чтобы не ловить 429`);
        break;
      }
      for (const scanVariant of variantsToScan) {
        if (scanned.length >= (opts.maxQueries || 8)) {
          notes.push(`остановился на ${opts.maxQueries || 8} запросах, чтобы не ловить 429`);
          break;
        }
        const baseLabel = type || '(любая база)';
        const label = scanVariant === 'clean' ? baseLabel : `${baseLabel} [${scanVariant}]`;
        const body = trade.buildQuery({ type: type || undefined }, {
          priceMax: opts.priceMax,
          priceCurrency: opts.priceCurrency,
          status,
          ...variantFilters(scanVariant),
          statFilters: filters,
        });
        await pauseBeforeQuery();
        const result = await dealsForQuery({
          league, body, rates, label, samples, threshold,
          includeSuspicious: opts.includeSuspicious, minProfitDivine, kind: 'rare',
        });
        scanned.push({ ...result, variant: scanVariant, deals: undefined, dealCount: result.deals.length });
        deals.push(...result.deals);
        candidates.push(...(result.candidates || []));

        const retryFloor = wallRetryFloor(result, null);
        if (retryFloor && scanned.length < (opts.maxQueries || 8)) {
          const retryBody = trade.buildQuery({ type: type || undefined }, {
            priceMax: opts.priceMax,
            priceCurrency: opts.priceCurrency,
            status,
            ...variantFilters(scanVariant),
            priceMin: retryFloor,
            statFilters: filters,
          });
          await pauseBeforeQuery();
          const retry = await dealsForQuery({
            league, body: retryBody, rates, label, samples, threshold,
            includeSuspicious: opts.includeSuspicious, minProfitDivine, kind: 'rare',
          });
          notes.push(`${label}: нижние лоты — стена по ${result.wall.price} div `
            + `(${Math.round(result.wall.share * 100)}% выборки), перезапросил от ${retryFloor} div`);
          scanned.push({ ...retry, variant: scanVariant, aboveWallFloor: retryFloor, deals: undefined, dealCount: retry.deals.length });
          deals.push(...retry.deals);
          candidates.push(...(retry.candidates || []));
        }
      }
    }
  } else {
    return {
      preset: { id: preset.id, title: preset.title, kind: preset.kind },
      league,
      note: 'bulk-пресет: сделки ищутся не поиском предметов, а в обмене стопками',
      exchangeUrl: trade.exchangeUrl(league, preset.exchange.have, preset.exchange.want),
    };
  }

  // Сначала лоты, которым есть кому писать, и только потом по абсолютному профиту:
  // лот за 50 div без ответа продавца стоит ноль, а свежий за 90 - реальные деньги.
  const activityRank = (deal) => {
    // Лот, который держат, и продавец, который уже молчал, стоят в конце.
    if (deal.suspectedPriceFix) return 0;
    if (deal.sellerTrust && deal.sellerTrust.knownSilent) return 1;
    const text = deal.sellerActivity || '';
    if (text.includes('писать сейчас')) return 4;
    if (text.includes('может не ответить')) return 3;
    if (deal.online) return 2;
    return 0;
  };
  deals.sort((a, b) => (activityRank(b) - activityRank(a))
    || ((b.undercutProfitDivine || b.profitDivine) - (a.undercutProfitDivine || a.profitDivine)));
  if (deals.length) {
    notes.push('сортировка: сначала лоты с активными продавцами, затем по абсолютному профиту');
  }

  // Одинаковые на вид лоты (тот же предмет, цена, ilvl и моды) схлопываем: покупателю это одна
  // и та же возможность, а список из пяти «Mageblood 250 div» читать невозможно.
  const deduped = dedupeDeals(deals);
  if (deduped.collapsed > 0) {
    notes.push(`схлопнуто одинаковых лотов: ${deduped.collapsed}`
      + ' (тот же предмет, цена и моды у других продавцов — в строке виден лучший из них)');
  }
  const dedupedCandidates = dedupeDeals(candidates);

  const quota = quotaSnapshot();
  if (quota.blocked) {
    notes.push(`трейд-сайт ограничил запросы: повторить через ${quota.retryInText}`);
  }

  return {
    preset: { id: preset.id, title: preset.title, kind: preset.kind, why: preset.why },
    league,
    threshold,
    samples,
    minProfitDivine,
    tradeStatus: status,
    variant,
    divineInChaos: rates.divineInChaos,
    cards,
    scanned,
    notes,
    quota,
    duplicatesCollapsed: deduped.collapsed,
    dealCount: deduped.deals.length,
    deals: deduped.deals.slice(0, opts.limit || 25),
    // Второй уровень: дешёвые лоты, у которых есть конкуренты по цене. Это не «сделка» —
    // обойти конкурента нельзя, — но именно из них собирается пул, когда строгих сделок нет.
    candidateCount: dedupedCandidates.deals.length,
    candidates: dedupedCandidates.deals.slice(0, opts.candidateLimit || 15),
    caveat: 'Цена справедливости - запросы продавцов, а не сделки. Профит считается к выходу по цене '
      + 'fairValue -10% и сортируется по абсолютным дивайнам, а не по процентам. Лоты дешевле 10% от '
      + 'справедливой цены отброшены как приманки, лоты с профитом ниже minProfitDivine - как мелочь, '
      + 'а лоты, которые не единственные дешёвые (включая совпадающие по цене), попадают в кандидаты.',
  };
}

/** Full card for one item, with live market numbers and (optionally) live listings. */
async function itemCard(opts) {
  const league = opts.league || 'Forbidden Rites';
  const rates = await scout.ratesFor(league);
  const category = opts.category || 'accessory';
  const snapshot = await uniqueSnapshot(league, [{ name: opts.name, category }]);
  const item = snapshot.get(opts.name);
  if (!item) {
    return {
      league,
      found: false,
      name: opts.name,
      hint: 'проверьте категорию: armour | weapon | accessory | jewel | flask',
    };
  }

  const card = cardFromScout(item);
  card.league = league;
  card.found = true;
  card.marketPriceDivine = roundPrice(rates.toDivine(item.CurrentPrice, 'chaos'));
  card.marketPriceChaos = item.CurrentPrice;
  card.priceLogs = (item.PriceLogs || []).filter(Boolean).map((l) => ({
    time: l.Time, price: l.Price, quantity: l.Quantity,
  }));

  if (opts.includeLive) {
    // Живые лоты ищем тем же способом, что и всё остальное: уник — по имени, редкий — по базе и модам.
    const entry = {
      kind: opts.kind,
      name: opts.name,
      label: opts.label,
      baseType: opts.baseType,
      mods: opts.mods,
    };
    try {
      const found = await liveStatsFor(entry, {
        league,
        rates,
        samples: opts.samples || 20,
        extra: { status: opts.status || trade.DEFAULT_TRADE_STATUS },
      });
      card.live = found.live;
      card.tradeUrl = trade.searchUrl(league, found.body);
    } catch (error) {
      card.warning = error instanceof RateLimitError
        ? `торговый сайт ограничил запросы (${error.message})`
        : error.message;
      card.tradeUrl = trade.searchUrl(league, await bodyForSpec(searchSpecFor(entry), entry, {}));
    }
  }
  return card;
}

// ── контроль цены по взятым в работу предметам ──────────────────────────────

/**
 * Что делать с предметом, который уже в работе, при таком сдвиге рынка.
 * @param {number|null} deltaPct (рынок сейчас - записанная справедливая) / записанная
 */
function sellVerdict(deltaPct) {
  if (deltaPct === null || deltaPct === undefined) return 'нет базы для сравнения';
  if (deltaPct <= -0.15) return 'рынок просел: продавай сейчас, иначе потеряешь на разнице';
  if (deltaPct >= 0.15) return 'подорожал: можно поднять цену продажи';
  return 'держи: цена стабильна';
}

/**
 * Цена, чтобы обойти ближайшего конкурента. null — если обходить некого:
 * наш лот не самый дешёвый, и продавать придётся ниже собственной закупки.
 */
function undercutPrice(price, competitorDivine) {
  if (!competitorDivine || competitorDivine <= price) return null;
  return Math.max(competitorDivine - 1, price + 0.5);
}

/**
 * Реалистичный профит: если мы самые дешёвые, цену выхода задаёт следующий конкурент,
 * а не «справедливая минус 10%» (до неё рынок может просто не дойти).
 */
function undercutProfit(price, undercutSellDivine) {
  if (!undercutSellDivine || !price) return null;
  const profit = undercutSellDivine - price;
  return profit > 0 ? Math.round(profit * 100) / 100 : null;
}

/**
 * Насколько строка перспективна как сделка: нужен, чтобы при схлопывании одинаковых
 * лотов в списке остался самый полезный продавец.
 */
function sellerScore(deal) {
  if (deal.suspectedPriceFix) return 0;
  if (deal.sellerTrust && deal.sellerTrust.knownSilent) return 1;
  const fresh = typeof deal.listedAgoMinutes === 'number' && deal.listedAgoMinutes <= 120;
  if (deal.online && fresh) return 5;
  if (deal.online) return 3;
  return 2;
}

/**
 * Схлопывает визуально одинаковые лоты: тот же предмет, цена, ilvl и те же моды.
 * Для покупателя это одна и та же возможность, поэтому в строке остаётся лучший продавец,
 * а сколько таких же предложений ещё есть — видно в sameOffers.
 *
 * @param {object[]} deals
 * @returns {{deals: object[], collapsed: number}}
 */
function dedupeDeals(deals) {
  const byKey = new Map();
  const out = [];
  for (const deal of deals) {
    const signature = (deal.mods || [])
      .map((mod) => String(mod).replace(/\s+/g, ' ').trim())
      .sort()
      .join('§');
    const key = [
      deal.label,
      deal.price.amount,
      deal.price.currency,
      deal.itemLevel === null || deal.itemLevel === undefined ? '?' : deal.itemLevel,
      signature,
    ].join('|');

    const existing = byKey.get(key);
    if (!existing) {
      deal.sameOffers = 1;
      byKey.set(key, deal);
      out.push(deal);
      continue;
    }
    existing.sameOffers += 1;
    if (sellerScore(deal) > sellerScore(existing)) {
      deal.sameOffers = existing.sameOffers;
      out[out.indexOf(existing)] = deal;
      byKey.set(key, deal);
    }
  }

  // Разные лоты с одной ценой не схлопываем (это разные роллы), но помечаем: покупателю важно
  // знать, что по этой цене есть и другие предложения, иначе строки кажутся дублями.
  const priceCounts = new Map();
  for (const deal of out) {
    const key = `${deal.label}|${deal.price.amount}|${deal.price.currency}`;
    priceCounts.set(key, (priceCounts.get(key) || 0) + 1);
  }
  for (const deal of out) {
    const key = `${deal.label}|${deal.price.amount}|${deal.price.currency}`;
    deal.samePriceOffers = priceCounts.get(key);
  }

  return { deals: out, collapsed: deals.length - out.length };
}

/**
 * Фильтры варианта предмета для запроса к трейд-сайту.
 * 'clean' = не коррапченный и опознанный, 'corrupted', 'unidentified'.
 * @param {string|null} variant
 */
function variantFilters(variant) {
  if (variant === 'clean') return { corrupted: false, identified: true };
  if (variant === 'corrupted') return { corrupted: true };
  if (variant === 'unidentified') return { identified: false };
  return {};
}

/**
 * Стоит ли вообще писать этому продавцу: свежий лот + продавец в игре.
 * Прайс-фикс выглядит именно так: лот висит, продавец молчит.
 */
function sellerActivity(opts) {
  const age = opts && opts.ageMinutes !== undefined ? opts.ageMinutes : null;
  const online = opts ? opts.online : null;
  if (online === false) return 'продавец не в сети: виспер дождётся его входа';
  if (age === null) return online ? 'продавец в игре, возраст лота неизвестен' : 'нет данных о продавце';
  if (online && age <= 120) return 'продавец в игре, лот свежий — писать сейчас (ответ не гарантирован)';
  if (online && age <= 60 * 24) return 'продавец в игре, лот не свежий — может не ответить';
  if (online) return 'продавец в игре, но лот висит больше суток — часто это прайс-фикс';
  return 'нет данных о продавце';
}

const CATEGORY_ORDER = ['accessory', 'armour', 'weapon', 'jewel', 'flask'];

/**
 * Сколько времени предмет будет продаваться: чем меньше конкурирующих предложений,
 * тем дольше висит ваша цена. Это риск, а не запрет.
 */
function liquidityRisk(liquidity) {
  if (liquidity === null || liquidity === undefined) return 'нет данных о ликвидности';
  if (liquidity < 5) return 'почти нет рынка: продажа может занять недели';
  if (liquidity < 20) return 'тонкий рынок: продажа займёт дни';
  if (liquidity < 100) return 'нормальный рынок';
  return 'густой рынок: уйдёт быстро';
}

/** poe2scout price for one unique, trying the hint category first. */
async function scoutPriceFor(league, name, hintCategory) {
  const order = hintCategory
    ? [hintCategory, ...CATEGORY_ORDER.filter((c) => c !== hintCategory)]
    : CATEGORY_ORDER;
  for (const category of order) {
    const items = await scout.allUniques({ league, category, dataPoints: 7 });
    const wanted = String(name).toLowerCase();
    const item = items.find((i) => String(i.Name).toLowerCase() === wanted);
    if (item) return { item, category };
  }
  return { item: null, category: null };
}

/**
 * Стоит ли продавать сейчас: свежий рынок против записанной справедливой цены.
 * @param {object} opts league, name, category, fairValueDivine (записанная), samples
 */
/**
 * Ошибка площадки «Unknown item name»: так она отвечает, когда уникал ищут там, где его нет.
 * На практике это значит, что предмет редкий: у рарок имя генерируется игрой, и трейд его не знает.
 */
function isUnknownItemName(error) {
  const text = String((error && error.message) || error || '');
  return /Unknown item name/i.test(text) || /"code"\s*:\s*2\b/.test(text);
}

/**
 * Как искать предмет на площадке: уникал — по имени, редкий — по базе и модам.
 * @param {object} entry запись «в работе» или лот
 */
function searchSpecFor(entry) {
  const kind = entry && (entry.kind === 'rare' || entry.rare === true) ? 'rare' : 'unique';
  if (kind === 'rare') {
    return { kind, field: 'type', value: (entry && (entry.baseType || entry.label)) || null, useMods: true };
  }
  return { kind, field: 'name', value: (entry && (entry.name || entry.label)) || null, useMods: false };
}

/** Тело запроса по спецификации поиска. */
async function bodyForSpec(spec, entry, extra) {
  const filters = spec.useMods ? (await trade.buildStatFilters((entry && entry.mods) || [])).filters : [];
  const preset = spec.field === 'type' ? { type: spec.value } : { name: spec.value };
  return trade.buildQuery(preset, { statFilters: filters, ...extra });
}

/**
 * Живые лоты по предмету с авто-исправлением: если площадка не знает имени, повторяем
 * по базе и модам. Так «Spirit Collar» (редкий амулет) перестаёт ломать проверку цен.
 */
async function liveStatsFor(entry, opts = {}) {
  const rates = opts.rates;
  const league = opts.league;
  const extra = { status: opts.status || trade.DEFAULT_TRADE_STATUS, ...(opts.extra || {}) };
  const spec = searchSpecFor(entry);
  let body = await bodyForSpec(spec, entry, extra);
  try {
    const live = await analyze.listingStats({ league, body, rates, samples: opts.samples || 20 });
    return { body, live, spec };
  } catch (error) {
    if (!isUnknownItemName(error) || spec.field === 'type') throw error;
    const fallback = { kind: 'rare', field: 'type', value: entry.baseType || entry.label || null, useMods: true };
    if (!fallback.value) {
      // Понятная ошибка вместо сырого 400 от площадки.
      throw new Error(`площадка не знает имени «${spec.value}»: похоже, предмет редкий, а для поиска нужны база и моды`);
    }
    body = await bodyForSpec(fallback, entry, extra);
    const live = await analyze.listingStats({ league, body, rates, samples: opts.samples || 20 });
    return { body, live, spec: fallback, fallbackUsed: true };
  }
}

async function priceCheck(opts) {
  const league = opts.league || 'Forbidden Rites';
  const rates = await scout.ratesFor(league);
  const { item, category } = await scoutPriceFor(league, opts.name, opts.category);
  const scoutDivine = item ? rates.toDivine(item.CurrentPrice, 'chaos') : null;

  const recorded = opts.fairValueDivine && opts.fairValueDivine > 0 ? opts.fairValueDivine : null;
  const floor = (recorded || scoutDivine) ? (recorded || scoutDivine) * 0.25 : undefined;
  const entry = {
    kind: opts.kind,
    name: opts.name,
    label: opts.label,
    baseType: opts.baseType,
    mods: opts.mods,
  };
  const url0 = trade.searchUrl(league, await bodyForSpec(searchSpecFor(entry), entry, {}));

  let live;
  let url = url0;
  try {
    const found = await liveStatsFor(entry, {
      league,
      rates,
      samples: opts.samples || 20,
      extra: { priceMin: floor ? roundPrice(floor) : undefined },
    });
    live = found.live;
    url = trade.searchUrl(league, found.body);
  } catch (error) {
    if (!(error instanceof RateLimitError)) throw error;
    return { name: opts.name, league, warning: `трейд ограничил запросы (${error.message})`, url };
  }

  const picked = pickFairValue(scoutDivine, live.medianDivine);
  const fairNow = picked.fair;
  const deltaPct = recorded && fairNow ? round((fairNow - recorded) / recorded, 4) : null;

  // Бесплатная проверка «лот ещё жив»: те же лоты, что уже прочитаны для цены.
  const compact = live.listings.map((l) => ({
    account: l.account,
    price: l.price,
    itemLevel: l.ilvl,
    corrupted: l.corrupted,
    listedAgoMinutes: minutesSince(l.indexed),
  }));
  const wanted = { account: opts.account, amount: opts.priceAmount, currency: opts.priceCurrency };
  const listingAlive = opts.account || opts.priceAmount
    ? compact.some((l) => matchesListing(l, wanted))
    : 'unknown';

  history.record({
    league,
    name: opts.name,
    fairDivine: fairNow,
    minDivine: live.minDivine,
    medianDivine: live.medianDivine,
    p25: live.priceStats ? live.priceStats.p25 : null,
    p75: live.priceStats ? live.priceStats.p75 : null,
    lots: live.total,
  });
  const trend = history.trendFor(league, opts.name);

  return {
    name: opts.name,
    category: category || opts.category || null,
    league,
    marketLots: item ? item.CurrentQuantity : null,
    scoutPriceDivine: scoutDivine ? roundPrice(scoutDivine) : null,
    liveMinDivine: live.minDivine,
    liveMedianDivine: live.medianDivine,
    listingsOnTrade: live.total,
    sampled: live.sampled,
    baitCluster: Boolean(live.priceStats && live.priceStats.baitCluster),
    fairNowDivine: fairNow ? roundPrice(fairNow) : null,
    fairSource: picked.source,
    fairNote: picked.note,
    recordedFairDivine: recorded,
    deltaPct,
    recommendedSellNowDivine: fairNow ? roundPrice(fairNow * 0.9) : null,
    verdict: live.priceStats && live.priceStats.baitCluster
      ? 'цены недостоверны: в стакане стена приманок'
      : sellVerdict(deltaPct),
    listingAlive,
    wanted,
    trend,
    url,
  };
}

/**
 * Пройтись по списку работы и сказать по каждому предмету, что с ним делать сейчас.
 * Статусы sold/skipped пропускаются: они уже закрыты.
 */
async function watchRecheck(opts = {}) {
  const league = opts.league || 'Forbidden Rites';
  const data = loadWatchlist();
  const open = data.entries.filter((e) => !['sold', 'skipped'].includes(e.status));
  const checked = [];
  const notes = [];
  const maxQueries = opts.maxQueries === undefined ? 6 : Number(opts.maxQueries);

  for (const entry of open.slice(0, maxQueries)) {
    let check;
    try {
      check = await priceCheck({
        league,
        name: entry.name,
        label: entry.label,
        baseType: entry.baseType,
        mods: entry.mods,
        kind: entry.kind,
        category: entry.category,
        fairValueDivine: entry.fairValueDivine,
        account: entry.account,
        priceAmount: entry.buyPrice ? entry.buyPrice.amount : undefined,
        priceCurrency: entry.buyPrice ? entry.buyPrice.currency : undefined,
        samples: opts.samples,
      });
    } catch (error) {
      // Один проблемный предмет не должен ломать проверку остальных.
      check = { name: entry.name, league, warning: `не удалось проверить: ${error.message}` };
      notes.push(`«${entry.name}»: ${error.message}`);
    }

    // Если предмет уже куплен или выставлен, интересно не «жив ли лот продавца» (он и должен
    // исчезнуть), а стоит ли НАШ лот на площадке. Это и есть ответ на «не находит моих лотов».
    if (opts.myAccount && ['bought', 'listed'].includes(entry.status)) {
      try {
        const mine = await myListings({
          account: opts.myAccount,
          name: entry.name,
          label: entry.label,
          baseType: entry.baseType,
          mods: entry.mods,
          kind: entry.kind,
          league,
          fingerprint: entry.fingerprint || itemFingerprint(entry),
        });
        if (mine.error) {
          check.myListing = { error: mine.error };
        } else {
          const price = (mine.myPrices || [])[0] || null;
          const undercut = price && mine.cheapestOnMarket !== null && mine.cheapestOnMarket !== undefined
            && mine.cheapestOnMarket < price.divine - 0.01;
          check.myListing = {
            onMarket: mine.onMarket,
            total: mine.total,
            amount: price ? price.amount : null,
            currency: price ? price.currency : null,
            divine: price ? price.divine : null,
            cheapestOnMarket: mine.cheapestOnMarket,
            undercut: Boolean(undercut),
            sameItem: mine.sameItem ? mine.sameItem.found : null,
          };
          const patch = {
            possiblySold: !mine.onMarket,
            listingGoneAt: mine.onMarket ? null : new Date().toISOString(),
            listedPriceDivine: price ? price.divine : null,
            marketCheapestDivine: mine.cheapestOnMarket === undefined ? null : mine.cheapestOnMarket,
            undercutAt: undercut ? new Date().toISOString() : null,
            ...(mine.sameItem ? { sameItemAt: mine.sameItem.found ? new Date().toISOString() : null, sameItemChecked: mine.sameItem.checked } : {}),
          };
          const live = data.entries.find((e) => e.id === entry.id);
          if (live) Object.assign(live, patch);
        }
      } catch (error) {
        check.myListing = { error: error.message };
      }
    }

    entry.lastCheck = { at: new Date().toISOString(), ...check };
    entry.updatedAt = entry.lastCheck.at;
    if (check.recommendedSellNowDivine) entry.targetSellNowDivine = check.recommendedSellNowDivine;
    checked.push({ id: entry.id, ...check });
  }
  if (open.length > maxQueries) {
    notes.push(`проверил ${maxQueries} из ${open.length}: трейд-сайт лимитирует частые запросы`);
  }
  saveWatchlist(data);

  return {
    league,
    checked: checked.length,
    skipped: data.entries.length - open.length,
    notes,
    rows: checked,
    caveat: 'Рекомендованная цена = справедливая сейчас −10%. Сравнение идёт с ценой, записанной при взятии в работу.',
  };
}

/**
 * Совпадает ли лот из живой выдачи с записанным (аккаунт + цена).
 * Пустое поле в записи считается совпадением: так можно искать только по аккаунту.
 */
function matchesListing(listing, wanted) {
  if (!listing || !wanted) return false;
  if (wanted.account
    && String(listing.account || '').toLowerCase() !== String(wanted.account).toLowerCase()) {
    return false;
  }
  if (wanted.amount && listing.price) {
    if (Number(listing.price.amount) !== Number(wanted.amount)) return false;
    if (wanted.currency
      && String(listing.price.currency).toLowerCase() !== String(wanted.currency).toLowerCase()) {
      return false;
    }
  }
  return true;
}

/**
 * Жив ли конкретный лот. Запрос идёт с ценовым порогом, равным цене лота, поэтому он
 * попадает в первую страницу выдачи, если всё ещё продаётся (а не утонул среди дешёвых).
 *
 * @param {object} opts league, name, account, priceAmount, priceCurrency, fairValueDivine, samples
 */
async function checkListing(opts) {
  const league = opts.league || 'Forbidden Rites';
  const rates = await scout.ratesFor(league);
  const floorDivine = opts.priceAmount && opts.priceCurrency
    ? rates.toDivine(opts.priceAmount, opts.priceCurrency)
    : (opts.fairValueDivine ? opts.fairValueDivine * 0.25 : null);
  const entry = {
    kind: opts.kind,
    name: opts.name,
    label: opts.label,
    baseType: opts.baseType,
    mods: opts.mods,
  };
  let url = trade.searchUrl(league, await bodyForSpec(searchSpecFor(entry), entry, {}));

  let live;
  try {
    const found = await liveStatsFor(entry, {
      league,
      rates,
      samples: opts.samples || 20,
      extra: {
        priceMin: floorDivine ? roundPrice(floorDivine) : undefined,
        priceCurrency: opts.priceCurrency || 'divine',
      },
    });
    live = found.live;
    url = trade.searchUrl(league, found.body);
  } catch (error) {
    if (!(error instanceof RateLimitError)) throw error;
    return {
      name: opts.name,
      league,
      alive: 'unknown',
      wanted: { account: opts.account, amount: opts.priceAmount, currency: opts.priceCurrency },
      warning: `трейд ограничил запросы (${error.message})`,
      note: 'лот не проверен: трейд-сайт ограничил запросы, повторите через пару минут',
      url,
    };
  }

  const wanted = { account: opts.account, amount: opts.priceAmount, currency: opts.priceCurrency };
  const found = live.listings.find((l) => matchesListing(l, wanted)) || null;

  return {
    name: opts.name,
    league,
    account: opts.account || null,
    wanted,
    alive: Boolean(found),
    total: live.total,
    searched: live.listings.length,
    found: found
      ? {
        price: found.price,
        itemLevel: found.ilvl,
        corrupted: found.corrupted,
        listedAgoMinutes: minutesSince(found.indexed),
        mods: found.mods,
        whisper: found.whisper,
      }
      : null,
    note: found
      ? 'лот всё ещё в продаже — можно писать продавцу'
      : 'этого лота в текущей выдаче нет: продан, снят или переставлен по другой цене',
    url,
  };
}

/**
 * Чистый фильтр «действительно можно брать»: не приманка, продавец не молчал,
 * мы самые дешёвые, профит от обхода конкурента положительный.
 */
function isActionable(deal, minProfitDivine = 1) {
  if (!deal) return false;
  if (deal.suspectedPriceFix) return false;
  if (deal.sellerTrust && deal.sellerTrust.knownSilent) return false;
  if (!deal.undercutSellDivine || !deal.undercutProfitDivine) return false;
  if (deal.undercutProfitDivine < minProfitDivine) return false;
  return true;
}

/**
 * Что стоит делать сейчас: пройти несколько пресетов и вернуть только пригодные к сделке лоты.
 * Это ответ на вопрос «есть ли вообще чем заняться», а не ещё один список всего подряд.
 *
 * @param {object} opts
 * @param {string} [opts.league]
 * @param {string[]} [opts.presets] какие пресеты смотреть (по умолчанию три ходовых)
 * @param {number} [opts.minProfitDivine] минимальный реалистичный профит для итогового списка
 * @param {number} [opts.minDealProfitDivine] порог, ниже которого лот вообще не считается сделкой
 * @param {number} [opts.maxPresets] сколько пресетов опросить за раз (по умолчанию 3)
 * @param {number} [opts.samples] сколько лотов читать на запрос
 * @param {number} [opts.threshold] минимальная скидка к справедливой цене
 * @param {number} [opts.limit] сколько вариантов вернуть
 * @returns {Promise<object>}
 */
async function bestNow(opts = {}) {
  const league = opts.league || 'Forbidden Rites';
  const presets = (opts.presets && opts.presets.length)
    ? opts.presets
    : ['meta_belts', 'liquid_cheap_uniques', 'headhunter_hunt'];
  const minProfit = opts.minProfitDivine === undefined ? 2 : opts.minProfitDivine;
  const threshold = opts.threshold === undefined ? 0.15 : opts.threshold;

  const scannedPresets = [];
  const actionable = [];
  // Считаем и то, что отсеялось ещё внутри запроса: иначе «нечего брать» выглядит беспричинно.
  const skipped = { suspectedPriceFix: 0, sellerSilent: 0, thinMargin: 0, notCheapest: 0 };

  for (const presetId of presets.slice(0, opts.maxPresets || 3)) {
    let report;
    try {
      report = await findDeals({
        presetId,
        league,
        threshold,
        samples: opts.samples || 20,
        minProfitDivine: opts.minDealProfitDivine === undefined ? 0.5 : opts.minDealProfitDivine,
        limit: 25,
        status: opts.status,
      });
    } catch (error) {
      scannedPresets.push({ preset: presetId, error: error.message });
      continue;
    }
    if (report.error) {
      scannedPresets.push({ preset: presetId, error: report.error });
      continue;
    }
    const throttled = (report.scanned || []).filter((s) => s.warning).length;
    const notCheapest = (report.scanned || []).reduce((sum, s) => sum + (s.notCheapestSkipped || 0), 0);
    skipped.notCheapest += notCheapest;
    scannedPresets.push({
      preset: presetId,
      title: report.preset.title,
      deals: report.dealCount,
      throttled,
      notCheapest,
    });
    for (const deal of report.deals) {
      if (deal.suspectedPriceFix) skipped.suspectedPriceFix += 1;
      else if (deal.sellerTrust && deal.sellerTrust.knownSilent) skipped.sellerSilent += 1;
      else if (!deal.undercutProfitDivine || deal.undercutProfitDivine < minProfit) skipped.thinMargin += 1;
      if (isActionable(deal, minProfit)) actionable.push({ preset: presetId, ...deal });
    }
  }

  actionable.sort((a, b) => b.undercutProfitDivine - a.undercutProfitDivine);
  // Один и тот же лот может прийти из двух пресетов: схлопываем и здесь, иначе «Лучшее сейчас»
  // показывает его дважды.
  const dedupedTop = dedupeDeals(actionable);
  const top = dedupedTop.deals.slice(0, opts.limit || 5);
  const allUnavailable = scannedPresets.length > 0
    && scannedPresets.every((s) => s.error || s.throttled);

  const quota = quotaSnapshot();
  return {
    league,
    presets: scannedPresets,
    minProfitDivine: minProfit,
    threshold,
    actionableCount: dedupedTop.deals.length,
    duplicatesCollapsed: dedupedTop.collapsed,
    quota,
    skipped,
    top,
    verdict: allUnavailable
      ? `данных нет: трейд-сайт в лимите`
        + (quota.blocked ? `, повторить через ${quota.retryInText}` : ', повторите через несколько минут')
      : top.length
        ? `есть ${top.length} вариант(ов): лучший — ${top[0].name} за ${top[0].price.divine} div, реалистичный профит ${top[0].undercutProfitDivine} div`
        : 'сейчас брать нечего: подходящих лотов нет (либо приманки, либо маржа ниже порога)',
    throttledNotice: allUnavailable
      ? null
      : (scannedPresets.some((s) => s.throttled) || scannedPresets.some((s) => s.error)
        ? 'часть пресетов не опрошена из-за лимита трейд-сайта — повторите позже'
        : null),
  };
}

// ── watchlist: предметы, с которыми работаем ────────────────────────────────

function loadWatchlist() {
  try {
    const raw = fs.readFileSync(WATCH_FILE, 'utf8');
    const data = JSON.parse(raw);
    return Array.isArray(data.entries) ? data : { entries: [] };
  } catch {
    return { entries: [] };
  }
}

function saveWatchlist(data) {
  fs.mkdirSync(STATE_DIR, { recursive: true });
  fs.writeFileSync(WATCH_FILE, JSON.stringify(data, null, 2));
  return data;
}

/** Add a deal (or any item snapshot) to the working list. */
function watchAdd(entry) {
  const data = loadWatchlist();
  const now = new Date().toISOString();
  const record = {
    id: `${Date.now().toString(36)}-${(entry.name || entry.label || 'item').replace(/\W+/g, '-').toLowerCase()}`,
    status: entry.status || 'watching',
    createdAt: now,
    updatedAt: now,
    name: entry.name || entry.label,
    label: entry.label || null,
    // Уникал или редкий: определяет, как искать предмет на площадке (имя против базы с модами).
    kind: entry.kind || null,
    category: entry.category || null,
    baseType: entry.baseType || null,
    itemLevel: entry.itemLevel || null,
    corrupted: entry.corrupted === true,
    mods: entry.mods || [],
    league: entry.league || null,
    buyPrice: entry.price || null,
    buyPriceDivine: entry.price ? entry.price.divine : entry.fairValueDivine || null,
    fairValueDivine: entry.fairValueDivine || null,
    suggestedSellDivine: entry.suggestedSellDivine || null,
    expectedProfitDivine: entry.profitDivine || null,
    profitPct: entry.profitPct || null,
    account: entry.account || null,
    whisper: entry.whisper || null,
    searchUrl: entry.searchUrl || null,
    note: entry.note || '',
    sellPriceDivine: null,
    // Отпечаток предмета: по нему потом видно, что на площадке выставлен тот же самый экземпляр.
    fingerprint: entry.fingerprint || itemFingerprint(entry),
  };
  data.entries.unshift(record);
  saveWatchlist(data);
  return record;
}

function watchUpdate(id, patch) {
  const data = loadWatchlist();
  const index = data.entries.findIndex((e) => e.id === id);
  if (index < 0) return { error: `unknown id: ${id}`, available: data.entries.map((e) => e.id) };
  const entry = data.entries[index];
  // Поля статуса плюс метки, которые приходят из лога игры (наблюдатель за Client.txt):
  // покупка, выставление и продажа проставляются автоматически.
  for (const key of [
    'status', 'note', 'buyPriceDivine', 'sellPriceDivine', 'fairValueDivine', 'suggestedSellDivine',
    'account', 'whisperedAt', 'replyAt', 'replyText', 'afkAt', 'hideoutAt', 'tradeConfirmedAt',
    'boughtAt', 'listedAt', 'soldAt', 'buyer', 'listedPriceAmount', 'listedPriceCurrency',
    'listedPriceDivine', 'buyPriceAmount', 'buyPriceCurrency', 'sellPriceAmount', 'sellPriceCurrency',
    // Мониторинг своих лотов: исчез с площадки, цена конкурента, метка подрезания.
    'listingGoneAt', 'possiblySold', 'marketCheapestDivine', 'undercutAt',
    // Отпечаток предмета и подтверждение «на площадке тот же самый экземпляр».
    'fingerprint', 'sameItemAt', 'sameItemChecked', 'sameItemPriceDivine',
  ]) {
    if (patch[key] !== undefined) entry[key] = patch[key];
  }
  if (entry.sellPriceDivine && entry.buyPriceDivine) {
    entry.realisedProfitDivine = round(entry.sellPriceDivine - entry.buyPriceDivine, 2);
  }
  entry.updatedAt = new Date().toISOString();
  data.entries[index] = entry;
  saveWatchlist(data);
  return entry;
}

function watchRemove(id) {
  const data = loadWatchlist();
  const before = data.entries.length;
  data.entries = data.entries.filter((e) => e.id !== id);
  saveWatchlist(data);
  return { removed: before - data.entries.length, left: data.entries.length };
}

function watchList() {
  const data = loadWatchlist();
  const byStatus = {};
  for (const entry of data.entries) {
    byStatus[entry.status] = (byStatus[entry.status] || 0) + 1;
  }
  return { file: WATCH_FILE, total: data.entries.length, byStatus, entries: data.entries };
}

module.exports = {
  findDeals,
  bestNow,
  isActionable,
  itemCard,
  priceCheck,
  checkListing,
  matchesListing,
  sellerActivity,
  sellerScore,
  dedupeDeals,
  variantFilters,
  locateMarketMedian,
  myListings,
  syncMyListings,
  itemFingerprint,
  matchesFingerprint,
  findByFingerprint,
  searchSpecFor,
  isUnknownItemName,
  liveStatsFor,
  undercutPrice,
  undercutProfit,
  watchRecheck,
  sellVerdict,
  liquidityRisk,
  watchAdd,
  watchUpdate,
  watchRemove,
  watchList,
  pickFairValue,
  WATCH_FILE,
  percentile,
  round,
};
