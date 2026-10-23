const fs = require("fs");
const path = require("path");
const { call } = require("../mcp/engine.js");
const root = path.resolve(__dirname, "..");
const itemText = fs.readFileSync(path.join(root, "src/last_item.txt"), "utf8");
(async () => {
  const result = await call("mod_chances", { item_text: itemText, method: "exalted" });
  const text = JSON.stringify(result);
  console.log("  размер ответа: " + text.length + " символов");
  console.log("  упоминаний \"coe\":   " + (text.match(/coe/g) || []).length);
  console.log("  упоминаний \"mixed\": " + (text.match(/mixed/g) || []).length);
  console.log("  упоминаний \"weightSource\": " + (text.match(/weightSource/g) || []).length);
  const groups = (result && result.groups) || [];
  groups.slice(0, 5).forEach((g) => console.log("      " + String(g.text).slice(0, 40).padEnd(40) + " шанс " + g.chance + "  источник " + (g.weightSource || "нет поля")));
  console.log("  поля верхнего уровня: " + Object.keys(result || {}).join(", "));
})();
