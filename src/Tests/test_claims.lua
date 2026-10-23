-- Checking claims against the data, which is what protects a beginner from fabricated guides.
--
-- docs/mentor-research.md documents the finding: an "ultimate beginner guide" that ranks well in search
-- teaches mechanics PoE 2 does not have - a resonant anvil, an echoing chisel, an Orb of Scouring, "Regal
-- locks your prefix". A beginner cannot tell that from a real guide, and every wrong claim costs currency.
return function()
	local H = require("Tests.harness")
	local Claims = require("Craft.Claims")
	local Api = require("Mcp.api")

	-- Every claim is well formed: an id, a verdict, a title, an explanation and a source.
	local list = Claims.list()
	H.check("claims: the list is not empty", #list >= 8, tostring(#list))
	local seenIds = { }
	for _, claim in ipairs(list) do
		H.check("claims: an entry has an id", type(claim.id) == "string" and claim.id ~= "")
		H.eq("claims: the id is unique (" .. tostring(claim.id) .. ")", seenIds[claim.id], nil)
		seenIds[claim.id] = true
		H.check("claims: it states a verdict (" .. tostring(claim.id) .. ")",
			claim.verdict == "true" or claim.verdict == "false", tostring(claim.verdict))
		H.check("claims: it has a title (" .. tostring(claim.id) .. ")",
			type(claim.title) == "string" and #claim.title > 10)
		H.check("claims: it explains itself (" .. tostring(claim.id) .. ")",
			type(claim.why) == "string" and #claim.why > 40)
		H.check("claims: it names where it comes from (" .. tostring(claim.id) .. ")",
			type(claim.source) == "string" and #claim.source > 10)
		H.check("claims: it can be matched (" .. tostring(claim.id) .. ")",
			type(claim.matches) == "table" and #claim.matches > 0)
	end

	-- The fabrications from that guide are recognised as false, in the words a player would actually use.
	local FALSE_QUESTIONS = {
		{ "Орб Скуринга снимает все суффиксы", "scouring_orb" },
		{ "Regal фиксирует префикс", "regal_locks_prefix" },
		{ "Chaos перекатывает весь предмет", "chaos_rerolls_all" },
		{ "можно поставить два created-мода", "essence_twice" },
		{ "Vaal обратим", "vaal_reversible" },
		{ "Качество занимает слот", "quality_free_slot" },
		{ "Divine меняет моды", "divine_changes_mods" },
	}
	for _, case in ipairs(FALSE_QUESTIONS) do
		local answer = Claims.answer(case[1])
		H.eq("claims: recognised - " .. case[1], answer.id, case[2])
		H.eq("claims: and marked false - " .. case[1], answer.verdict, "false")
		H.check("claims: with the reason - " .. case[1],
			type(answer.why) == "string" and #answer.why > 40)
	end

	-- True claims are recognised as true, so the checker is not simply saying "no" to everything.
	local exalted = Claims.answer("Exalted безопасно добавлять?")
	H.eq("claims: a true claim is marked true", exalted.verdict, "true")
	H.eq("claims: and named", exalted.id, "exalted_safe")

	-- Case folding must work for Cyrillic: this Lua build lower-cases ASCII only, and the first version of
	-- the checker answered "not in my list" for a capitalised Russian question it knew the answer to.
	H.eq("claims: a capitalised Russian question is recognised",
		(Claims.answer("ПРАВДА ЛИ, ЧТО РЕГАЛ ФИКСИРУЕТ ПРЕФИКС?") or { }).id, "regal_locks_prefix")

	-- A question nobody wrote a rule for is not guessed at: the answer says so instead of inventing one.
	local unknown = Claims.answer("Сколько стоит божественная сфера завтра?")
	H.eq("claims: an unknown question is not answered", unknown.known, false)
	H.check("claims: and the refusal explains itself",
		type(unknown.why) == "string" and #unknown.why > 40)
	H.eq("claims: empty input is not a claim", Claims.find(""), nil)
	H.eq("claims: no input is not a claim", Claims.find(nil), nil)

	-- The verifiers: where our own ruleset can settle a claim, it does. This is what keeps the anti-fabrication
	-- feature from being one person's opinion - and it caught its own inversion, because the first version
	-- compared `holds` against the verdict and reported every trap as a failure.
	local league = require("Data.league_0_5_5")
	local verified = Claims.verifyAll(league)
	H.check("claims: the ruleset settles several claims", verified.checked >= 8, tostring(verified.checked))
	H.check("claims: and none of them contradict the data", #verified.failed == 0,
		("failed: " .. table.concat((function()
			local names = { }
			for _, fail in ipairs(verified.failed) do names[#names + 1] = tostring(fail.id) end
			return names
		end)(), ", ")))
	-- A claim that the data can settle says so, so the panel can show "checked against the data".
	local scouring = Claims.answer("Орб Скуринга снимает все суффиксы")
	H.eq("claims: a data-checked claim is marked verified", scouring.verified, true)
	-- And the one the data cannot settle must NOT claim to be checked. The "one created modifier" rule has no
	-- row in the ruleset to read; an earlier verifier returned true unconditionally, which made the panel print
	-- "verified against the data" for a rule the data never looked at.
	local essence = Claims.answer("Можно ли поставить два created-мода?")
	H.check("claims: the created-slot claim is not faked as verified", essence.verified ~= true,
		tostring(essence.verified))
	-- The rule is still real, it is just enforced by the engine rather than by a data row, so that is checked
	-- where it lives: an item that already carries a created modifier must produce the warning.
	local Coach = require("Craft.Coach")
	local Parser = require("Item.Parser")
	local Mods = require("Item.Mods")
	local CRAFTED = table.concat({
		"Item Class: Helmets", "Rarity: Rare", "Crafted Helm", "Charming Tiara", "--------",
		"Item Level: 80", "--------",
		'{ Prefix Modifier "Charmed" (Tier: 2) }', "37% increased Energy Shield",
		'{ Suffix Modifier "of the Craft" (Tier: 1) }', "+15% to Fire Resistance (crafted)",
	}, "\n")
	local craftedItem = Parser.parse(CRAFTED)
	Mods.annotate(craftedItem)
	local craftedState = Coach.state(craftedItem, CRAFTED)
	H.eq("claims: the engine sees a created modifier already present",
		craftedState.craftedAnchorUsed, true)
	local warnings = Coach.warnings(craftedItem, CRAFTED, craftedState)
	local sawCraftedWarning = false
	for _, warning in ipairs(warnings or { }) do
		local text = type(warning) == "table" and (warning.text or warning.id) or tostring(warning)
		if tostring(text):find("crafted", 1, true) or tostring(text):find("Созданный", 1, true) then
			sawCraftedWarning = true
		end
	end
	H.check("claims: and warns that a second will not fit", sawCraftedWarning,
		tostring(#(warnings or { })))
	-- A verifier must actually depend on the data: break the chaos record and the claim stops agreeing.
	local broken = { currencies = { chaos = { en = "Chaos Orb", adds = 9, removes = 9 } } }
	local brokenResult = Claims.verifyAll(broken)
	H.check("claims: a wrong ruleset fails the check", #brokenResult.failed > 0,
		tostring(#brokenResult.failed))
	local sawChaos = false
	for _, fail in ipairs(brokenResult.failed) do
		if fail.id == "chaos_rerolls_all" then sawChaos = true end
	end
	H.eq("claims: and the chaos claim is the one that fails", sawChaos, true)

	-- The API exposes it, because the panel asks through the same engine.
	local viaApi = assert(Api.call("check_claim", { text = "Vaal обратим?" }))
	H.eq("claims: the API answers", viaApi.known, true)
	H.eq("claims: and the verdict travels", viaApi.verdict, "false")
	local all = assert(Api.call("claims", { }))
	H.eq("claims: the API lists them all", #(all.claims or { }), #list)
	local noText, noTextError = Api.call("check_claim", { })
	H.eq("claims: a missing question is rejected", noText, nil)
	H.check("claims: with an error message", type(noTextError) == "string", tostring(noTextError))
end
