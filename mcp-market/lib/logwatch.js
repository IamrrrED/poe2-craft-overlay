/*
 * PoE2 Market : lib/logwatch.js
 *
 * Наблюдатель за Client.txt — файлом, который клиент игры пишет сам.
 *
 * Зачем: половина торгового цикла происходит в игре, и раньше её приходилось отмечать руками
 * («молчит», «взял в работу»). В логе есть ровно то, что нужно, и это проверено на живом файле:
 *   @To <продавец>: Hi, I would like to buy your <предмет> listed for <цена> <валюта> in <лига>
 *   @To <продавец>: ty                          — это пишут после удачной сделки
 *   @From <продавец>: This player is AFK.       — авто-ответ клиента продавца
 *   [LOADING SCREEN] (Убежище на берегу)        — вы в убежище, обычно это идёт сделка
 *
 * Только чтение файла: ни ввода, ни кликов, ни памяти процесса игры, ни пакетов. Наблюдатель
 * не пишет продавцам и ничего не покупает — он лишь понимает, что уже сделал человек.
 */

'use strict';

const fs = require('fs');
const path = require('path');

const STATE_DIR = process.env.POE2_MARKET_STATE || path.join(__dirname, '..', '.state');
const STATE_FILE = path.join(STATE_DIR, 'logwatch.json');
const DEFAULT_LOG = process.env.POE2_CLIENT_LOG
  || 'G:\\Soft\\Steam\\steamapps\\common\\Path of Exile 2\\logs\\Client.txt';
/** Сколько ждать ответа продавца, прежде чем считать, что он молчит. */
const SILENCE_MINUTES = 20;
/** Сколько событий держать для показа на странице. */
const RECENT_LIMIT = 60;

const LINE_RE = /^(\d{4})\/(\d{2})\/(\d{2}) (\d{2}):(\d{2}):(\d{2})\s+.*?\[[A-Z]+\s+Client\s+\d+\]\s?(.*)$/;

function readState(stateFile = STATE_FILE) {
  try {
    const parsed = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
    return {
      offset: typeof parsed.offset === 'number' ? parsed.offset : null,
      recent: Array.isArray(parsed.recent) ? parsed.recent : [],
      applied: Array.isArray(parsed.applied) ? parsed.applied : [],
      // Кому и за какой лот писали: без этого «ty» и убежище не к чему привязать.
      lastWhisper: parsed.lastWhisper && typeof parsed.lastWhisper === 'object' ? parsed.lastWhisper : {},
    };
  } catch {
    return { offset: null, recent: [], applied: [], lastWhisper: {} };
  }
}

function writeState(state, stateFile = STATE_FILE) {
  try {
    fs.mkdirSync(path.dirname(stateFile), { recursive: true });
    fs.writeFileSync(stateFile, JSON.stringify({
      offset: state.offset,
      updatedAt: new Date().toISOString(),
      recent: state.recent.slice(-RECENT_LIMIT),
      applied: state.applied.slice(-RECENT_LIMIT),
      lastWhisper: state.lastWhisper || {},
    }, null, 2));
    return true;
  } catch {
    return false;
  }
}

/** Метка времени строки лога → ISO. Клиент пишет локальное время. */
function lineTime(match) {
  const [, year, month, day, hour, minute, second] = match;
  return new Date(Number(year), Number(month) - 1, Number(day), Number(hour), Number(minute), Number(second)).toISOString();
}

/**
 * Разобрать одну строку лога. Чистая функция: её и проверяем тестами.
 * @param {string} line
 * @returns {object|null} событие или null, если строка не про торговлю
 */
function parseLine(line) {
  const match = LINE_RE.exec(line);
  if (!match) return null;
  const at = lineTime(match);
  const text = match[7] || '';

  // Ваш виспер продавцу — самый полезный формат: в нём предмет, цена и лига.
  const whisper = /^@To (\S+): Hi, I would like to buy your (.+?) listed for ([\d.]+) ([\w' -]+?) in (.+)$/.exec(text);
  if (whisper) {
    return {
      type: 'whisper-sent',
      at,
      seller: whisper[1],
      itemText: whisper[2],
      amount: Number(whisper[3]),
      currency: whisper[4],
      league: whisper[5],
    };
  }

  // «ty» после сделки: так закрывают покупку, и по этому видно, что обмен состоялся.
  const thanks = /^@To (\S+): ty$/i.exec(text);
  if (thanks) return { type: 'thanks', at, seller: thanks[1] };

  // Покупатель пишет нам: значит предмет уже выставлен на площадке. Это сигнал «выставлен».
  const sale = /^@From (\S+): Hi, I would like to buy your (.+?) listed for ([\d.]+) ([\w' -]+?) in (.+)$/.exec(text);
  if (sale) {
    return {
      type: 'sale-whisper',
      at,
      buyer: sale[1],
      itemText: sale[2],
      amount: Number(sale[3]),
      currency: sale[4],
      league: sale[5],
    };
  }

  // Ответ продавца. Клиент часто отвечает сам, когда игрок отошёл.
  const incoming = /^@From (\S+): (.*)$/.exec(text);
  if (incoming) {
    return {
      type: 'whisper-received',
      at,
      seller: incoming[1],
      text: incoming[2],
      afk: /AFK|отошёл|отсутству/i.test(incoming[2]),
    };
  }

  // Переходы между областями: по ним видно убежище (визит к продавцу).
  const loading = /\[LOADING SCREEN\] \((.+?)\)/.exec(text);
  if (loading) return { type: 'zone', at, zone: loading[1], hideout: /Hideout|Убежищ/i.test(loading[1]) };
  const area = /Generating level \d+ area "([A-Za-z0-9_]+)"/.exec(text);
  if (area) return { type: 'zone', at, zone: area[1], hideout: /Hideout/i.test(area[1]) };

  return null;
}

/** Привести название предмета к сравнимому виду. */
function normalizeName(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/[^a-zа-я0-9 ]+/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Найти, к какому лоту относится виспер: по имени предмета из текста и по цене.
 *
 * @param {object} event событие whisper-sent
 * @param {object[]} targets записи «в работе» и лоты пула: { id, name, label, priceDivine }
 * @returns {object|null} лучшая запись
 */
function matchTarget(event, targets) {
  if (!event || (event.type !== 'whisper-sent' && event.type !== 'sale-whisper')) return null;
  const haystack = normalizeName(event.itemText);
  let best = null;
  for (const target of targets || []) {
    const name = normalizeName(target.name || target.label);
    if (!name || !haystack.includes(name)) continue;
    const price = target.priceDivine === undefined || target.priceDivine === null
      ? null
      : Number(target.priceDivine);
    // Точное совпадение цены важнее: по нему видно, что написали именно за этот лот.
    const priceMatches = price !== null && event.currency.toLowerCase() === 'divine'
      && Math.abs(price - event.amount) < 0.01;
    const score = (priceMatches ? 10 : 0) + (name.length > 4 ? 2 : 1);
    if (!best || score > best.score) best = { target, score, priceMatches };
  }
  return best ? { ...best.target, priceMatches: best.priceMatches } : null;
}

/** Пора ли считать, что продавец молчит: виспер отправлен, ответа нет. */
function isSilent(entry, now = Date.now(), minutes = SILENCE_MINUTES) {
  if (!entry || !entry.whisperedAt) return false;
  if (entry.replyAt || entry.tradeConfirmedAt) return false;
  return now - new Date(entry.whisperedAt).getTime() > minutes * 60 * 1000;
}

/** Последний виспер: кому и по какому лоту. Нужен, чтобы привязать `ty`, ответ и убежище. */
function findLastWhisper(lastWhisper, seller, now = Date.now(), maxMinutes = 60) {
  const table = lastWhisper || {};
  if (seller && table[seller]) return table[seller];
  let best = null;
  for (const link of Object.values(table)) {
    if (!link || !link.at) continue;
    if (now - new Date(link.at).getTime() > maxMinutes * 60 * 1000) continue;
    if (!best || new Date(link.at) > new Date(best.at)) best = link;
  }
  return best;
}

/**
 * Создать наблюдатель.
 *
 * @param {object} opts
 * @param {string} [opts.logPath] путь к Client.txt
 * @param {string} [opts.stateFile] где хранить offset (тесты используют свой файл)
 * @param {() => object[]} opts.getTargets записи, которые можно сопоставлять
 * @param {(target: object, patch: object, event: object) => void} opts.onSignal применить сигнал
 * @param {(event: object) => object|null} [opts.onCreate] создать запись по висперу
 * @param {number} [opts.intervalMs]
 */
function createLogWatcher(opts) {
  const logPath = opts.logPath || DEFAULT_LOG;
  const stateFile = opts.stateFile || STATE_FILE;
  const intervalMs = opts.intervalMs || 15 * 1000;
  // Лог — необязательный источник: он живёт только пока запущен клиент игры, и без него
  // инструмент полностью работает (площадку спрашиваем по аккаунту). По умолчанию выключен.
  let enabled = opts.enabled === true;
  // Часы можно подменить: тесты так проверяют привязку событий без зависимости от реального времени.
  const clock = opts.now || (() => Date.now());
  let state = readState(stateFile);
  let timer = null;
  let stopped = false;
  const stats = { checked: 0, matched: 0, started: false };

  function status() {
    let size = null;
    let exists = false;
    let modifiedAt = null;
    try {
      const stat = fs.statSync(logPath);
      size = stat.size;
      modifiedAt = stat.mtime.toISOString();
      exists = true;
    } catch {
      exists = false;
    }
    return {
      enabled,
      logPath,
      exists,
      size,
      modifiedAt,
      offset: state.offset,
      note: enabled
        ? 'читаю только новые строки Client.txt'
        : 'выключен: продажу и цены отслеживает площадка, лог нужен только для подтверждения покупки',
      started: stats.started,
      checkedLines: stats.checked,
      matched: stats.matched,
      silenceMinutes: SILENCE_MINUTES,
      recent: state.recent.slice(-20).reverse(),
      applied: state.applied.slice(-20).reverse(),
    };
  }

  /** Прочитать только новые строки: при первом запуске встаём в конец файла, историю не переигрываем. */
  function readNewLines() {
    let stat;
    try {
      stat = fs.statSync(logPath);
    } catch {
      return [];
    }
    if (state.offset === null || state.offset > stat.size) {
      state.offset = stat.size;
      writeState(state, stateFile);
      return [];
    }
    if (stat.size === state.offset) return [];
    const length = stat.size - state.offset;
    const buffer = Buffer.alloc(length);
    let handle;
    try {
      handle = fs.openSync(logPath, 'r');
      fs.readSync(handle, buffer, 0, length, state.offset);
    } catch {
      return [];
    } finally {
      if (handle !== undefined) fs.closeSync(handle);
    }
    state.offset = stat.size;
    return buffer.toString('utf8').split(/\r?\n/);
  }

  function tick() {
    if (stopped) return;
    const lines = readNewLines();
    if (!lines.length) return;
    stats.started = true;
    const events = [];
    for (const line of lines) {
      stats.checked += 1;
      const event = parseLine(line);
      if (event) events.push(event);
    }
    if (events.length) state.recent = state.recent.concat(events).slice(-RECENT_LIMIT);

    for (const event of events) {
      let target = null;
      try {
        target = matchTarget(event, opts.getTargets ? opts.getTargets() : []);
      } catch {
        target = null;
      }

      if (event.type === 'whisper-sent' && !target && opts.onCreate) {
        // Написали за лот, которого нет в работе: заводим запись сами, чтобы покупка не потерялась.
        try {
          target = opts.onCreate(event);
        } catch {
          target = null;
        }
      }

      // «ty», ответ продавца, письмо покупателя и убежище относятся не к свежему запросу,
      // а к тому висперу, который был раньше: привязываем их по собеседнику.
      if (!target && (event.type === 'thanks' || event.type === 'whisper-received' || event.type === 'zone')) {
        const who = event.type === 'zone' ? null : event.seller;
        const link = findLastWhisper(state.lastWhisper, who, clock());
        if (link) target = { id: link.targetId };
      }
      if (!target || !target.id) continue;

      const patch = {};
      if (event.type === 'whisper-sent') {
        patch.whisperedAt = event.at;
        patch.account = target.account || event.seller;
        patch.status = target.status && target.status !== 'watching' ? target.status : 'whispered';
        patch.note = `виспер отправлен по логу (${event.amount} ${event.currency})`;
        state.lastWhisper = state.lastWhisper || {};
        state.lastWhisper[event.seller] = {
          targetId: target.id, at: event.at, direction: 'buy', amount: event.amount, currency: event.currency,
        };
      } else if (event.type === 'sale-whisper') {
        // Покупатель пишет нам — значит предмет уже выставлен на площадке по этой цене.
        patch.status = 'listed';
        patch.listedAt = event.at;
        patch.listedPriceAmount = event.amount;
        patch.listedPriceCurrency = event.currency;
        patch.buyer = event.buyer;
        patch.note = `выставлен и найден покупателем: ${event.amount} ${event.currency}`;
        state.lastWhisper = state.lastWhisper || {};
        state.lastWhisper[event.buyer] = {
          targetId: target.id, at: event.at, direction: 'sell', amount: event.amount, currency: event.currency,
        };
      } else if (event.type === 'thanks') {
        const link = findLastWhisper(state.lastWhisper, event.seller, clock());
        patch.tradeConfirmedAt = event.at;
        if (link && link.direction === 'sell') {
          // Мы попрощались с покупателем: предмет продан по цене из его виспера.
          patch.status = 'sold';
          patch.soldAt = event.at;
          patch.sellPriceAmount = link.amount;
          patch.sellPriceCurrency = link.currency;
          patch.note = `продано по логу: ${link.amount} ${link.currency}`;
        } else if (link && link.direction === 'buy') {
          // Мы поблагодарили продавца: покупка состоялась, цена известна из нашего виспера.
          patch.status = 'bought';
          patch.boughtAt = event.at;
          patch.buyPriceAmount = link.amount;
          patch.buyPriceCurrency = link.currency;
          patch.note = `куплено по логу: ${link.amount} ${link.currency}`;
        } else {
          patch.note = 'сделка закрыта: в логе есть «ty»';
        }
      } else if (event.type === 'whisper-received') {
        patch.replyAt = event.at;
        patch.replyText = event.text.slice(0, 160);
        if (event.afk) patch.afkAt = event.at;
      } else if (event.type === 'zone' && event.hideout) {
        patch.hideoutAt = event.at;
      } else {
        continue;
      }

      stats.matched += 1;
      state.applied = state.applied
        .concat([{ at: event.at, type: event.type, target: target.id, patch }])
        .slice(-RECENT_LIMIT);
      try {
        opts.onSignal(target, patch, event);
      } catch {
        // сбой применения не должен останавливать наблюдение
      }
    }
    writeState(state, stateFile);
  }

  function start() {
    if (stopped || !enabled) return status();
    if (timer) clearInterval(timer);
    timer = setInterval(tick, intervalMs);
    if (timer.unref) timer.unref();
    tick();
    return status();
  }

  /** Включить чтение лога: нужно только для подтверждения покупки, когда игра запущена. */
  function enable() {
    enabled = true;
    return start();
  }

  function disable() {
    enabled = false;
    if (timer) clearInterval(timer);
    timer = null;
    return status();
  }

  function stop() {
    stopped = true;
    if (timer) clearInterval(timer);
    timer = null;
  }

  return { start, stop, enable, disable, isEnabled: () => enabled, status, tick, parseLine, state: () => state };
}

module.exports = {
  DEFAULT_LOG,
  STATE_FILE,
  SILENCE_MINUTES,
  RECENT_LIMIT,
  parseLine,
  normalizeName,
  matchTarget,
  isSilent,
  readState,
  writeState,
  createLogWatcher,
};
