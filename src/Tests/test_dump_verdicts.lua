return function()
	local Memory = require("Craft.Memory")
	local before = { "+30 к Силе", "38% увеличение урона", "+190 к максимуму маны" }
	local cases = {
		{ "ничего не изменилось", before },
		{ "добавился мод", { "+30 к Силе", "38% увеличение урона", "+190 к максимуму маны", "+45% к сопротивлению огню" } },
		{ "потеряли мод", { "+30 к Силе", "38% увеличение урона" } },
		{ "замена один-к-одному", { "+30 к Силе", "38% увеличение урона", "+50 к максимуму маны" } },
	}
	local out = {}
	for _, case in ipairs(cases) do
		local changes = Memory.compare(before, case[2])
		local verdict
		if #changes.added == 0 and #changes.removed == 0 then verdict = "nothing"
		elseif #changes.added > #changes.removed then verdict = "progress"
		elseif #changes.removed > #changes.added then verdict = "loss"
		else verdict = "swap" end
		out[#out + 1] = case[1] .. " -> " .. verdict
			.. " добавлено " .. #changes.added .. ", убрано " .. #changes.removed
	end
	local file = io.open("app/data/verdicts-lua.txt", "w")
	if file then file:write(table.concat(out, "\n") .. "\n") file:close() end
	for _, line in ipairs(out) do print("lua: " .. line) end
	return true
end