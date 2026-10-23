-- The Genesis Tree passives that change what a womb produces, and the fact that they reach the panel.
--
-- Catalysts come only from this tree since 0.5.0, so "which node do I take" is a real crafting question. The
-- full tree is dozens of passives per womb and a dump would be unreadable, so the data is an explicit SUBSET:
-- the nodes that change a decision, with the source and a note saying it is a subset. Passives are freely
-- refundable, which is why nothing here is described as permanent.
return function()
	local H = require("Tests.harness")
	local Api = require("Mcp.api")
	local league = require("Data.league_0_5_5")

	local tree = league.genesisTree
	H.check("genesis: the tree block exists", type(tree) == "table")
	H.check("genesis: it names its source", type(tree.wombPassivesSource) == "string"
		and tree.wombPassivesSource:find("poewiki", 1, true) ~= nil, tostring(tree.wombPassivesSource))

	local wombs = tree.wombPassives or { }
	H.check("genesis: the passives are grouped by womb", #wombs >= 3, tostring(#wombs))

	local byWomb = { }
	for _, group in ipairs(wombs) do
		byWomb[group.womb] = group.nodes or { }
	end
	H.check("genesis: the equipment womb is described", byWomb.equipment ~= nil)
	H.check("genesis: the currency womb is described", byWomb.currency ~= nil)

	-- Each node needs both languages, or the Russian panel shows half a block in English.
	local missing = { }
	local count = 0
	for womb, nodes in pairs(byWomb) do
		for _, node in ipairs(nodes) do
			count = count + 1
			if type(node.name) ~= "string" or node.name == ""
				or type(node.effectEn) ~= "string" or node.effectEn == ""
				or type(node.effectRu) ~= "string" or node.effectRu == "" then
				missing[#missing + 1] = womb .. ":" .. tostring(node.name)
			end
		end
	end
	H.eq("genesis: every passive has a name and both explanations", #missing, 0)
	H.check("genesis: the subset is not empty", count >= 10, tostring(count))

	-- The nodes a crafter actually weighs.
	local function has(womb, needle)
		for _, node in ipairs(byWomb[womb] or { }) do
			if tostring(node.name) == needle then return true end
		end
		return false
	end
	H.eq("genesis: fractured chance is documented", has("equipment", "Solid Cysts"), true)
	H.eq("genesis: value rerolls are documented", has("equipment", "Divine Rolls"), true)
	H.eq("genesis: tier rating is documented", has("equipment", "Modifier Tier Rating"), true)

	-- And they must reach the player, not just the data file.
	local guide = assert(Api.call("crafting_guide", { }))
	local exposed = guide.genesisTree
	H.check("genesis: the guide carries the tree", type(exposed) == "table")
	if type(exposed) == "table" then
		H.check("genesis: with the passives inside", #(exposed.wombPassives or { }) >= 3,
			tostring(#(exposed.wombPassives or { })))
	end
end
