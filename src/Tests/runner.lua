-- PoE2 Craft Overlay : Tests/runner.lua
-- Headless test entry point. Called by Launch.lua in test mode, so the tests run
-- on the exact LuaJIT build the overlay ships with.

local H = require("Tests.harness")

local MODULES = {
	-- Exports the crafting data to JSON for the Electron overlay; runs first so the files exist.
	"Tests.test_dump_data",
	"Tests.test_dump_odds",
	"Tests.test_dump_mcp",
	"Tests.test_dump_verdicts",
	"Tests.test_parser",
	"Tests.test_mods",
	"Tests.test_lines",
	"Tests.test_capture",
	"Tests.test_guide",
	"Tests.test_coach",
	"Tests.test_coach_cost",
	"Tests.test_coach_live",
	"Tests.test_memory",
	"Tests.test_coach_loop",
	"Tests.test_font",
	"Tests.test_strings",
	"Tests.test_view",
	"Tests.test_prefs",
	"Tests.test_advisor",
	"Tests.test_omens",
	"Tests.test_essences",
	"Tests.test_runes",
	"Tests.test_reforging",
	"Tests.test_mcp",
	"Tests.test_reveal",
	"Tests.test_prices",
	"Tests.test_ru",
	"Tests.test_out_ru",
	"Tests.test_categories",
	"Tests.test_ocr",
	"Tests.test_quality_memory",
	"Tests.test_order",
	"Tests.test_stage_switch",
	"Tests.test_stage",
	"Tests.test_lesson",
	"Tests.test_claims",
	"Tests.test_homogenising",
	"Tests.test_techniques",
	"Tests.test_curriculum",
	"Tests.test_craft_or_buy_price",
	"Tests.test_craft_or_buy",
	"Tests.test_base_quality",
	"Tests.test_genesis_passives",
	"Tests.test_rare_full_warning",
	"Tests.test_language_ru",
	"Tests.test_magic_full_wand",
	"Tests.test_real_amulet",
	"Tests.test_second_source",
	"Tests.test_genesis_advisor",
	"Tests.test_genesis_tree",
	"Tests.test_memory_state",
	"Tests.test_poe2db_closed",
	"Tests.test_poe2db_gaps",
	"Tests.test_quality_cap",
	"Tests.test_audit_fixes",
	"Tests.test_created_slot",
	"Tests.test_mentor",
	"Tests.test_recipes",
	"Tests.test_mod_pool",
	"Tests.test_stash_tabs",
	"Tests.test_annotation_split",
	"Tests.test_language",
	"Tests.test_language_prose",
	"Tests.test_data_files",
	"Tests.test_i18n",
	"Tests.test_language_corpus",
}

--- Compile the engine's own source files, so a syntax error fails the tests instead of the engine.
--
-- A stray comment marker in Advisor.lua left the overlay unable to start at all: the host printed
-- "unexpected symbol" on a runtime console and then died with an access violation, and the test run
-- produced no report at all. The files below are the ones the panel loads first, and compiling them
-- here turns that into an ordinary failing assertion naming the file and the line. The host's working
-- directory IS src/, so these paths are relative to it.
local ENGINE_FILES = {
	"Craft/Advisor.lua", "Craft/Coach.lua", "Craft/Memory.lua",
	"Craft/Stage.lua", "Craft/Lesson.lua", "Craft/Claims.lua", "Craft/Techniques.lua",
	"Craft/Curriculum.lua", "Craft/CraftOrBuy.lua", "Craft/GenesisTree.lua",
	"Item/Parser.lua", "Item/Mods.lua", "Item/Lines.lua", "Item/Runes.lua", "Item/Reforging.lua",
	"Data/league_0_5_5.lua", "Core/strings.lua", "Core/i18n.lua",
}

local function checkEngineSyntax(h)
	local problems, checked = { }, 0
	for _, path in ipairs(ENGINE_FILES) do
		local file = io.open(path, "rb")
		if file then
			local text = file:read("*a")
			file:close()
			checked = checked + 1
			local chunk, err = loadstring(text, path)
			if not chunk then
				problems[#problems + 1] = tostring(err)
			end
		else
			problems[#problems + 1] = "cannot open " .. path
		end
	end
	-- A silent zero would pass for a clean run, so the count is part of the assertion.
	h.check("syntax: the engine's own files compile (" .. checked .. "/" .. #ENGINE_FILES .. ")",
		#problems == 0 and checked == #ENGINE_FILES, table.concat(problems, " | "))
end

--- Run every registered test module.
-- @return passed, failed, report string
function H.runAll()
	-- Compiled first: a syntax error in one of these is what stops the overlay from starting at all.
	local okSyntax, syntaxError = pcall(checkEngineSyntax, H)
	if not okSyntax then
		H.check("syntax: the engine file check ran", false, tostring(syntaxError))
	end
	for _, name in ipairs(MODULES) do
		local ok, fn = pcall(require, name)
		if not ok then
			H.check("loading module " .. name, false, tostring(fn))
		elseif type(fn) ~= "function" then
			H.check("module " .. name .. " returns a function", false, type(fn))
		else
			local okRun, err = pcall(fn, H)
			if not okRun then
				H.check("running " .. name, false, tostring(err))
			end
		end
	end
	return H.summary()
end

return H

























































