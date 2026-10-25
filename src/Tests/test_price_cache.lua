-- PoE2 Craft Overlay : Tests/test_price_cache.lua
-- A cached price is only useful if it is honest: it must expire, it must never be presented as fresh, and it must not
-- grow without limit. Each of those is checked here, including the exact edges of the day.
local H = require("Tests.harness")
local PriceCache = require("Craft.PriceCache")

return function(h)
	local now = 1700000000

	H.eq("cache: a day is the lifetime", PriceCache.TTL_HOURS, 24)

	-- Keys: stable, distinct, and derived from the item text plus the league.
	local first = PriceCache.key("Rarity: Rare\nDoom Shroud", "Standard")
	local again = PriceCache.key("Rarity: Rare\nDoom Shroud", "Standard")
	local otherText = PriceCache.key("Rarity: Rare\nDoom Veil", "Standard")
	local otherLeague = PriceCache.key("Rarity: Rare\nDoom Shroud", "Hardcore")
	H.eq("cache: the same item gives the same key", first, again)
	H.check("cache: another item gives another key", first ~= otherText, tostring(first) .. " vs " .. tostring(otherText))
	H.check("cache: another league gives another key", first ~= otherLeague, tostring(first) .. " vs " .. tostring(otherLeague))
	H.eq("cache: an empty item has no key", PriceCache.key("", ""), nil)

	-- Store and read back.
	local store = { }
	local stored = PriceCache.put(store, first, {
		price = 12.5, currency = "Chaos Orb", query = "Doom Shroud", league = "Standard", source = "trade",
	}, { now = now })
	H.check("cache: a price with a number is stored", stored ~= nil, "nil")
	H.eq("cache: the price is kept", store[first].price, 12.5)
	H.eq("cache: the query is kept", store[first].query, "Doom Shroud")
	H.eq("cache: put without a price stores nothing", PriceCache.put(store, "k", { currency = "Chaos" }, { now = now }), nil)

	local hit, age = PriceCache.get(store, first, { now = now + 3600 })
	H.check("cache: an hour later it still hits", hit ~= nil, "miss")
	H.check("cache: the age is about an hour", age > 0.9 and age < 1.1, tostring(age))

	-- The exact edge: 23 h 59 min is still good, 24 h 1 min is not.
	local nearly = PriceCache.get(store, first, { now = now + 24 * 3600 - 60 })
	H.check("cache: just under the day it still hits", nearly ~= nil, "miss")
	local expired = PriceCache.get(store, first, { now = now + 24 * 3600 + 60 })
	H.eq("cache: past the day it misses", expired, nil)
	H.eq("cache: and the expired entry is gone", store[first], nil)

	-- Description never calls a cached price fresh.
	PriceCache.put(store, first, { price = 12.5, league = "Standard" }, { now = now })
	local record = store[first]
	local fresh = PriceCache.describe(record, 0.2)
	H.check("cache: a young price still says it comes from the cache", fresh.fromCache == true, tostring(fresh.fromCache))
	H.check("cache: a young price needs no refresh offer", fresh.refreshOffered == false, tostring(fresh.refreshOffered))
	local old = PriceCache.describe(record, 20)
	H.check("cache: an older price offers a refresh", old.refreshOffered == true, tostring(old.refreshOffered))
	H.check("cache: an older price is marked stale", old.stale == true, tostring(old.stale))
	H.check("cache: the sentence mentions the cache", old.text:find("кеш", 1, true) ~= nil, old.text)

	-- Pruning: expired entries go, and an oversized store keeps the newest.
	local crowded = { }
	for index = 1, 30 do
		crowded[string.format("k%02d", index)] = { price = index, fetchedAt = now - index * 600 }
	end
	crowded.stale = { price = 1, fetchedAt = now - 48 * 3600 }
	local removed = PriceCache.prune(crowded, { now = now }, 10)
	H.check("cache: pruning removed something", removed > 0, tostring(removed))
	H.eq("cache: the expired entry is gone", crowded.stale, nil)
	local kept = 0
	for _ in pairs(crowded) do
		kept = kept + 1
	end
	H.eq("cache: the store is trimmed to the limit", kept, 10)
	H.check("cache: the newest entry survived", crowded.k01 ~= nil, "k01 gone")

	-- Persistence: what is written can be read back by the same code.
	local written = nil
	PriceCache.save(store, "price-cache.lua", function(_, text) written = text return true end)
	H.check("cache: saving produced text", type(written) == "string" and #written > 20, "empty")
	local reloaded = PriceCache.load("price-cache.lua", function() return written end)
	H.eq("cache: the reloaded entry keeps its price", reloaded[first] and reloaded[first].price, 12.5)
	local broken = PriceCache.load("price-cache.lua", function() return "this is not lua {" end)
	H.eq("cache: a broken file loads as an empty cache", type(broken), "table")
	local missing = PriceCache.load("price-cache.lua", function() return nil end)
	H.eq("cache: a missing file loads as an empty cache", type(missing), "table")
	-- The card stays silent while the price is fresh, and speaks only when it may no longer be today's market.
	H.eq("cache: six hours is the point where the card speaks", PriceCache.CARD_NOTE_HOURS, 6)
	local young = PriceCache.cardNote({ price = 5, league = "Standard" }, 1.5)
	H.eq("cache: a fresh price gives the card no line", young, nil)
	local edge = PriceCache.cardNote({ price = 5, league = "Standard" }, 6)
	H.eq("cache: exactly six hours is still silent", edge, nil)
	local old = PriceCache.cardNote({ price = 5, league = "Standard", query = "Doom Shroud" }, 9)
	H.check("cache: an older price gives a line", old ~= nil, "nil")
	H.check("cache: the line offers a refresh", old and old.refreshOffered == true, tostring(old and old.refreshOffered))
	H.check("cache: the line is marked stale", old and old.stale == true, tostring(old and old.stale))
	H.check("cache: the line keeps the query it came from", old and old.query == "Doom Shroud", tostring(old and old.query))
	H.check("cache: the line says the word cache", old and old.text:find("кеш", 1, true) ~= nil, old and old.text)
	H.eq("cache: no record means no line", PriceCache.cardNote(nil, 20), nil)
	H.eq("cache: an unreadable age means no line", PriceCache.cardNote({ price = 5 }, nil), nil)
	-- A caller can ask for a different point, and eight hours must silence a stricter threshold of twelve.
	local strict = PriceCache.cardNote({ price = 5 }, 8, 12)
	H.eq("cache: a stricter threshold silences an eight hour price", strict, nil)end
