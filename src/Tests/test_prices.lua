-- PoE2 Craft Overlay : Tests/test_prices.lua
-- Currency prices (Craft of Exile snapshot) and, more importantly, the rule that they are
-- never used without their league: a number from another league is worse than no number.

local Prices = require("Craft.Prices")
local config = require("Data.config")

return function(H)
	local info = Prices.info()
	H.eq("prices: snapshot present", info.available, true)
	H.eq("prices: snapshot names its league", type(info.league) == "string" and #info.league > 0, true)
	H.eq("prices: snapshot has a fetch time", type(info.fetchedAt) == "string" and #info.fetchedAt >= 10, true)
	H.eq("prices: snapshot names its source", type(info.source) == "string" and #info.source > 5, true)
	H.eq("prices: unit is chaos", info.unit, "chaos")
	H.eq("prices: currencies loaded", info.currencies > 0, true)

	-- Values are only meaningful relative to each other; these relationships hold in any
	-- league where the game's economy is intact, so they catch a corrupted snapshot.
	local chaos = Prices.unitPrice("Chaos Orb")
	local divine = Prices.unitPrice("Divine Orb")
	local exalted = Prices.unitPrice("Exalted Orb")
	H.eq("prices: chaos is the unit and equals 1", chaos, 1)
	H.eq("prices: divine is worth more than chaos", divine and divine > 1, true)
	H.eq("prices: exalted is worth less than chaos", exalted and exalted < 1, true)
	H.eq("prices: an unknown currency has no price", Prices.unitPrice("Not A Currency"), nil)
	H.eq("prices: step cost multiplies the unit price",
		math.abs(Prices.stepCost("Divine Orb", 2) - divine * 2) < 1e-9, true)

	-- The league gate: a snapshot the player picked at agent start counts as theirs (the
	-- agent asks which league is being played and stores the answer), so it applies. One
	-- that merely happens to be on disk for a different league is still refused.
	local snapshot = require("Data.prices")
	if snapshot.chosen == true then
		local applies, why = Prices.matchesLeague(config.leagueName or "0.5.5 Forbidden Rites")
		H.eq("prices: the league chosen at start is used", applies, true)
		H.eq("prices: a chosen snapshot needs no excuse", why, nil)
		H.eq("prices: the chosen league is recorded", type(info.league) == "string" and #info.league > 0, true)
	else
		local matches, why = Prices.matchesLeague(config.leagueName or "0.5.5 Forbidden Rites")
		H.eq("prices: snapshot for another league is refused", matches, false)
		H.eq("prices: refusal explains itself", type(why) == "string" and #why > 10, true)
		H.eq("prices: snapshot league is named in the reason",
			why ~= nil and why:find(tostring(info.league), 1, true) ~= nil, true)
	end

	local forced = Prices.matchesLeague("0.5.5 Forbidden Rites", true)
	H.eq("prices: an explicit override accepts any league", forced, true)
	local named = Prices.matchesLeague("0.5.5 Forbidden Rites", info.league)
	H.eq("prices: naming the snapshot league matches it", named, true)
	local empty = Prices.matchesLeague("")
	-- An explicitly chosen snapshot is used even when nothing else identifies the league;
	-- without that choice an unknown league means no prices.
	if snapshot.chosen == true then
		H.eq("prices: a chosen snapshot needs no league name", empty, true)
	else
		H.eq("prices: no configured league means no prices", empty, false)
	end

	-- The default configuration must not show prices from another league.
	H.eq("prices: default config does not force prices", config.ui.pricesLeague ~= true, true)
end
