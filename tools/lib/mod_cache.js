/*
 * PoE2 Craft Overlay : tools/lib/mod_cache.js
 *
 * A day-long cache for modifier prices.
 *
 * The trade site gives a limited number of requests per hour, and the same question ("what does this modifier
 * cost on this base?") is asked again for every item of that base. A 24 hour answer is honest here: a modifier's
 * median price does not move in an afternoon, and the panel says when a number came from the cache.
 *
 * Only successful answers are stored. A refusal (rate limit, unknown base, empty result) is exactly the thing
 * that must NOT be remembered - caching it would turn a temporary limit into a day of "no market data".
 *
 * The file lives in tools/cache/, which is not published: it is a local convenience, not data of the project.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const CACHE_DIR = path.join(__dirname, '..', 'cache');
const CACHE_FILE = path.join(CACHE_DIR, 'mod-prices.json');
const DEFAULT_TTL_SECONDS = 24 * 60 * 60;
const MAX_ENTRIES = 400;

function ttlSeconds() {
  // An unset variable must mean the default, not zero: Number('') is 0, and a zero ttl silently disables the
  // cache while looking like it is configured.
  const raw = process.env.POE2CRAFT_MOD_CACHE_TTL;
  if (raw === undefined || raw === '') {
    return DEFAULT_TTL_SECONDS;
  }
  const parsed = Number(raw);
  return Number.isFinite(parsed) && parsed >= 0 ? parsed : DEFAULT_TTL_SECONDS;
}

function keyFor(host, league, base, texts) {
  const parts = [host || 'www.pathofexile.com', league || '-', String(base || '').toLowerCase(),
    texts.map((text) => String(text || '').toLowerCase()).sort().join('|')];
  return parts.join('::');
}

function load() {
  try {
    const raw = fs.readFileSync(CACHE_FILE, 'utf8');
    const data = JSON.parse(raw);
    return data && typeof data === 'object' && data.entries ? data : { entries: {} };
  } catch (error) {
    return { entries: {} };
  }
}

function save(data) {
  try {
    fs.mkdirSync(CACHE_DIR, { recursive: true });
    const keys = Object.keys(data.entries);
    // Oldest first: a long-lived install must not grow without a bound.
    if (keys.length > MAX_ENTRIES) {
      keys.sort((left, right) => (data.entries[left].at || 0) - (data.entries[right].at || 0));
      for (const key of keys.slice(0, keys.length - MAX_ENTRIES)) {
        delete data.entries[key];
      }
    }
    fs.writeFileSync(CACHE_FILE, JSON.stringify(data));
    return true;
  } catch (error) {
    return false;
  }
}

/** A cached answer younger than the TTL, or null. */
function get(key, now) {
  const ttl = ttlSeconds();
  if (ttl <= 0) {
    return null;
  }
  const data = load();
  const entry = data.entries[key];
  if (!entry || typeof entry.at !== 'number') {
    return null;
  }
  const age = Math.floor(((now || Date.now()) / 1000) - entry.at);
  if (age < 0 || age > ttl) {
    return null;
  }
  return { payload: entry.payload, ageSeconds: age, ttlSeconds: ttl };
}

function put(key, payload, now) {
  const data = load();
  data.entries[key] = { at: Math.floor((now || Date.now()) / 1000), payload };
  save(data);
}

function clear() {
  try {
    fs.unlinkSync(CACHE_FILE);
    return true;
  } catch (error) {
    return false;
  }
}

function stats() {
  const data = load();
  const keys = Object.keys(data.entries);
  return { file: CACHE_FILE, entries: keys.length, ttlSeconds: ttlSeconds() };
}

module.exports = { keyFor, get, put, clear, stats, ttlSeconds, CACHE_FILE };

// `node tools/lib/mod_cache.js --self-test` proves the round trip without touching the trade site, so the check
// suite can run it. Uses a temporary file and restores whatever was there.
if (require.main === module && process.argv.includes('--self-test')) {
  const backup = (() => {
    try { return fs.readFileSync(CACHE_FILE, 'utf8'); } catch (error) { return null; }
  })();
  const key = keyFor('ru.pathofexile.com', 'Test League', 'Маска парии', ['#% к сопротивлению холоду']);
  put(key, { ok: true, medianChaos: 1.5 }, Date.now());
  const hit = get(key);
  const wrongLeague = get(keyFor('ru.pathofexile.com', 'Other League', 'Маска парии', ['#% к сопротивлению холоду']));
  const expired = get(key, Date.now() + (ttlSeconds() + 10) * 1000);
  const failures = [];
  if (!hit || !hit.payload || hit.payload.medianChaos !== 1.5) failures.push('round trip failed');
  if (wrongLeague !== null) failures.push('the league is not part of the key');
  if (expired !== null) failures.push('the ttl is not applied');
  clear();
  if (backup !== null) {
    try { fs.mkdirSync(CACHE_DIR, { recursive: true }); fs.writeFileSync(CACHE_FILE, backup); } catch (error) { /* ignore */ }
  }
  if (failures.length) {
    console.log('FAIL mod cache: ' + failures.join(', '));
    process.exit(1);
  }
  console.log('PASS mod cache: round trip, key by league, ttl');
}
