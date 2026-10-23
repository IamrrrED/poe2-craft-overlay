/*
 * PoE2 Market MCP : lib/presets.js
 *
 * Presets are data (presets.json), not code: the whole point is that the user never
 * writes trade filters by hand again. A preset is either
 *   kind=unique  - a watchlist of unique items (name search + poe2scout pricing)
 *   kind=rare    - a base type plus stat specs written as plain mod text
 *   kind=bulk    - a stackable pair for the bulk item exchange
 */

'use strict';

const fs = require('fs');
const path = require('path');

const PRESETS_FILE = process.env.POE2_MARKET_PRESETS
  || path.join(__dirname, '..', 'presets.json');

function loadPresets() {
  const raw = fs.readFileSync(PRESETS_FILE, 'utf8');
  const data = JSON.parse(raw);
  const presets = (data.presets || []).map((p) => ({ ...p }));
  const ids = new Set();
  for (const preset of presets) {
    if (!preset.id) throw new Error('preset without id');
    if (ids.has(preset.id)) throw new Error(`duplicate preset id: ${preset.id}`);
    ids.add(preset.id);
  }
  return {
    file: PRESETS_FILE,
    version: data.version || 1,
    leagueDefault: data.leagueDefault || process.env.POE2_MARKET_LEAGUE || 'Forbidden Rites',
    note: data.note || '',
    presets,
  };
}

/** Short list for the `list_presets` tool: no stat internals. */
function summarize() {
  const { file, leagueDefault, presets, note } = loadPresets();
  return {
    file,
    leagueDefault,
    note,
    presets: presets.map((p) => ({
      id: p.id,
      title: p.title,
      kind: p.kind,
      why: p.why,
      items: p.kind === 'unique'
        ? (p.uniques || []).map((u) => u.name)
        : p.kind === 'bulk'
          ? [`${p.exchange.have} -> ${p.exchange.want}`]
          : (p.types || ['(любая база)']),
      stats: (p.stats || []).map((s) => `${s.text}${s.min !== undefined ? ` >= ${s.min}` : ''}`),
    })),
  };
}

function getPreset(id) {
  const { presets, leagueDefault } = loadPresets();
  const preset = presets.find((p) => p.id === id);
  if (!preset) {
    return { preset: null, leagueDefault, available: presets.map((p) => p.id) };
  }
  return { preset, leagueDefault, available: presets.map((p) => p.id) };
}

module.exports = { loadPresets, summarize, getPreset, PRESETS_FILE };
