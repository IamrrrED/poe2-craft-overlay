-- PoE2 Craft Overlay : Craft/PriceCache.lua
-- Remembers item prices for a day so the panel does not re-ask the trade site for the same item on every hover.
--
-- Two rules shape this module:
--   * a cached price is never presented as a fresh one - every lookup says how old it is and whether the caller
--     should offer to refresh;
--   * the cache never invents a price. A miss returns nil; a hit returns exactly what was stored, with its league and
--     the query that produced it, so the card can show the same "where did this number come from" line as before.
--
-- The store is a plain table so the logic is testable without touching the disk; load/save handle one small file the
-- overlay owns (same approach as Core/prefs.lua: the file is written by us, so reading it back as Lua is safe).

local PriceCache = { }

--- A day. A price older than this is worse than no price: it is a different market.
PriceCache.TTL_HOURS = 24

-- Keys are short hex hashes of the item text plus the league. FNV-1a on bytes: stable across runs, no dependencies.
function PriceCache.key(itemText, league)
	local text = tostring(itemText or "") .. "\n" .. tostring(league or "")
	if text == "\n" then
		return nil
	end
	local hash = 2166136261
	for index = 1, #text do
		hash = hash ~ text:byte(index)
		hash = (hash * 16777619) % 4294967296
	end
	return string.format("%08x", hash)
end

local function nowSeconds(options)
	if type(options) == "table" and tonumber(options.now) then
		return tonumber(options.now)
	end
	return os.time()
end

--- Store a price.
-- @param store table (in memory or loaded from disk)
-- @param key from PriceCache.key
-- @param entry { price=number, currency=string, query=string, league=string, source=string }
-- @return the stored entry
function PriceCache.put(store, key, entry, options)
	if type(store) ~= "table" or not key or type(entry) ~= "table" then
		return nil
	end
	local record = {
		price = tonumber(entry.price),
		currency = entry.currency and tostring(entry.currency) or nil,
		query = entry.query and tostring(entry.query) or nil,
		league = entry.league and tostring(entry.league) or nil,
		source = entry.source and tostring(entry.source) or nil,
		fetchedAt = nowSeconds(options),
	}
	if not record.price then
		return nil
	end
	store[key] = record
	return record
end

--- Look a price up.
-- @return entry, nil when it is missing or older than the TTL (an expired entry is dropped, not returned)
function PriceCache.get(store, key, options)
	if type(store) ~= "table" or not key then
		return nil
	end
	local record = store[key]
	if type(record) ~= "table" or not tonumber(record.fetchedAt) then
		return nil
	end
	local ageHours = (nowSeconds(options) - tonumber(record.fetchedAt)) / 3600
	if ageHours > PriceCache.TTL_HOURS then
		store[key] = nil
		return nil
	end
	return record, ageHours
end

--- How to describe a hit to the player. Never says "fresh" for something from the store.
function PriceCache.describe(record, ageHours)
	if type(record) ~= "table" then
		return nil
	end
	local age = tonumber(ageHours) or 0
	local text
	if age < 1 then
		text = "цена из кеша, только что"
	elseif age < 6 then
		text = string.format("цена из кеша, %d ч назад", math.floor(age + 0.5))
	else
		text = string.format("цена из кеша, %d ч назад - обновить", math.floor(age + 0.5))
	end
	return {
		text = text,
		fromCache = true,
		ageHours = age,
		stale = age > (PriceCache.TTL_HOURS / 2),
		refreshOffered = age > (PriceCache.TTL_HOURS / 2),
		league = record.league,
		query = record.query,
	}
end

--- Drop everything older than the TTL, and, if the store is too big, the oldest entries first.
-- A cache that grows without limit is a leak with a friendly name.
function PriceCache.prune(store, options, maxEntries)
	if type(store) ~= "table" then
		return 0
	end
	local now = nowSeconds(options)
	local removed = 0
	local survivors = { }
	for key, record in pairs(store) do
		local fetchedAt = type(record) == "table" and tonumber(record.fetchedAt) or nil
		if not fetchedAt or (now - fetchedAt) / 3600 > PriceCache.TTL_HOURS then
			store[key] = nil
			removed = removed + 1
		else
			survivors[#survivors + 1] = { key = key, fetchedAt = fetchedAt }
		end
	end
	local limit = tonumber(maxEntries)
	if limit and #survivors > limit then
		table.sort(survivors, function(first, second) return first.fetchedAt > second.fetchedAt end)
		for index = limit + 1, #survivors do
			store[survivors[index].key] = nil
			removed = removed + 1
		end
	end
	return removed
end

--- Read the cache file. Missing or broken file means an empty cache, never an error.
function PriceCache.load(path, readFile)
	local reader = readFile or (function(filePath)
		local util = require("Core.util")
		return util.readFile(filePath)
	end)
	local ok, text = pcall(reader, path or "price-cache.lua")
	if not ok or not text or text == "" then
		return { }
	end
	local chunk = (loadstring or load)(text)
	if not chunk then
		return { }
	end
	local loaded = chunk()
	if type(loaded) ~= "table" then
		return { }
	end
	return loaded
end

--- Write the cache file. Failures are silent on purpose: a lost cache costs one query, not a craft.
function PriceCache.save(store, path, writeFile)
	local writer = writeFile or (function(filePath, text)
		local util = require("Core.util")
		return util.writeFile(filePath, text)
	end)
	if type(store) ~= "table" then
		return false
	end
	local lines = { "return {" }
	for _, key in ipairs((function()
		local keys = { }
		for name in pairs(store) do
			keys[#keys + 1] = name
		end
		table.sort(keys)
		return keys
	end)()) do
		local record = store[key]
		if type(record) == "table" and tonumber(record.price) then
			lines[#lines + 1] = string.format(
				"\t[%q] = { price = %s, currency = %q, league = %q, query = %q, source = %q, fetchedAt = %d },",
				key, tostring(record.price), tostring(record.currency or ""), tostring(record.league or ""),
				tostring(record.query or ""), tostring(record.source or ""), tonumber(record.fetchedAt) or 0)
		end
	end
	lines[#lines + 1] = "}"
	local ok = pcall(writer, path or "price-cache.lua", table.concat(lines, "\n") .. "\n")
	return ok
end

return PriceCache
