-- PoE2 Craft Overlay : Data/config.lua
-- User-editable settings. Read at startup; no code changes are needed to re-bind
-- hotkeys, change the overlay surface or point at another league file.

return {
	-- Which ruleset to load (module name under src/Data).
	leagueFile = "Data.league_0_5_5",

	hotkeys = {
		-- The one that matters in normal use: hover the item in game, press Ctrl+Q, and the
		-- local site opens with the crafting options for it. Same idea as the price-check
		-- hotkey in Sidekick or Exiled Exchange 2, except the answer appears in a browser
		-- where all the numbers fit, and the item is read from a picture of the tooltip.
		grabImage = "CTRL+Q",
		capture = "F6",     -- capture via the clipboard (send Ctrl+C, then read it)
		togglePanel = "F7", -- show/hide the panel (only used when ui.panel is true)
		clear = "F8",       -- clear the result
		demo = "F5",        -- analyse the demo item from samples/
		interactive = "F9", -- clickable window (for dragging) / back to overlay mode
		reapply = "F11",    -- re-apply the overlay styling
		quit = "F10",       -- exit
		-- Block folding: the panel should not cover half the screen.
		detail = "F1",      -- detail level: compact -> normal -> detailed
		toggleItem = "F2",  -- item block (including modifier tiers)
		togglePlans = "F3", -- MIN/MAX plan block
		toggleOmens = "F4", -- league crafting methods block
		toggleNotes = "F6", -- notes block (with the modifier below)
		toggleMods = "F9",  -- modifier tiers only (with the modifier below)
		-- Live font preview: hold the modifier and step through the glyph atlases.
		fontModifier = "CTRL",
		fontNext = "F1",      -- Ctrl+F1 next font
		fontPrev = "F2",      -- Ctrl+F2 previous font
		fontSave = "F3",      -- Ctrl+F3 save font, size and spacing
		textSmaller = "F4",   -- Ctrl+F4 smaller panel text
		textLarger = "F5",    -- Ctrl+F5 larger panel text
		letterTighter = "F7", -- Ctrl+F7 tighter letter spacing
		letterLooser = "F8",  -- Ctrl+F8 looser letter spacing
	},

	capture = {
		-- true  = the overlay sends Ctrl+C to the game itself (like Awakened PoE Trade)
		-- false = you copy the item yourself and the overlay only reads the clipboard
		sendCtrlC = true,
		-- Delay between Ctrl+C and reading the clipboard, milliseconds.
		ctrlCDelayMs = 180,
		-- Game processes whose window is a valid target for Ctrl+C.
		windowImageNames = { "PathOfExile2.exe", "PathOfExile.exe", "PathOfExileSteam.exe" },
		-- Image capture (the Ctrl+Q path): a picture of the tooltip is taken around the
		-- cursor and read with the OCR engine built into Windows - no game hooks, no
		-- network, nothing sent anywhere.
		grabScript = "tools\\grab_item.ps1",
		grabScale = 2,
		-- Region relative to the cursor, where the game draws the tooltip.
		imageRegion = { width = 660, height = 800, offsetX = 24, offsetY = -60 },
		-- Fewer characters than this means the reading failed, and the overlay falls back
		-- to the clipboard so a hotkey press is never a dead end.
		minOcrChars = 20,
	},

	-- The local crafting site (web/server.js): capture an item in game and read the whole
	-- analysis in the browser, where there is room to show every number comfortably.
	web = {
		enabled = true,
		host = "127.0.0.1",
		port = 17427,
		-- Start the site automatically the first time an item is captured.
		autoStart = true,
		-- Open (or bring to the front) the page in the default browser.
		openBrowser = true,
	},

	overlay = {
		-- The panel is on: it draws the analysis itself, over the game, and no browser or site
		-- server takes part. The engine both computes and shows, which is the whole point of
		-- this mode - one process, one window, nothing to reload.
		enabled = true,
		-- System-tray icon for the agent: no panel, no taskbar button, one icon whose menu
		-- opens the site, captures an item, or quits.
		tray = true,
		-- Uniform window opacity: 255/255 = fully opaque, so the panel is a solid surface that
		-- the game never shows through. Lower it (204 was 0.8) to make the panel translucent.
		alpha = 255,
		clickThrough = true,
		topmost = true,
		width = 700,
		-- Initial height; the panel then auto-fits its content up to maxHeight.
		height = 520,
		maxHeight = 1400,
		marginRight = 24,
		marginTop = 60,
		-- The panel is centred on screen, keeping this many pixels away from the edges.
		marginCenter = 8,
		-- Height of the window chrome: the host gives the drawing area less than the
		-- requested window height, so the window is asked for more than the panel needs.
		chromePad = 40,
		autoPosition = true,
		-- The overlay's own window must be identified by (exact title, host image) so
		-- styling or quitting can never target a foreign process.
		hostImage = "Building-PoE2.exe",
		-- The host keeps its window at full render-surface size, so everything the panel
		-- does not cover is erased to this colour and then made transparent and
		-- click-through through the layered-window colour key.
		-- Set to nil to fall back to a plain dark background rectangle.
		keyColor = { r = 255, g = 0, b = 255 },
	},

	ui = {
		-- Glyph atlas to use (Data/fonts/<id>.lua); the manifest Data/fonts.lua lists
		-- every variant. Fontin is the typeface Path of Exile and Sidekick use; the font
		-- file is taken from assets/fonts or from the Sidekick installation.
		-- Other sizes: fontin_regular_16/14/13, fontin_bold_15/14.
		fontVariant = "fontin_regular_15",
		-- Panel text scale (0.70 ... 1.60), changed live with Ctrl+F4 / Ctrl+F5.
		textScale = 1.0,
		-- Letter spacing: 1.0 is the font's own advance, lower is tighter.
		-- nil = keep the value baked into the atlas. Ctrl+F7 tighter, Ctrl+F8 looser.
		letterSpacing = 0.94,
		-- Shortlist used by the comparison mode (src/font_shortlist.flag).
		fontShortlist = {
			"fontin_regular_16", "fontin_regular_15", "fontin_regular_14", "fontin_regular_13",
			"verdana_13", "verdana_12", "tahoma_13", "cascadia_mono_13",
		},
		-- 1 = step names only, 2 = + short description and best chance,
		-- 3 = + tips, warnings and the full chance list.
		detailLevel = 2,
		-- Which blocks start folded (see Core/view.lua).
		sections = {
			modTiers = true,
			omens = false,
			notes = true,
		},
		rowHeight = 20,
		font = "VAR",
		fontBold = "VAR BOLD",
		-- Panel surface: the warm near-black of Path of Exile 2's item tooltip. Solid, not
		-- translucent - a washed-out panel over a bright game scene was the readability
		-- problem, and this palette is documented by the community overlay at
		-- github.com/andre-lund/poe2-overlay (its DESIGN.md).
		background = { 0.047, 0.039, 0.027, 1 },
		-- Currency prices from Craft of Exile (Data/prices.lua) are shown next to the
		-- step costs only when the snapshot's league matches the one being played.
		-- nil = strict match against the ruleset league, true = accept any league,
		-- or a string to match a specific league name.
		pricesLeague = nil,
		-- 1px bronze frame around the panel so the surface reads as a distinct window.
		border = { 0.341, 0.290, 0.173, 1 },
		text = { 0.839, 0.796, 0.698, 1 },
		dim = { 0.604, 0.553, 0.439, 1 },
		gold = { 0.784, 0.667, 0.427, 1 },
		goldBright = { 0.910, 0.835, 0.627, 1 },
		good = { 0.561, 0.890, 0.627, 1 },
		warn = { 0.910, 0.788, 0.541, 1 },
		bad = { 1.0, 0.561, 0.490, 1 },
		-- Modifier text uses the game's magic-mod blue, which is how a real tooltip
		-- separates modifiers from item fields.
		magic = { 0.659, 0.659, 0.973, 1 },
		-- Item names carry the rarity colour, exactly as in game.
		rarity = {
			normal = { 0.784, 0.784, 0.784, 1 },
			magic = { 0.533, 0.533, 1.0, 1 },
			rare = { 1.0, 1.0, 0.467, 1 },
			unique = { 0.686, 0.376, 0.145, 1 },
			currency = { 0.667, 0.620, 0.510, 1 },
		},
	},

	-- Path (relative to src/) of the demo item used by the demo hotkey.
	demoItemPath = "../samples/rare_gloves.txt",
	-- Diagnostics file, relative to src/.
	sessionLogPath = "session.log",
}
