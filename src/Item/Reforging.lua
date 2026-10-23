-- PoE2 Craft Overlay : Item/Reforging.lua
-- The Reforging Bench ("3-to-1"), as far as it can be decided from ONE item.
--
-- Two different jobs share the name and they answer different questions:
--   upgrade - three of the same family member become one of the next rung (runes, Liquid Emotions,
--             essences, catalysts);
--   recycle - three items of the same base and rarity become one of that base with fresh modifiers.
-- The bench needs three items, and the overlay sees one, so this module answers "would the bench take
-- this item, and what would come out of three of them" - never "you have three, go do it".

local Reforging = { }

--- May this item go into the Reforging Bench at all?
-- Corrupted and mirrored items cannot; a sanctified item can, which is the one place where sanctified
-- is not a full stop (every currency refuses it, the bench does not).
-- @param item parsed item
-- @return allowed boolean, reason string|nil
function Reforging.allows(item, ruleset)
	if type(item) ~= "table" then
		return false, "no item"
	end
	local rules = (ruleset or { }).reforging or { }
	local flags = item.flags or { }
	local refuses = rules.refuses or { corrupted = true, mirrored = true }
	if flags.corrupted and refuses.corrupted then
		return false, "corrupted"
	end
	if flags.mirrored and refuses.mirrored then
		return false, "mirrored"
	end
	if flags.sanctified and (rules.allows or { }).sanctified then
		return true, "sanctified"
	end
	return true, nil
end

--- The upgrade a family of three identical items produces, if the family has a ladder.
-- @param family one of the ruleset's upgrade family names ("runes", "liquidEmotions", ...)
-- @return detail string|nil
function Reforging.upgradeFor(family, ruleset)
	local rules = (ruleset or { }).reforging or { }
	for _, entry in ipairs(rules.upgradeFamilies or { }) do
		if entry.family == family then
			return entry.detail
		end
	end
	return nil
end

--- Does the bench upgrade this kind of item rather than reroll it?
-- Flasks and jewels and plain gear are recycled; runes, emotions, essences and catalysts are upgraded.
-- @param item parsed item
-- @return "upgrade" | "recycle" | nil
function Reforging.mode(item, ruleset)
	local rules = (ruleset or { }).reforging or { }
	local class = tostring(item and item.itemClass or ""):lower()
	if class == "" then
		return nil
	end
	local function has(needle) return class:find(needle, 1, true) ~= nil end
	if has("rune") or has("soul core") or has("idol") then
		return "upgrade", "runes"
	end
	if has("essence") then
		return "upgrade", "essences"
	end
	if has("catalyst") then
		return "upgrade", "catalysts"
	end
	for _, entry in ipairs(rules.recycleFamilies or { }) do
		if entry.family ~= "gear" and has(entry.family) then
			return "recycle", entry.family
		end
	end
	if has("flask") or has("charm") then
		return "recycle", "flasks"
	end
	if has("jewel") then
		return "recycle", "jewels"
	end
	-- Everything else that can hold modifiers is ordinary gear.
	if has("sword") or has("axe") or has("mace") or has("bow") or has("crossbow") or has("claw")
		or has("dagger") or has("spear") or has("staff") or has("stave") or has("wand")
		or has("sceptre") or has("scepter") or has("armour") or has("helmet") or has("gloves")
		or has("boots") or has("shield") or has("quiver") or has("ring") or has("amulet")
		or has("belt") or has("talisman") then
		return "recycle", "gear"
	end
	return nil
end

--- The one-paragraph reason to use the bench on this item, or nil when there is none.
--
-- The interesting case is a rare whose three modifiers are all taken: three of those can come back as
-- an unidentified rare with four modifiers, which is the only way the bench improves a rare rather
-- than just rerolling it.
-- @param item parsed item
-- @return text string|nil
function Reforging.whyFor(item, ruleset)
	local allowed, reason = Reforging.allows(item, ruleset)
	if not allowed then
		return nil, reason
	end
	local mode, family = Reforging.mode(item, ruleset)
	if not mode then
		return nil, nil
	end
	if mode == "upgrade" then
		local detail = Reforging.upgradeFor(family, ruleset)
		return detail or "Three of these combine into one of the next tier."
	end
	local rules = (ruleset or { }).reforging or { }
	local affixes = (item.prefixCount or 0) + (item.suffixCount or 0)
	if rules.upgradesThreeModRares and item.rarity == "RARE" and affixes >= 3 then
		return "Three rares with three modifiers each can come back as an unidentified rare with four: "
			.. "that is the only way the bench gives a rare MORE than it had, so it is worth it when the "
			.. "modifiers are not the ones you want."
	end
	return "Three items of the same base and rarity become one of that base with its modifiers rolled "
		.. "again - a way to reuse duplicates rather than a way to improve a good item."
end

return Reforging
