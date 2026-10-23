-- PoE2 Craft Overlay : Tests/test_i18n.lua
-- The two things a Russian sentence needs from code, and that a translation tool cannot do by itself.
--
-- Why this file exists: the panel's Russian notes used to say "3 мод(ов) без тега могут быть имплиситами".
-- That is what a sentence looks like when the number is glued to a noun with a bracket, and a Russian
-- speaker sees it on the first screen. The noun (and often the verb) must agree with the number, so the
-- note entries are allowed to be functions and this file pins the forms.

local H = require("Tests.harness")
local i18n = require("Core.i18n")

return function(h)
	-- 1, 21, 31 take the singular; 2-4 and 22-24 the paucal; 0, 5-20, 25-30 the plural; 11-14 stay plural.
	local cases = {
		{ 1, "мод" }, { 2, "мода" }, { 4, "мода" }, { 5, "модов" }, { 0, "модов" },
		{ 11, "модов" }, { 12, "модов" }, { 14, "модов" }, { 21, "мод" }, { 22, "мода" },
		{ 25, "модов" }, { 101, "мод" }, { 111, "модов" }, { 112, "модов" },
	}
	for _, case in ipairs(cases) do
		local count, expected = case[1], case[2]
		local actual = i18n.plural(count, "мод", "мода", "модов")
		H.eq("i18n: " .. count .. " takes the right Russian form", actual, expected)
	end

	-- The note itself: the noun AND the verb agree, which a "%d мод(ов) ... могут" template cannot do.
	local one = i18n.note("suspected_implicit", { 1 }, "ru")
	local many = i18n.note("suspected_implicit", { 3 }, "ru")
	H.contains("i18n: one untagged modifier is singular", one, "1 мод без тега может быть имплиситом")
	H.contains("i18n: three untagged modifiers are paucal", many, "3 мода без тега могут быть имплиситами")
	H.check("i18n: no bracket-glued plural is left in the Russian note",
		not one:find("(ов)", 1, true) and not many:find("(ов)", 1, true), one .. " | " .. many)

	-- English keeps the plain template, so the same code path serves both languages.
	local english = i18n.note("suspected_implicit", { 3 }, "en")
	H.contains("i18n: the English note is unchanged", english, "3 untagged mod(s)")

	-- A note code with no translation at all must still read as a sentence, not as its own name.
	local fallback = i18n.note("no_name", nil, "en")
	H.eq("i18n: an untranslated code keeps its English sentence", fallback, "item name not found")

	-- Every Russian note must contain Cyrillic: an English sentence left in the ru column is the bug this
	-- whole exercise started with.
	local codes = { "empty_input", "no_rarity_header", "no_name", "no_base", "unparsed_property",
		"suspected_implicit", "low_item_level", "corrupted_check", "full_affixes", "no_rule",
		"pool_missing", "prefixes_full", "suffixes_full", "tier_estimated", "affix_split_unknown",
		"split_unknown_no_rule", "affix_split_inconsistent", "crafted_slot_taken" }
	local englishLeft = { }
	for _, code in ipairs(codes) do
		local text = i18n.note(code, { 2, "x", "y" }, "ru")
		if not text:find("[\208-\209][\128-\191]") then
			englishLeft[#englishLeft + 1] = code
		end
	end
	h.check("i18n: every note has Russian text", #englishLeft == 0, table.concat(englishLeft, ", "))
end
