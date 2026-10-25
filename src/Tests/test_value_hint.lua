-- PoE2 Craft Overlay : Tests/test_value_hint.lua
-- The highlight has to be earned: a neutral modifier must never be dressed up as the goal, and a boost may only be
-- attached to the family it names. A wrong "use this omen" is worse than no hint, because it costs currency.
local H = require("Tests.harness")
local ValueHint = require("Craft.ValueHint")

return function(h)
	local wanted = {
		{ side = "suffix", family = "life", bestText = "+# to maximum Life", chance = 0.12, score = 9, boost = 2.0 },
		{ side = "suffix", family = "resistance", bestText = "+#% to Fire Resistance", chance = 0.3, score = 6, boost = 1.4 },
		{ side = "prefix", family = "mana", bestText = "+# to maximum Mana", chance = 0.25, score = 2, boost = 1.0 },
	}

	local hints = ValueHint.forWanted(wanted)
	H.eq("value: two entries are worth chasing", #hints.valuable, 2)
	H.eq("value: the neutral one is not", #hints.others, 1)
	H.eq("value: the neutral family is kept, not hidden", hints.others[1].family, "mana")

	-- Reachability first: resistance is more likely than life, so it leads even though life scores higher.
	H.eq("value: the more likely valuable mod leads", hints.valuable[1].family, "resistance")
	H.eq("value: the second is the higher scoring one", hints.valuable[2].family, "life")

	-- Boosts only where the family is named.
	local lifeBoosts = ValueHint.boostsFor("life")
	H.check("value: life has a known boost", #lifeBoosts >= 1, tostring(#lifeBoosts))
	H.check("value: the boost names an action", (lifeBoosts[1].action or "") ~= "", tostring(lifeBoosts[1].action))
	H.check("value: the boost states its risk", (lifeBoosts[1].risk or "") ~= "", tostring(lifeBoosts[1].risk))
	H.eq("value: an unrelated family gets no boost", #ValueHint.boostsFor("gems"), 0)
	H.eq("value: an empty family gets no boost", #ValueHint.boostsFor(""), 0)

	-- A hint never invents a probability: the chance printed is the one handed in.
	H.eq("value: the chance is passed through", hints.valuable[2].chance, 0.12)

	-- A caller can raise the bar and silence almost everything.
	local strict = ValueHint.forWanted(wanted, { minBoost = 1.9 })
	H.eq("value: a strict threshold keeps only the best", #strict.valuable, 1)
	H.eq("value: and it is the life modifier", strict.valuable[1].family, "life")

	-- Degenerate inputs must not crash the card.
	local empty = ValueHint.forWanted(nil)
	H.eq("value: no input means nothing valuable", #empty.valuable, 0)
	H.eq("value: and no summary", ValueHint.summary(empty), nil)
	local junk = ValueHint.forWanted({ "not a table", 42 })
	H.eq("value: junk entries are ignored", #junk.valuable + #junk.others, 0)

	-- The sentence for the card, in both languages, and only when there is something to say.
	local ru = ValueHint.summary(hints, "ru")
	local en = ValueHint.summary(hints, "en")
	H.check("value: the Russian summary names the goal", ru and ru:find("цель", 1, true) ~= nil, tostring(ru))
	H.check("value: the Russian summary names the way to raise the chance", ru and ru:find("шанс", 1, true) ~= nil,
		tostring(ru))
	H.check("value: the English summary says chase", en and en:find("chase", 1, true) ~= nil, tostring(en))
end
