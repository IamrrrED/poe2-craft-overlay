# Кеш цен предметов: как подключить к карточке

Модуль: `src/Craft/PriceCache.lua` (27 тестов, все зелёные). Кеш живёт 24 ч, всегда сообщает возраст
и предлагает обновление после половины срока.

## Что уже есть

```lua
local PriceCache = require("Craft.PriceCache")

local store = PriceCache.load("price-cache.lua")          -- битый/отсутствующий файл = пустой кеш
local key   = PriceCache.key(itemText, league)            -- стабильный хеш текста предмета + лиги

local record, ageHours = PriceCache.get(store, key)       -- nil, если старше суток (запись удаляется)
if record then
    local note = PriceCache.describe(record, ageHours)
    -- note.text        = "цена из кеша, 20 ч назад - обновить"
    -- note.fromCache   = true
    -- note.refreshOffered = true (после 12 ч)
end

PriceCache.put(store, key, { price = 12.5, currency = "Chaos Orb", league = league, query = query })
PriceCache.prune(store, nil, 500)                         -- чистит просрочку и режет лишнее
PriceCache.save(store, "price-cache.lua")
```

## Что осталось (одна правка, два места)

1. **В карточке** (`docs/mockups/panel-real.html`, блок цены рядом с `priceButton`): после успешного запроса цены
   выводить строку из `note.text` и, если `note.refreshOffered`, показывать ту же кнопку как «Обновить».
   Строки для обоих языков уже есть в таблице (`priceWord`, `priceButton`, `buyPlaceholder`) — добавить две:
   `priceCached` / `priceCachedRefresh`.
2. **В обмене с движком**: панель передаёт в `craft_step` уже полученную цену и её время
   (`market_price`, `market_price_at`), а движок возвращает `report.priceCache` — запись из `describe()`.
   Это аддитивное поле: если его нет, карточка ведёт себя как раньше.

## Почему не сделано сразу

Правка карточки — это изменение DOM в файле на несколько тысяч строк, а его проверяет `check_all.ps1`
(«кнопка поиска на trade предлагается», «вердикт в DOM», …). Менять его вслепую, без открытой панели и
визуальной проверки, — значит рисковать 2387 зелёными тестами ради строки, которую никто не увидит.

## Правило, которое кеш не нарушает

Цена из кеша **никогда** не подаётся как свежая: `describe()` всегда возвращает `fromCache = true`, возраст и
признак «пора обновить». Это то же правило, что у снимка цен валют (`Craft/Prices.lua`): число без лиги и возраста
в этом проекте не выводится.
