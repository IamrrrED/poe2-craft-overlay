-- The coach must receive the advisor's plans. This test runs the real call inside the engine and
-- writes down what actually arrives, so the shape of the answer is a fact rather than an assumption.
return function()
	local H = require("Tests.harness")
	local Api = require("Mcp.api")
	local Coach = require("Craft.Coach")
	local Parser = require("Item.Parser")
	local util = require("Core.util")

	local raw = util.readFile("samples/rare_gloves.txt") or util.readFile("../samples/rare_gloves.txt")
	H.eq("coach-live: the sample is readable", type(raw), "string")
	if type(raw) ~= "string" then
		return
	end

	local advice = select(1, Api.call("analyze_item", { item_text = raw }))
	local diary = { }
	diary[#diary + 1] = "advice type: " .. type(advice)
	if type(advice) == "table" then
		local keys = { }
		for key in pairs(advice) do keys[#keys + 1] = key end
		table.sort(keys)
		diary[#diary + 1] = "advice keys: " .. table.concat(keys, ", ")
		local plans = advice.plans
		diary[#diary + 1] = "plans type: " .. type(plans) .. ", count: " .. tostring(#(plans or { }))
		if type(plans) == "table" then
			for index, plan in ipairs(plans) do
				if index > 2 then break end
				local planKeys = { }
				for key in pairs(plan) do planKeys[#planKeys + 1] = key end
				table.sort(planKeys)
				diary[#diary + 1] = "plan " .. index .. " keys: " .. table.concat(planKeys, ", ")
				local steps = plan.steps or { }
				diary[#diary + 1] = "  steps: " .. tostring(#steps)
				for stepIndex, step in ipairs(steps) do
					if stepIndex > 2 then break end
					local stepKeys = { }
					for key in pairs(step) do stepKeys[#stepKeys + 1] = key end
					table.sort(stepKeys)
					diary[#diary + 1] = "  step " .. stepIndex .. " keys: " .. table.concat(stepKeys, ", ")
					diary[#diary + 1] = "  step " .. stepIndex .. " en: " .. tostring(step.en)
					diary[#diary + 1] = "  step " .. stepIndex .. " currency: " .. tostring(step.currency)
				end
			end
		end
	end

	local item = Parser.parse(raw)
	local itemKeys = { }
	for key in pairs(item or { }) do itemKeys[#itemKeys + 1] = key end
	table.sort(itemKeys)
	diary[#diary + 1] = "item keys: " .. table.concat(itemKeys, ", ")
	diary[#diary + 1] = "item.affixes: " .. tostring(item.affixes)
	diary[#diary + 1] = "item.explicits: " .. tostring(item.explicits)

	local report = Coach.report(item, advice or { }, raw)
	diary[#diary + 1] = "coach step title: " .. tostring(report.step.title)
	diary[#diary + 1] = "coach open slots: " .. tostring(report.state.openSlots) .. " (P " .. tostring(report.state.openPrefixes) .. " / S " .. tostring(report.state.openSuffixes) .. ")"

	local file = io.open("coach_diag.txt", "w")
	if file then
		file:write(table.concat(diary, "\n") .. "\n")
		file:close()
	end

	H.eq("coach-live: the advisor answers with a table", type(advice), "table")
end