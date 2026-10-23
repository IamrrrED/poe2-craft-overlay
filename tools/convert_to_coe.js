#!/usr/bin/env node
/**
 * Turn an item copied from the game into the item format Craft of Exile uses.
 *
 * Why this exists: pyoe2-craftpath (MIT) computes craft routes, but it only reads items in Craft
 * of Exile's emulator format - which normally means exporting by hand from their site. Our capture
 * already has the item text, so this closes that gap.
 *
 * The format, learned from the examples shipped with that engine:
 *
 *   {
 *     "settings": { "bgroup": 7, "base": 20, "bitem": 231, "ilvl": 100, "rarity": "magic", ... },
 *     "data": { "iaffixes": [ { "atype": "prefix", "id": 5120, "mgrp": "1", "tindex": 7, ... } ] }
 *   }
 *
 * `id` is the modifier id in Craft of Exile - the same id our coe_text_map.lua maps our wording
 * to. `bitem` and `base` are the numeric ids from coe_bases.lua.
 *
 * Mod lines arrive with a rolled value ("+23 to maximum Mana") while our map is keyed by the tier
 * wording with a range ("+(20-25) to maximum Mana"). Both sides are therefore normalised - values
 * become # - before matching. Tiers of one modifier collapse into the same key, so the first match
 * wins and the caller is told how many lines were resolved.
 *
 * Usage:
 *   node tools/convert_to_coe.js --item src/ring_test.txt --out src/ring_coe.json
 */

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const { call } = require(path.join(root, "mcp", "engine.js"));

function arg(name, fallback) {
  const index = process.argv.indexOf("--" + name);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

function normalise(text) {
  return String(text)
    .toLowerCase()
    .replace(/\([^)]*\)/g, "#")
    .replace(/\d+(?:\.\d+)?/g, "#")
    .replace(/[^a-z#\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}


(async () => {
  try {
    const itemPath = path.resolve(root, arg("item", path.join("src", "ring_test.txt")));
    const outPath = path.resolve(root, arg("out", path.join("src", "ring_coe.json")));
    const itemText = fs.readFileSync(itemPath, "utf8");

    // The engine resolves the Russian client text to English and names the base.
    const analysis = await call("analyze_item", { item_text: itemText });
    const item = analysis && (analysis.item || analysis);
    const lines = item.explicitLines || item.explicits || [];
    const modLines = (Array.isArray(lines) ? lines : []).map((entry) =>
      typeof entry === "string" ? entry : entry.text);

    // Base ids and our wording -> Craft of Exile modifier id.
    const baseIds = new Map();
    const baseText = fs.readFileSync(path.join(root, "src", "Data", "coe_bases.lua"), "utf8");
    const baseLine = new RegExp('\\["([^"]+)"\\]\\s*=\\s*\\{ id_bitem = "([^"]+)", id_base = "([^"]+)"', "g");
    let baseMatch;
    while ((baseMatch = baseLine.exec(baseText)) !== null) {
      baseIds.set(baseMatch[1], { bitem: baseMatch[2], base: baseMatch[3] });
    }

    const textMap = new Map();
    const mapText = fs.readFileSync(path.join(root, "src", "Data", "coe_text_map.lua"), "utf8");
    const mapLine = /\["([^"]+)"\]\s*=\s*(\d+),/g;
    let mapMatch;
    while ((mapMatch = mapLine.exec(mapText)) !== null) {
      textMap.set(normalise(mapMatch[1]), Number(mapMatch[2]));
    }

    const ids = baseIds.get(item.baseType) || { };
    const affixes = [];
    const unresolved = [];
    modLines.forEach((line) => {
      const id = textMap.get(normalise(line));
      if (id) {
        affixes.push({
          atype: /^\+?\d|%/.test(line) ? "prefix" : "prefix",
          id: id,
          mgrp: "0",
          modgroups: [],
          tindex: 0,
          bench: 0,
          frac: 0,
          maven: 0,
          nvalues: "[[0,0]]",
          rolls: [0],
          weight: "0",
        });
      } else {
        unresolved.push(line);
      }
    });

    const document = {
      settings: {
        bgroup: 0,
        base: Number(ids.base || 0),
        bitem: Number(ids.bitem || 0),
        ilvl: Number(item.itemLevel || 0),
        rarity: String(item.rarity || "rare").toLowerCase(),
        influences: null,
        sockets: 0,
        socketed: [],
        quality: Number(item.quality || 0),
        exmods: null,
      },
      data: { implicits: null, iaffixes: affixes, iaffbt: { prefix: 0, suffix: 0 }, imprint: null, eldritch: null, meta_flags: {} },
      log: [],
    };

    fs.writeFileSync(outPath, JSON.stringify(document, null, 2), "utf8");
    console.log("  предмет: " + item.baseType + ", ilvl " + item.itemLevel + ", редкость " + item.rarity);
    console.log("  id базы: bitem=" + ids.bitem + " base=" + ids.base);
    console.log("  модов сопоставлено: " + affixes.length + " из " + modLines.length);
    if (unresolved.length) console.log("  без пары: " + unresolved.slice(0, 3).join(" | "));
    console.log("  записано: " + path.relative(root, outPath));

    // Structural check against the example the engine ships with.
    const example = JSON.parse(fs.readFileSync(path.join(root, "..", "_engines", "pyoe2-craftpath-main",
      "python_examples", "example_items", "startitem_good_essence_bow.json"), "utf8"));
    const sameSettings = Object.keys(example.settings).filter((k) => !(k in document.settings));
    const sameAffix = example.data.iaffixes[0]
      ? Object.keys(example.data.iaffixes[0]).filter((k) => !(k in (affixes[0] || { })))
      : [];
    console.log("  сверка с их примером:");
    console.log("      полей settings не хватает: " + (sameSettings.length ? sameSettings.join(", ") : "нет"));
    console.log("      полей записи мода не хватает: " + (sameAffix.length ? sameAffix.join(", ") : "нет"));
  } catch (error) {
    console.log("  ошибка: " + error.message);
  } finally {
    process.exit(0);
  }
})();
