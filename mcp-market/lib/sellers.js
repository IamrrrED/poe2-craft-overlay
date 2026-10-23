/*
 * PoE2 Market MCP : lib/sellers.js
 *
 * Память о лотах и продавцах. Торговый сайт не говорит, что лот - приманка, но это видно
 * из наших собственных наблюдений: если дешёвый лот висит час и мы видим его в каждом скане
 * (а дешевле рынка на треть), значит его держат, а не продают. Ровно так и вышло с лотом
 * Headhunter за 50 div: продавец «в игре», лот свежий, ответа нет.
 *
 * Файл: .state/sellers.json
 */

'use strict';

const fs = require('fs');
const path = require('path');

const STATE_DIR = process.env.POE2_MARKET_STATE || path.join(__dirname, '..', '.state');
const FILE = path.join(STATE_DIR, 'sellers.json');
const MAX_LISTINGS = 3000;

function empty() {
  return { listings: {}, sellers: {} };
}

function load() {
  try {
    const data = JSON.parse(fs.readFileSync(FILE, 'utf8'));
    return {
      listings: data.listings && typeof data.listings === 'object' ? data.listings : {},
      sellers: data.sellers && typeof data.sellers === 'object' ? data.sellers : {},
    };
  } catch {
    return empty();
  }
}

function save(data) {
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true });
    const rows = Object.entries(data.listings)
      .sort((a, b) => String(b[1].lastAt).localeCompare(String(a[1].lastAt)))
      .slice(0, MAX_LISTINGS);
    data.listings = Object.fromEntries(rows);
    fs.writeFileSync(FILE, JSON.stringify(data, null, 2));
  } catch {
    /* память - вспомогательные данные */
  }
  return data;
}

const listingKey = (info) => `${info.league || ''}|${info.name}|${info.account}|${info.priceDivine}`;
const minutes = (fromMs) => Math.max(0, Math.round((Date.now() - fromMs) / 60000));

/** Отметить лот как увиденный в очередном скане. */
function noteListing(info) {
  if (!info || !info.name || !info.account) return null;
  const data = load();
  const key = listingKey(info);
  const existing = data.listings[key];
  const row = existing || {
    league: info.league || null,
    name: info.name,
    account: info.account,
    priceDivine: info.priceDivine === undefined ? null : info.priceDivine,
    firstAt: new Date().toISOString(),
    seen: 0,
  };
  row.seen += 1;
  row.lastAt = new Date().toISOString();
  data.listings[key] = row;
  save(data);
  return { ...row, minutesSeen: minutes(Date.parse(row.firstAt)) };
}

/** Что мы уже знаем про этот лот (без записи). */
function listingMemory(info) {
  if (!info || !info.name || !info.account) return null;
  const row = load().listings[listingKey(info)];
  if (!row) return { seen: 0, minutesSeen: null, firstAt: null };
  return { ...row, minutesSeen: minutes(Date.parse(row.firstAt)) };
}

/** Продавец не ответил на виспер (или наоборот - ответил). */
function noteSeller(account, patch) {
  if (!account) return null;
  const data = load();
  const row = data.sellers[account] || { noResponse: 0, answered: 0, lastAt: null, names: [] };
  if (patch && patch.noResponse) row.noResponse += 1;
  if (patch && patch.answered) row.answered += 1;
  if (patch && patch.name && !row.names.includes(patch.name)) row.names.push(patch.name);
  row.lastAt = new Date().toISOString();
  data.sellers[account] = row;
  save(data);
  return row;
}

/** Доверие к продавцу: молчал ли он раньше. */
function sellerTrust(account) {
  if (!account) return { knownSilent: false, noResponse: 0, answered: 0, lastAt: null };
  const row = load().sellers[account];
  if (!row) return { knownSilent: false, noResponse: 0, answered: 0, lastAt: null };
  return {
    knownSilent: row.noResponse > 0,
    noResponse: row.noResponse,
    answered: row.answered || 0,
    lastAt: row.lastAt,
    note: row.noResponse > 0
      ? `этот продавец уже не отвечал ${row.noResponse} раз(а)`
      : null,
  };
}

/**
 * Чистая эвристика приманки: лот видим давно, много раз и он заметно дешевле рынка.
 * @param {{seen:number, minutesSeen:number|null, discountPct:number|null}} info
 */
function looksLikePriceFix(info) {
  if (!info || !info.seen || info.seen < 3) return false;
  if (info.minutesSeen === null || info.minutesSeen === undefined || info.minutesSeen < 60) return false;
  return (info.discountPct || 0) >= 0.3;
}

/** Полная картина по лоту: память + доверие к продавцу + вердикт. */
function assess(info) {
  const memory = noteListing(info);
  const trust = sellerTrust(info && info.account);
  const suspected = looksLikePriceFix({
    seen: memory ? memory.seen : 0,
    minutesSeen: memory ? memory.minutesSeen : null,
    discountPct: info ? info.discountPct : null,
  });
  return {
    timesSeen: memory ? memory.seen : 0,
    minutesSeen: memory ? memory.minutesSeen : null,
    sellerTrust: trust,
    suspectedPriceFix: suspected,
    note: suspected
      ? `видим этот лот ${memory.seen}-й раз за ${memory.minutesSeen} мин и он дешевле рынка — похоже, его держат, а не продают`
      : trust.knownSilent ? trust.note : null,
  };
}

/** Забыть продавца и все его наблюдения (уборка тестовых записей). */
function forget(account) {
  if (!account) return 0;
  const data = load();
  const had = Boolean(data.sellers[account]);
  delete data.sellers[account];
  // Наблюдения за лотами этого продавца тоже уходят, иначе счётчик «видели N раз» не сбросить.
  for (const [key, row] of Object.entries(data.listings)) {
    if (row && row.account === account) delete data.listings[key];
  }
  save(data);
  return had ? 1 : 0;
}

function all() {
  return load();
}

module.exports = {
  noteListing,
  listingMemory,
  noteSeller,
  sellerTrust,
  looksLikePriceFix,
  assess,
  forget,
  all,
  FILE,
};
