/*
 * PoE2 Craft Overlay : tools/calibrate_pool.js
 *
 * Ask the market what each pooled modifier is actually worth, so the ranking in the panel can be checked instead of
 * trusted.
 *
 * Reads calibration-input.json (written by the engine: base, side, modifier text, its trade template, family, our
 * score, chance, tier) and prices every row with the existing market script - one request per modifier, cached for a
 * day by tools/lib/mod_cache.js, so a second run costs nothing. Writes calibration-results.json.
 *
 * Why the trade template and not the printed text: the trade site matches stats by template ("Adds # to # Cold
 * damage to Attacks"). Sending the rolled text ("Adds (21-24) to ...") resolves to no stat at all, and the first
 * run of this script reported "no market" for every single modifier because of it.
 *
 * Usage: node tools/calibrate_pool.js [--limit N] [--host www.pathofexile.com] [--lang en]
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ROOT = path.join(__dirname, '..');
const MARKET = path.join(__dirname, 'market_price.js');
// The engine writes into its own working directory (src/), so accept either place.
const INPUT = fs.existsSync(path.join(ROOT, 'calibration-input.json'))
  ? path.join(ROOT, 'calibration-input.json')
  : path.join(ROOT, 'src', 'calibration-input.json');
const OUTPUT = path.join(path.dirname(INPUT), 'calibration-results.json');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

function priceOne(spec) {
  try {
    const output = execFileSync(process.execPath, [MARKET], {
      input: JSON.stringify(spec),
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    return JSON.parse(output);
  } catch (error) {
    return { ok: false, reason: String((error && error.message) || error) };
  }
}

async function main() {
  if (!fs.existsSync(INPUT)) {
    console.error('no calibration-input.json - run the engine dump first');
    process.exit(1);
  }
  const data = JSON.parse(fs.readFileSync(INPUT, 'utf8'));
  const rows = Array.isArray(data.rows) ? data.rows : [];
  const limit = Number(arg('limit', '0')) || rows.length;
  const host = arg('host', '');
  const lang = arg('lang', 'en');
  // The trade site refuses bursts with a 429 and a retry-after, so a calibration walks, it does not run.
  const delay = Number(arg('delay', '3000')) || 0;

  const results = [];
  for (const row of rows.slice(0, limit)) {
    const spec = {
      base: row.base,
      mods: [{ text: row.tradeText || row.text }],
      lang,
      // Each row carries the host its base is known on: a Russian base is only in the Russian catalogue.
      tradeHost: row.host || host || 'www.pathofexile.com',
    };
    if (results.length && delay > 0) {
      await new Promise((resolve) => setTimeout(resolve, delay));
    }
    const answer = priceOne(spec);
    const priced = Boolean(answer && answer.ok) && typeof answer.medianChaos === 'number';
    results.push(Object.assign({}, row, {
      ok: priced,
      medianChaos: priced ? answer.medianChaos : null,
      listings: priced ? answer.priced : 0,
      cached: Boolean(answer && answer.cached),
      reason: priced ? null : ((answer && (answer.reasonRu || answer.reason)) || 'no answer'),
    }));
    const shown = results[results.length - 1];
    console.log(
      `${shown.label} ${shown.side} ${shown.family} `
      + `${priced ? shown.medianChaos.toFixed(3) + ' chaos' : 'n/a'} `
      + `(score ${shown.score.toFixed(2)}) ${shown.text.slice(0, 52)}`
      + (priced ? '' : ' | ' + shown.reason),
    );
  }

  fs.writeFileSync(OUTPUT, JSON.stringify({ host, lang, at: new Date().toISOString(), rows: results }, null, 1));
  console.log(`\nwrote ${OUTPUT} (${results.length} rows)`);
}

main();
