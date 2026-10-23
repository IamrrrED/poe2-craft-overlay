-- The runtime state file is not part of the sources, and nothing may depend on it existing.
--
-- craft_memory.lua used to be tracked, which meant every capture and every test run dirtied the tree, and a
-- commit could carry one player's item state into the repository. It is now gitignored and untracked, so the
-- engine has to work when the file is absent, empty, or full of garbage - all three are states a real
-- installation can be in after an update, a hand edit, or a crash mid-write.
return function()
	local H = require("Tests.harness")
	local Memory = require("Craft.Memory")

	-- Whatever is on disk now, the round trip has to work.
	local saved = Memory.save("v2|Helmets|Test|Base|80", { "+10 to Strength [10]" },
		{ currency = "Exalted Orb", index = 2, title = "Следующий шаг: Exalted Orb" })
	H.eq("memory: a save succeeds", saved, true)
	local loaded = Memory.load()
	H.check("memory: and loads back", type(loaded) == "table")
	if loaded then
		H.eq("memory: the fingerprint survives", loaded.fingerprint, "v2|Helmets|Test|Base|80")
		H.eq("memory: the step survives", loaded.step, "Exalted Orb")
		H.eq("memory: and its index", tonumber(loaded.stepIndex), 2)
	end

	-- The file says what it is, so a human who opens it does not mistake it for data.
	local file = io.open("craft_memory.lua", "r")
	if file then
		local head = file:read("*l") or ""
		file:close()
		H.check("memory: the file announces itself as generated",
			head:find("GENERATED", 1, true) ~= nil, head)
	end

	-- A cleared memory reads as nothing rather than as an empty table.
	Memory.clear()
	H.eq("memory: a cleared memory loads as nil", Memory.load(), nil)

	-- Garbage on disk must not raise: a half-written file is what a crash leaves behind.
	local broken = io.open("craft_memory.lua", "w")
	if broken then
		broken:write("this is not lua (((\n")
		broken:close()
	end
	H.eq("memory: a corrupt file loads as nil", Memory.load(), nil)

	-- And an empty file is not a memory either.
	local empty = io.open("craft_memory.lua", "w")
	if empty then
		empty:close()
	end
	H.eq("memory: an empty file loads as nil", Memory.load(), nil)

	-- Leave the file in the cleared state for whatever runs next.
	Memory.clear()
	H.eq("memory: the file is left cleared", Memory.load(), nil)
end
