#!/usr/bin/env node
/**
 * Assemble the crafting panel text for an item - the content the in-game overlay will show.
 *
 * This is the specification of the panel and a way to check it without launching the game: it asks
 * the engine for exactly what the panel will ask for, and prints the block in the form the overlay
 * will draw it.
 *
 * Everything comes from the engine:
 *   - chances per modifier group, each marked exact (Craft of Exile weights for this base) or
 *     estimated (the tag-based fallback);
 *   - attempts and cost at the 50th, 90th and 99th percentile;
 *   - the craft options, whose price and kind labels are translated with the engine's own
 *     Russian dictionary (src/Mcp/out_ru.lua), so the panel and the data cannot drift apart.
 *
 * Modifier wordings are still English: they come from the Path of Building data. A Russian
 * modifier dictionary is a separate task.
 *
 * Usage:
 *   node tools/panel_preview.js --item src/ring_test.txt
 */

const fs = require("fs");
const path = require("path");
const { call } = require(path.join(__dirname, "..", "mcp", "engine.js"));

const root = path.resolve(__dirname, "..");

function arg(name, fallback) {
  const index = process.argv.indexOf("--" + name);
  return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

/** Russian plural form: 1 попытка, 2 попытки, 5 попыток. */
function plural(count, one, few, many) {
  const n = Math.abs(count) % 100;
  const last = n % 10;
  if (n > 10 && n < 20) return many;
  if (last > 1 && last < 5) return few;
  if (last === 1) return one;
  return many;
}

/** A label from the engine's Russian dictionary, so there is one source of truth. */
function label(dictionary, key) {
  const file = fs.readFileSync(path.join(root, "src", "Mcp", "out_ru.lua"), "utf8");
  const block = file.match(new RegExp("OutRu\\." + dictionary + "\\s*=\\s*\\{[\\s\\S]*?\\}"));
  if (!block) return key;
  const hit = block[0].match(new RegExp(key + '\\s*=\\s*"([^"]+)"'));
  return hit ? hit[1] : key;
}

function width(text, size) {
  const plain = String(text);
  return plain.length >= size ? plain.slice(0, size - 1) + "…" : plain.padEnd(size);
}

(async () => {
  try {
    const itemPath = path.resolve(root, arg("item", path.join("src", "ring_test.txt")));
    const itemText = fs.readFileSync(itemPath, "utf8");

    const analysis = await call("analyze_item", { item_text: itemText });
    const item = analysis && (analysis.item || analysis);
    const chances = await call("mod_chances", { item_text: itemText, method: "exalted" });
    const plan = await call("league_methods", { item_text: itemText });
    const cost = await call("craft_cost", { item_text: itemText, method: "exalted" });

    const rule = "─".repeat(54);
    const lines = [];
    lines.push(String(item.name || "").toUpperCase() + " · " + item.baseType + " · ур. " + item.itemLevel);
    lines.push(rule);
    lines.push("ШАНСЫ (Exalted Orb) — " + (cost.chancePerAttempt * 100).toFixed(2) + "% за попытку");
    (chances.groups || []).slice(0, 6).forEach((group) => {
      const mark = group.weightSource === "coe" ? "точно" : "оценка";
      lines.push("  " + String(group.chance).padStart(6) + "%  " + width(group.text, 40) + "[" + mark + "]");
    });

    lines.push(rule);
    lines.push("СТОИМОСТЬ");
    ["p50", "p90", "p99"].forEach((key) => {
      const value = (cost.costTo || {})[key];
      if (!value) return;
      const attempts = Number(value.attempts || 0);
      lines.push("  " + key + ": " + attempts + " " + plural(attempts, "попытка", "попытки", "попыток") +
        " = " + (value.exalted || 0) + " exalted");
    });

    lines.push(rule);
    const options = plan.options || [];
    lines.push("ВАРИАНТЫ (" + options.length + ")");
    options.slice(0, 5).forEach((option, index) => {
      lines.push("  " + (index + 1) + ". " + label("planCost", option.cost) + " · " +
        label("planKind", option.kind) + (option.title ? " — " + String(option.title).slice(0, 44) : ""));
      if (option.pool && option.pool[0]) {
        lines.push("     лучший: " + option.pool[0].chance + "% — " + width(option.pool[0].text, 40));
      }
    });
    lines.push(rule);
    console.log(lines.join("\n"));
  } catch (error) {
    console.log("  ОШИБКА: " + error.message);
  } finally {
    process.exit(0);
  }
})();
