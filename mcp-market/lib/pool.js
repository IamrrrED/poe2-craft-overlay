/*
 * PoE2 Market : lib/pool.js
 *
 * Пул интересных лотов, собранный фоном.
 *
 * Зачем: трейд-сайт отдаёт 429 после серии запросов, и ждать в интерфейсе нельзя. Поэтому
 * собираем лоты заранее, маленькими порциями, и держим их на диске: страница открывается
 * мгновенно, потому что читает готовый пул, а не ходит в трейд.
 *
 * Здесь только хранение и арифметика (сколько запросов было, что обновлять следующим).
 * Сам цикл сбора живёт в web/collector.js.
 */

'use strict';

const fs = require('fs');
const path = require('path');

const STATE_DIR = process.env.POE2_MARKET_STATE || path.join(__dirname, '..', '.state');
const POOL_FILE = path.join(STATE_DIR, 'pool.json');
const REQUEST_WINDOW_MS = 60 * 60 * 1000;
const MAX_JOBS = 40;

/** Поля лота, которые нужны интерфейсу: пул не должен пухнуть от модов и служебных данных. */
const DEAL_FIELDS = [
  'id', 'label', 'name', 'baseType', 'itemLevel', 'corrupted', 'unidentified',
  'mods', 'price', 'fairValueDivine', 'fairValueSource', 'fairVariant', 'fairVariantSample',
  'suggestedSellDivine', 'undercutSellDivine', 'undercutProfitDivine', 'nextCompetitorDivine',
  'profitDivine', 'profitPct', 'discountPct', 'priceRange', 'liquidity', 'liquidityRisk',
  'listedAgoMinutes', 'online', 'character', 'sellerActivity', 'account', 'whisper', 'searchUrl', 'lotUrl',
  'confidence', 'sameOffers', 'samePriceOffers', 'suspectedPriceFix', 'memoryNote', 'variantNote',
  'competition', 'candidate', 'tier', 'kind',
];

function emptyPool() {
  return { version: 1, updatedAt: null, jobs: {}, requests: [] };
}

function readPool() {
  try {
    const parsed = JSON.parse(fs.readFileSync(POOL_FILE, 'utf8'));
    if (!parsed || typeof parsed !== 'object') return emptyPool();
    return {
      version: parsed.version || 1,
      updatedAt: parsed.updatedAt || null,
      jobs: parsed.jobs && typeof parsed.jobs === 'object' ? parsed.jobs : {},
      requests: Array.isArray(parsed.requests) ? parsed.requests : [],
    };
  } catch {
    return emptyPool();
  }
}

function writePool(pool) {
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true });
    fs.writeFileSync(POOL_FILE, JSON.stringify(pool, null, 2));
    return true;
  } catch {
    return false;
  }
}

/** Оставить от лота только нужное и убрать пустые поля. */
function trimDeal(deal) {
  const out = {};
  for (const field of DEAL_FIELDS) {
    const value = deal[field];
    if (value === undefined || value === null) continue;
    if (Array.isArray(value) && !value.length) continue;
    out[field] = value;
  }
  return out;
}

/** Отметка о сделанном запросе: по ней видно реальную нагрузку на трейд-сайт. */
function noteRequest(pool, at = Date.now()) {
  const requests = Array.isArray(pool.requests) ? pool.requests : [];
  requests.push(at);
  const cutoff = at - REQUEST_WINDOW_MS;
  pool.requests = requests.filter((stamp) => stamp >= cutoff);
  return pool.requests.length;
}

function requestsLastHour(pool, now = Date.now()) {
  const cutoff = now - REQUEST_WINDOW_MS;
  return (pool.requests || []).filter((stamp) => stamp >= cutoff).length;
}

/**
 * Записать результат одного прохода по пресету.
 * @param {object} pool
 * @param {object} report отчёт findDeals()
 * @param {object} [meta] { startedAt, durationMs }
 */
function recordJob(pool, report, meta = {}) {
  const presetId = report.preset && report.preset.id ? report.preset.id : (report.presetId || 'unknown');
  const now = Date.now();
  const deals = (report.deals || []).map(trimDeal);
  // Второй уровень пула: дешёвые лоты с конкурентами по цене. Строгих сделок в глубоком рынке
  // часто нет вообще, и пул из одних только сделок был бы всегда пустым.
  const candidates = (report.candidates || []).map(trimDeal);
  const items = (report.scanned || []).map((scan) => ({
    label: scan.label,
    variant: scan.variant || null,
    total: scan.total === undefined ? null : scan.total,
    sampled: scan.sampled === undefined ? null : scan.sampled,
    fairDivine: scan.fairDivine === undefined ? null : scan.fairDivine,
    fairSource: scan.fairSource || null,
    marketMedianDivine: scan.marketMedianDivine === undefined ? null : scan.marketMedianDivine,
    market: scan.market || null,
    priceRange: scan.priceRange || null,
    dealCount: scan.dealCount === undefined ? null : scan.dealCount,
    notCheapestSkipped: scan.notCheapestSkipped === undefined ? null : scan.notCheapestSkipped,
    warning: scan.warning || null,
    floorUsed: scan.floorUsed === undefined ? null : scan.floorUsed,
  }));

  pool.jobs[presetId] = {
    preset: presetId,
    title: (report.preset && report.preset.title) || presetId,
    kind: (report.preset && report.preset.kind) || null,
    why: (report.preset && report.preset.why) || null,
    league: report.league || null,
    lastRunAt: new Date(now).toISOString(),
    lastRunMs: now,
    durationMs: meta.durationMs === undefined ? null : meta.durationMs,
    status: deals.length ? 'ok' : 'empty',
    tradeStatus: report.tradeStatus || null,
    variant: report.variant || null,
    dealCount: deals.length,
    duplicatesCollapsed: report.duplicatesCollapsed || 0,
    deals,
    candidates: candidates.slice(0, 10),
    candidateCount: report.candidateCount === undefined ? candidates.length : report.candidateCount,
    items,
    notes: (report.notes || []).slice(0, 12),
    caveat: report.caveat || null,
  };

  // Jobs, которые давно не обновлялись, не держим вечно.
  const entries = Object.entries(pool.jobs).sort((a, b) => (b[1].lastRunMs || 0) - (a[1].lastRunMs || 0));
  if (entries.length > MAX_JOBS) {
    pool.jobs = Object.fromEntries(entries.slice(0, MAX_JOBS));
  }
  pool.updatedAt = new Date(now).toISOString();
  return pool.jobs[presetId];
}

function recordFailure(pool, presetId, message, meta = {}) {
  const now = Date.now();
  pool.jobs[presetId] = {
    ...(pool.jobs[presetId] || { preset: presetId }),
    preset: presetId,
    lastRunAt: new Date(now).toISOString(),
    lastRunMs: now,
    durationMs: meta.durationMs === undefined ? null : meta.durationMs,
    status: meta.throttled ? 'throttled' : 'error',
    error: message,
    deals: (pool.jobs[presetId] && pool.jobs[presetId].deals) || [],
    dealCount: (pool.jobs[presetId] && pool.jobs[presetId].dealCount) || 0,
  };
  pool.updatedAt = new Date(now).toISOString();
  return pool.jobs[presetId];
}

/**
 * Какой пресет собирать следующим: самый старый по времени сбора.
 * @param {object} pool
 * @param {string[]} presetIds порядок предпочтения (первый цикл идёт слева направо)
 */
function nextPreset(pool, presetIds) {
  let best = null;
  for (const presetId of presetIds) {
    const job = pool.jobs[presetId];
    const lastRunMs = job && job.lastRunMs ? job.lastRunMs : 0;
    if (!best || lastRunMs < best.lastRunMs) best = { presetId, lastRunMs };
  }
  return best ? best.presetId : null;
}

/** Все лоты пула одним списком: сначала сделки, потом кандидаты, внутри — по абсолютным дивайнам. */
function allDeals(pool, options = {}) {
  const includeCandidates = options.includeCandidates !== false;
  const rows = [];
  for (const job of Object.values(pool.jobs)) {
    const ageMinutes = job.lastRunMs ? Math.round((Date.now() - job.lastRunMs) / 60000) : null;
    const base = { preset: job.preset, presetTitle: job.title, collectedAt: job.lastRunAt, ageMinutes };
    for (const deal of job.deals || []) rows.push({ ...deal, ...base, tier: 'deal' });
    if (includeCandidates) {
      for (const candidate of job.candidates || []) rows.push({ ...candidate, ...base, tier: 'candidate' });
    }
  }
  const profitOf = (row) => (row.tier === 'deal' ? (row.undercutProfitDivine || row.profitDivine || 0) : (row.profitDivine || 0));
  rows.sort((a, b) => (a.tier === b.tier ? profitOf(b) - profitOf(a) : (a.tier === 'deal' ? -1 : 1)));
  return rows;
}

/** Сводка для шапки страницы. */
function summary(pool) {
  const jobs = Object.values(pool.jobs);
  const fresh = jobs.filter((job) => job.lastRunMs && Date.now() - job.lastRunMs < 30 * 60 * 1000);
  const deals = allDeals(pool, { includeCandidates: false });
  const candidates = allDeals(pool, { includeCandidates: true }).filter((row) => row.tier === 'candidate');
  return {
    jobs: jobs.length,
    freshJobs: fresh.length,
    deals: deals.length,
    candidates: candidates.length,
    updatedAt: pool.updatedAt,
    requestsLastHour: requestsLastHour(pool),
    throttled: jobs.filter((job) => job.status === 'throttled').length,
  };
}

module.exports = {
  POOL_FILE,
  STATE_DIR,
  REQUEST_WINDOW_MS,
  emptyPool,
  readPool,
  writePool,
  trimDeal,
  noteRequest,
  requestsLastHour,
  recordJob,
  recordFailure,
  nextPreset,
  allDeals,
  summary,
};
