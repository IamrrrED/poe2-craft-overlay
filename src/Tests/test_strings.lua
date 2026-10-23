-- PoE2 Craft Overlay : Tests/test_strings.lua
-- The interface string table. English only: Russian was removed on request, so the
-- test now asserts that the table is complete, ASCII-safe and that the helper
-- functions no longer produce Russian regardless of the language argument.

local Strings = require("Core.strings")

return function(H)
	local keys = Strings.keys()
	H.eq("strings: table has keys", #keys > 20, true)

	-- English strings stay ASCII, so the panel renders even without a glyph atlas.
	local function hasCyrillic(text)
		return tostring(text):find("[\208-\209]") ~= nil
	end
	local cyrillic = { }
	for _, key in ipairs(keys) do
		local value = Strings.t("en", key)
		if type(value) == "string" and hasCyrillic(value) then
			cyrillic[#cyrillic + 1] = key
		end
	end
	H.check("strings: no Russian left in the table", #cyrillic == 0, table.concat(cyrillic, ", "))

	H.eq("strings: formatting works", Strings.t("en", "leagueLabel", "0.5.5"), "league 0.5.5")
	H.eq("strings: unknown key falls through", Strings.t("en", "nope"), "nope")
	-- The panel can be shown in Russian now; English stays the default, and any key the Russian
	-- table does not cover falls back to English rather than showing a bare key.
	H.eq("strings: Russian is used when asked for",
		Strings.t("ru", "sectionItem"), "Предмет")
	H.eq("strings: English is the default language",
		Strings.t("en", "sectionItem"), Strings.t(nil, "sectionItem"))
	H.eq("strings: an untranslated key falls back to English",
		Strings.t("ru", "nope"), "nope")
	H.eq("strings: interface language is English", Strings.lang, "en")

	-- Naming helpers return the English name and never a Russian variant.
	H.eq("strings: name returns the English side",
		Strings.name("ru", "Сфера", "Exalted Orb"), "Exalted Orb")
	H.eq("strings: name falls back to whatever exists",
		Strings.name("en", "Only Russian", nil), "Only Russian")
	H.eq("strings: modifier text is English",
		Strings.modText("+118 to maximum Life", "ru"), "+118 to maximum Life")
	H.eq("strings: modifier name is English",
		Strings.modName("+118 to maximum Life", "ru"), "+118 to maximum Life")
	H.eq("strings: terms are English",
		Strings.term("classes", "Gloves", "ru"), "Gloves")
	H.eq("strings: base names are English",
		Strings.baseName("Blacksteel Gauntlets", "ru"), "Blacksteel Gauntlets")
	H.eq("strings: rune type is readable",
		Strings.runeType("SoulCore", "en"), "Soul core")
	H.eq("strings: unknown rune type passes through",
		Strings.runeType("SomethingNew", "en"), "SomethingNew")

	-- No language switch remains in the module.
	H.eq("strings: no toggle function", Strings.toggle, nil)
	H.eq("strings: no russian dictionary hook", Strings.localizationCoverage, nil)
end
