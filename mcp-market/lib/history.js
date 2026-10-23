/*
 * PoE2 Market MCP : lib/history.js
 *
 * Своя история рынка. poe2scout отдаёт историю сделок только для части предметов
 * (у Headhunter, например, ценовые логи пустые), поэтому каждый реальный замер лотов
 * записывается сюда - и по нему уже видно, растёт цена или падает.
 *
 * Файл: .state/price-history.json. Пишется только то, что реально прочитано с рынка.
 */

'use strict';

const fs = require('fs');
const path = require('path');

const STATE_DIR = process.env.POE2_MARKET_STATE || path.join(__dirname, '..', '.state');
const FILE = path.join(STATE_DIR, 'price-history.json');
const MAX_ENTRIES = 2000;
const DEDUPE_MS = 10 * 60 * 1000;

function load() {
  try {
    const data = JSON.parse(fs.readFileSync(FILE, 'utf8'));
    return Array.isArray(data.snapshots) ? data : { snapshots: [] };
  } catch {
    return { snapshots: [] };
  }
}

function save(data) {
  try {
    fs.mkdirSync(STATE_DIR, { recursive: true });
    data.snapshots = data.snapshots.slice(-MAX_ENTRIES);
    fs.writeFileSync(FILE, JSON.stringify(data, null, 2));
  } catch {
    /* история - вспомогательные данные, не повод падать */
  }
  return data;
}

const number = (value) => (typeof value === 'number' && Number.isFinite(value) ? value : null);

function sameNumbers(a, b) {
  return a.fairDivine === b.fairDivine
    && a.minDivine === b.minDivine
    && a.medianDivine === b.medianDivine
    && a.p25 === b.p25
    && a.p75 === b.p75
    && a.lots === b.lots;
}

/**
 * Записать замер рынка. Повторные одинаковые цифры в пределах 10 минут не дублируются.
 * @returns {object|null} записанная строка (или уже существующая)
 */
function record(snapshot) {
  if (!snapshot || !snapshot.name) return null;
  const row = {
    at: new Date().toISOString(),
    league: snapshot.league || null,
    name: snapshot.name,
    fairDivine: number(snapshot.fairDivine),
    minDivine: number(snapshot.minDivine),
    medianDivine: number(snapshot.medianDivine),
    p25: number(snapshot.p25),
    p75: number(snapshot.p75),
    lots: number(snapshot.lots),
  };
  const data = load();
  const last = [...data.snapshots].reverse()
    .find((s) => s.name === row.name && s.league === row.league);
  if (last && sameNumbers(last, row) && Date.now() - Date.parse(last.at) < DEDUPE_MS) {
    return last;
  }
  data.snapshots.push(row);
  save(data);
  return row;
}

/** Замеры по предмету, от старых к новым. */
function snapshotsFor(league, name, limit = 30) {
  const wantedLeague = league || null;
  const wantedName = String(name || '').toLowerCase();
  const rows = load().snapshots.filter(
    (s) => String(s.name).toLowerCase() === wantedName && s.league === wantedLeague,
  );
  return rows.slice(-limit);
}

/** Убрать замеры предмета (для уборки тестовых записей). */
function clear(league, name) {
  const data = load();
  const wantedName = String(name || '').toLowerCase();
  const before = data.snapshots.length;
  data.snapshots = data.snapshots.filter(
    (s) => !(String(s.name).toLowerCase() === wantedName && s.league === (league || null)),
  );
  save(data);
  return before - data.snapshots.length;
}

const pct = (from, to) => (from && to ? (to - from) / from : null);

/**
 * Чистая сводка по замерам: тренд, границы, вердикт «держать или продавать».
 * @param {Array} snapshots от старых к новым
 */
function summarise(snapshots) {
  const rows = (snapshots || []).filter(Boolean);
  if (rows.length < 2) {
    return {
      count: rows.length,
      verdict: 'мало данных: нужно минимум два замера',
      note: 'замеры копятся сами: каждый скан или проверка цены добавляет точку',
    };
  }
  const first = rows[0];
  const last = rows[rows.length - 1];
  const medianDeltaPct = pct(first.medianDivine, last.medianDivine);
  const fairDeltaPct = pct(first.fairDivine, last.fairDivine);
  const medians = rows.map((s) => s.medianDivine).filter((v) => v !== null);

  let verdict = 'недостаточно данных';
  if (medianDeltaPct !== null) {
    if (Math.abs(medianDeltaPct) < 0.05) verdict = 'стабильно: держать';
    else if (medianDeltaPct > 0) verdict = 'рынок растёт: можно поднять цену';
    else verdict = 'рынок падает: не тяни с продажей';
  }

  return {
    count: rows.length,
    from: first.at,
    to: last.at,
    medianNow: last.medianDivine,
    fairNow: last.fairDivine,
    lotsNow: last.lots,
    medianDeltaPct: medianDeltaPct === null ? null : Math.round(medianDeltaPct * 10000) / 10000,
    fairDeltaPct: fairDeltaPct === null ? null : Math.round(fairDeltaPct * 10000) / 10000,
    medianMin: medians.length ? Math.min(...medians) : null,
    medianMax: medians.length ? Math.max(...medians) : null,
    verdict,
  };
}

/** Сводка по предмету: читает файл и считает. */
function trendFor(league, name, limit = 30) {
  const rows = snapshotsFor(league, name, limit);
  return { league: league || null, name, file: FILE, ...summarise(rows) };
}

module.exports = { record, snapshotsFor, summarise, trendFor, clear, FILE };
