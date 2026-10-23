const fs = require("fs");
const path = require("path");
const { call } = require("../mcp/engine.js");

const root = path.resolve(__dirname, "..");
const itemText = fs.readFileSync(path.join(root, "src/last_item.txt"), "utf8");
const coe = path.join(root, "src", "Data", "coe_text_map.lua");
const off = coe + ".off";

async function run(label) {
  const result = await call("mod_chances", { item_text: itemText, method: "exalted" });
  const entries = result && (result.mods || result.entries || result.topMods || []);
  const list = Array.isArray(entries) ? entries : [];
  console.log("  --- " + label + ": записей " + list.length + " ---");
  list.slice(0, 6).forEach((e) => {
    const text = String(e.text || e.name || "?").slice(0, 42).padEnd(42);
    console.log("      " + text + " шанс " + e.chance + "  вес " + e.weight + "  источник " + (e.weightSource || "?"));
  });
  if (!list.length) console.log("      " + JSON.stringify(result).slice(0, 260));
}

(async () => {
  try {
    await run("С данными CoE");
    fs.renameSync(coe, off);
    console.log("  (файл CoE временно отключён)");
    await run("Без данных CoE");
  } catch (error) {
    console.log("  ошибка: " + error.message);
  } finally {
    if (fs.existsSync(off)) { fs.renameSync(off, coe); console.log("  файл CoE возвращён на место"); }
  }
})();
