const engine = require('../mcp/engine.js');
const fs = require('fs');
const path = require('path');
(async () => {
  const itemText = fs.readFileSync(path.join(engine.ROOT, 'samples', 'rare_gloves.txt'), 'utf8');
  try {
    const lines = await engine.call('item_lines', { item_text: itemText });
    console.log('OK: свойств ' + (lines.properties || []).length + ', модов ' + (lines.mods || []).length);
  } catch (error) {
    console.log('ОШИБКА: ' + String(error.message));
  }
})();
