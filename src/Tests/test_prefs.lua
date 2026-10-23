-- PoE2 Craft Overlay : Tests/test_prefs.lua
-- Runtime preferences (the font the user picked) must survive a restart, so the
-- store is exercised through a real file - on a scratch path, never the live one.

local Prefs = require("Core.prefs")
local util = require("Core.util")

return function(H)
	local originalPath = Prefs.PATH
	Prefs.PATH = "test_prefs.lua"
	util.removeFile(Prefs.PATH)
	Prefs.reset()

	H.eq("prefs: missing file yields no value", Prefs.get("fontVariant"), nil)

	H.eq("prefs: set writes the file", Prefs.set("fontVariant", "segoe_semibold_13"), true)
	H.eq("prefs: file exists on disk", util.fileExists(Prefs.PATH), true)

	-- Simulate a restart: drop the cache and read the file again.
	Prefs.reset()
	H.eq("prefs: value survives a reload", Prefs.get("fontVariant"), "segoe_semibold_13")

	H.eq("prefs: booleans round-trip", Prefs.set("savedFlag", true), true)
	Prefs.reset()
	H.eq("prefs: boolean reloaded", Prefs.get("savedFlag"), true)

	H.eq("prefs: several keys coexist", Prefs.set("otherKey", 7), true)
	Prefs.reset()
	H.eq("prefs: numeric value reloaded", Prefs.get("otherKey"), 7)
	H.eq("prefs: earlier key still present", Prefs.get("fontVariant"), "segoe_semibold_13")

	local all = Prefs.all()
	H.eq("prefs: all() exposes the keys", type(all.fontVariant), "string")

	-- A corrupt file must not break startup.
	util.writeFile(Prefs.PATH, "this is not lua at all (((")
	Prefs.reset()
	H.eq("prefs: corrupt file is ignored", Prefs.get("fontVariant"), nil)

	util.removeFile(Prefs.PATH)
	Prefs.reset()
	Prefs.PATH = originalPath
end
