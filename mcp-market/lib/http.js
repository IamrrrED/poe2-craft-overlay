/*
 * PoE2 Market MCP : lib/http.js
 *
 * One HTTP layer for every market source: a browser-ish User-Agent (poe2scout asks
 * for a contact UA), per-host minimum interval between calls, retry with backoff on
 * 429/5xx, and an on-disk cache so repeated questions do not hammer public APIs.
 *
 * No dependencies: global fetch (Node 18+) and node:fs only.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const CACHE_DIR = process.env.POE2_MARKET_CACHE || path.join(ROOT, '.cache');
const DEFAULT_UA = process.env.POE2_MARKET_UA
  || 'poe2-market-mcp/1.0 (local research tool; contact: set POE2_MARKET_UA)';

/** Minimum gap between two calls to the same host, milliseconds. */
const HOST_INTERVAL_MS = {
  'poe.ninja': 1500,          // documented ~12 req / 5 min on some endpoints
  'api.poe2scout.com': 1200,  // documented ~10 req / min
  'www.pathofexile.com': 2500, // trade site: be gentle, it is the one that bans
};
const lastCallAt = new Map();

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

/** Raised when a source throttles us; callers degrade instead of crashing. */
class RateLimitError extends Error {
  constructor(message, retryAfter) {
    super(message);
    this.name = 'RateLimitError';
    this.retryAfter = retryAfter || 0;
  }
}

// ── память о лимитах ────────────────────────────────────────────────────────
// Торговый сайт отдаёт 429 с окном в минуты. Без памяти о кулдауне следующая же
// попытка снова тратит запрос и снова получает 429 - вместо этого ждём молча.

const COOLDOWN_FILE = path.join(CACHE_DIR, 'cooldowns.json');
let cooldowns = null;

function loadCooldowns() {
  if (cooldowns) return cooldowns;
  cooldowns = new Map();
  try {
    const raw = JSON.parse(fs.readFileSync(COOLDOWN_FILE, 'utf8'));
    const now = Date.now();
    for (const [host, until] of Object.entries(raw.hosts || {})) {
      if (Number(until) > now) cooldowns.set(host, Number(until));
    }
  } catch {
    /* нет файла - нет кулдаунов */
  }
  return cooldowns;
}

function saveCooldowns() {
  try {
    fs.mkdirSync(CACHE_DIR, { recursive: true });
    const now = Date.now();
    const hosts = {};
    for (const [host, until] of loadCooldowns()) {
      if (until > now) hosts[host] = until;
    }
    fs.writeFileSync(COOLDOWN_FILE, JSON.stringify({ hosts }, null, 2));
  } catch {
    /* кулдаун - подсказка, а не критичные данные */
  }
}

/** Запомнить, что источник закрыт на `seconds` секунд. */
function blockHost(host, seconds) {
  const until = Date.now() + Math.max(1, Math.round(seconds)) * 1000;
  const map = loadCooldowns();
  const current = map.get(host) || 0;
  if (until > current) map.set(host, until);
  saveCooldowns();
  return Math.max(0, Math.round((map.get(host) - Date.now()) / 1000));
}

function unblockHost(host) {
  const map = loadCooldowns();
  map.delete(host);
  saveCooldowns();
}

/** Сколько секунд источник ещё закрыт (0 = можно спрашивать). */
function cooldownRemaining(host) {
  const until = loadCooldowns().get(host);
  if (!until) return 0;
  return Math.max(0, Math.round((until - Date.now()) / 1000));
}

/**
 * Ручной сброс лимитов: убирает окна кулдаунов и историю 429, из-за которой паузы выросли.
 * Бюджет запросов за час не трогаем — он и есть защита от нового зацикливания.
 */
function resetLimits() {
  const hosts = cooldownStatus().map((row) => row.host);
  for (const host of hosts) unblockHost(host);
  try {
    const budget = loadBudget();
    budget.hits429 = [];
    saveBudget(budget);
  } catch {
    // не смогли — не страшно
  }
  return { hostsCleared: hosts.length };
}

/** Человеческое «сколько ждать»: 5 мин 1 с, 45 с, 2 ч 3 мин. */function humanizeSeconds(totalSeconds) {
  const seconds = Math.max(0, Math.round(Number(totalSeconds) || 0));
  if (seconds < 60) return `${seconds} с`;
  const minutes = Math.floor(seconds / 60);
  const restSeconds = seconds % 60;
  if (minutes < 60) return restSeconds ? `${minutes} мин ${restSeconds} с` : `${minutes} мин`;
  const hours = Math.floor(minutes / 60);
  const restMinutes = minutes % 60;
  return restMinutes ? `${hours} ч ${restMinutes} мин` : `${hours} ч`;
}

/**
 * Готовый для показа ответ на вопрос «когда можно повторить»: сколько секунд осталось,
 * как это сказать словами и до какого времени.
 */
function quotaSnapshot() {
  const hosts = cooldownStatus();
  const retryInSeconds = hosts.length ? hosts[0].secondsLeft : 0;
  return {
    blocked: retryInSeconds > 0,
    retryInSeconds,
    retryInText: retryInSeconds > 0 ? humanizeSeconds(retryInSeconds) : null,
    until: hosts.length ? hosts[0].until : null,
    hosts,
    // Бюджет запросов в час: по нему видно, сколько ещё можно сделать без риска 429.
    budget: budgetStatus(),
  };
}

const BUDGET_FILE = path.join(CACHE_DIR, 'budget.json');
/** Жёсткий потолок запросов в час: без него инструмент сам себя загоняет в вечный 429.
 *  150 — это ~2,5 запроса в минуту: площадке спокойно, а проверок хватает на рабочий день. */
const MAX_REQUESTS_PER_HOUR = Number(process.env.POE2_MARKET_MAX_RPH) || 150;
const HOUR_MS = 60 * 60 * 1000;

function loadBudget(now = Date.now()) {
  try {
    const parsed = JSON.parse(fs.readFileSync(BUDGET_FILE, 'utf8'));
    return {
      requests: Array.isArray(parsed.requests) ? parsed.requests.filter((t) => now - t < HOUR_MS) : [],
      hits429: Array.isArray(parsed.hits429) ? parsed.hits429.filter((t) => now - t < HOUR_MS) : [],
    };
  } catch {
    return { requests: [], hits429: [] };
  }
}

function saveBudget(budget) {
  try {
    fs.mkdirSync(CACHE_DIR, { recursive: true });
    fs.writeFileSync(BUDGET_FILE, JSON.stringify(budget));
  } catch {
    /* бюджет не сохранился — это не повод ломать запрос */
  }
}

/**
 * Сколько ждать после 429. Каждое новое попадание в лимит в течение часа увеличивает окно:
 * площадка выдаёт новое окно сразу, если вернуться ровно к его концу, и так по кругу.
 */
function escalatedWindowSeconds(retryAfterSeconds, recentHits) {
  const base = Math.max(Number(retryAfterSeconds) || 60, 60);
  const escalations = Math.max(0, Number(recentHits) || 0);
  // Потолок 20 минут, а не час: площадка сама просит ~9,5 минут, и часовая блокировка
  // бьёт по пользователю сильнее, чем помогает.
  return Math.min(1200, Math.round(base * (1.5 ** escalations)));
}

function budgetStatus(now = Date.now()) {
  const budget = loadBudget(now);
  const oldest = budget.requests.length ? Math.min(...budget.requests) : null;
  const freeAt = oldest === null ? null : oldest + HOUR_MS;
  return {
    used: budget.requests.length,
    limit: MAX_REQUESTS_PER_HOUR,
    remaining: Math.max(0, MAX_REQUESTS_PER_HOUR - budget.requests.length),
    hits429: budget.hits429.length,
    freeInSeconds: freeAt && freeAt > now ? Math.round((freeAt - now) / 1000) : 0,
  };
}

function noteSpent(now = Date.now()) {
  const budget = loadBudget(now);
  budget.requests.push(now);
  saveBudget(budget);
  return budgetStatus(now);
}

/** Записать 429 и вернуть окно, на которое закрыт хост. */
function noteRateLimit(host, retryAfterSeconds, now = Date.now()) {
  const budget = loadBudget(now);
  budget.hits429.push(now);
  saveBudget(budget);
  const seconds = escalatedWindowSeconds(retryAfterSeconds, budget.hits429.length - 1);
  blockHost(host, seconds);
  return seconds;
}

/** Состояние всех кулдаунов: для инструмента и для честного сообщения пользователю. */
function cooldownStatus() {  const now = Date.now();
  const rows = [];
  for (const [host, until] of loadCooldowns()) {
    const secondsLeft = Math.max(0, Math.round((until - now) / 1000));
    if (secondsLeft > 0) {
      rows.push({ host, secondsLeft, until: new Date(until).toISOString() });
    }
  }
  rows.sort((a, b) => b.secondsLeft - a.secondsLeft);
  return rows;
}

function cachePath(key) {
  // The readable prefix is for humans; the hash is what makes POST search bodies
  // (which are long and share a prefix) land in different files.
  const prefix = key.replace(/[^a-z0-9._-]+/gi, '_').slice(0, 60);
  const hash = crypto.createHash('sha1').update(key).digest('hex').slice(0, 16);
  return path.join(CACHE_DIR, `${prefix}-${hash}.json`);
}

function readCache(key) {
  try {
    const raw = fs.readFileSync(cachePath(key), 'utf8');
    const entry = JSON.parse(raw);
    if (!entry || typeof entry.savedAt !== 'number') return null;
    if (Date.now() - entry.savedAt > entry.ttlMs) return null;
    return entry.value;
  } catch {
    return null;
  }
}

function writeCache(key, value, ttlMs) {
  try {
    fs.mkdirSync(CACHE_DIR, { recursive: true });
    fs.writeFileSync(cachePath(key), JSON.stringify({ savedAt: Date.now(), ttlMs, value }));
  } catch {
    /* cache is best-effort: a read-only disk must not break a query */
  }
}

async function throttle(host) {
  const gap = HOST_INTERVAL_MS[host] || 1000;
  const prev = lastCallAt.get(host) || 0;
  const wait = prev + gap - Date.now();
  if (wait > 0) await sleep(wait);
  lastCallAt.set(host, Date.now());
}

/**
 * Fetch JSON (or text) with retries. `method` defaults to GET.
 *
 * @param {string} url
 * @param {object} [options]
 * @param {string} [options.method]
 * @param {object} [options.body]      serialised as JSON
 * @param {number} [options.cacheTtlMs] 0 disables the cache
 * @param {string} [options.cacheKey]   defaults to method + url + body
 * @param {boolean} [options.text]      return the raw body instead of JSON
 */
async function fetchJson(url, options = {}) {
  const method = options.method || 'GET';
  const bodyText = options.body ? JSON.stringify(options.body) : '';
  const cacheKey = options.cacheKey || `${method} ${url} ${bodyText}`;
  const ttl = options.cacheTtlMs === undefined ? 10 * 60 * 1000 : options.cacheTtlMs;

  if (ttl > 0) {
    const hit = readCache(cacheKey);
    if (hit !== null) return hit;
  }

  const host = new URL(url).host;
  let lastError = null;

  const blocked = cooldownRemaining(host);
  if (blocked > 0) {
    throw new RateLimitError(
      `${host} в кулдауне ещё ${blocked} с: источник сам сообщил окно после 429`,
      blocked,
    );
  }

  // Бюджет: лучше честно подождать, чем получить новое окно 429 и остаться без данных надолго.
  const budget = budgetStatus();
  if (budget.remaining <= 0) {
    throw new RateLimitError(
      `бюджет запросов исчерпан: ${budget.used}/${budget.limit} за час, следующий запрос через ${humanizeSeconds(budget.freeInSeconds)}`,
      budget.freeInSeconds,
    );
  }

  for (let attempt = 0; attempt < 3; attempt += 1) {
    await throttle(host);
    try {
      const response = await fetch(url, {
        method,
        headers: {
          'User-Agent': DEFAULT_UA,
          Accept: 'application/json, text/plain, */*',
          ...(bodyText ? { 'Content-Type': 'application/json' } : {}),
          ...(options.headers || {}),
        },
        body: bodyText || undefined,
      });

      if (response.status === 429 || response.status >= 500) {
        // The trade site hands out long Retry-After windows (minutes); sleeping that
        // long in silence looks like a hang, so cap the wait and surface a typed error.
        const retryAfter = Number(response.headers.get('retry-after')) || 0;
        const waitMs = Math.min(Math.max(retryAfter * 1000, 800 * (attempt + 1) ** 2), 15000);
        const message = `${response.status} from ${host}`
          + `${retryAfter ? ` (retry-after ${retryAfter}s)` : ''}`;
        if (response.status === 429) {
          // Запоминаем окно и эскалируем паузу: возвращаться ровно к концу окна бессмысленно,
          // площадка сразу выдаёт новое, и инструмент остаётся без данных часами.
          noteRateLimit(host, retryAfter || 60);
          lastError = new RateLimitError(message, retryAfter);
        } else {
          lastError = new Error(message);
        }
        if (attempt < 2) await sleep(waitMs);
        continue;
      }
      if (!response.ok) {
        const detail = (await response.text()).slice(0, 200);
        throw new Error(`${response.status} from ${host}: ${detail}`);
      }

      const text = await response.text();
      const value = options.text ? text : JSON.parse(text);
      if (ttl > 0) writeCache(cacheKey, value, ttl);
      // Успешный запрос идёт в бюджет часа: по нему считается, сколько ещё можно.
      noteSpent();
      return value;
    } catch (error) {
      if (error && /^4\d\d from/.test(error.message)) throw error;
      lastError = error;
      await sleep(600 * (attempt + 1));
    }
  }

  throw lastError || new Error(`request failed: ${url}`);
}

module.exports = {
  fetchJson,
  sleep,
  RateLimitError,
  blockHost,
  unblockHost,
  cooldownRemaining,
  cooldownStatus,
  quotaSnapshot,
  humanizeSeconds,
  budgetStatus,
  noteSpent,
  noteRateLimit,
  escalatedWindowSeconds,
  resetLimits,
  MAX_REQUESTS_PER_HOUR,
  CACHE_DIR,
  DEFAULT_UA,
};
