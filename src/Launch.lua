#@ SimpleGraphic
-- PoE2 Craft Overlay : Launch.lua
-- Entry point. Runs on the Path of Building runtime (SimpleGraphic + LuaJIT x64);
-- see README.md for how that runtime is staged and why it is used.
--
-- Modes, selected by marker files in the working directory (src/):
--   run_tests.flag    -> headless self-test: writes test_results.txt + test_done.flag
--   render_check.flag -> normal UI, analyses the demo item, screenshots, then quits
--   (neither)         -> normal overlay session
--
-- Two host quirks drive the structure of this file:
--   1. RenderInit() must run before any renderer query (GetScreenSize before it
--      hard-crashes the process), and before any ConPrintf output.
--   2. Exit() shuts the engine down but does NOT terminate the process, and from
--      OnInit it is ignored entirely - so quitting is done explicitly (quitSelf).
--
-- Text: the host's bitmap fonts carry no Cyrillic glyphs, so everything drawn on
-- screen is ASCII. Russian text goes to the log, the console dump and
-- last_advice.txt, which are plain UTF-8 files.

APP_NAME = "PoE2 Craft Overlay"
SetWindowTitle(APP_NAME)
-- The window mode has to be set before the host creates its window. Without these lines the
-- default is CFG_VID_DEFMODE "-1" (see SimpleGraphic/config.h), the window is created with no
-- proper mode and briefly appears at launch - the dark flash. Path of Building sets the same
-- values as its very first statements, and this file is a copy of its launcher.
ConExecute("set vid_mode 8")
ConExecute("set vid_resizable 3")
-- Keep the host's video window off screen. The setting is archived, so the host reads it before it
-- first applies video settings, and Apply() only shows the window when it is non-zero. Without it
-- the engine's GLFW window appears on screen for a moment at every start - the flash.
ConExecute("set vid_shown 0")

-- Module resolution relative to src/ (the engine sets the work dir there).
package.path = package.path .. ";./?.lua;./?/init.lua"

local function rawWrite(path, data)
	local f = io.open(path, "wb")
	if f then
		f:write(data)
		f:close()
		return true
	end
	return false
end

--- Compile the engine's own source files and report a syntax error instead of dying on it.
--
-- This runs BEFORE any module is required, and only in test mode, because a syntax error otherwise takes
-- the whole process down: the host prints "unexpected symbol" on a console this project cannot read and
-- then dies with an access violation, and the test run produces no report at all - which happened when a
-- comment was written with the wrong marker in Advisor.lua. Reading and compiling each file here turns
-- that into an ordinary failing test that names the file and the line.
-- @return report string, or nil when every file compiles
local function checkEngineSyntax()
	local files = {
		"Craft/Advisor.lua", "Craft/Coach.lua", "Craft/Memory.lua",
		"Craft/Stage.lua", "Craft/Lesson.lua", "Craft/Claims.lua", "Craft/Techniques.lua",
		"Craft/Curriculum.lua", "Craft/CraftOrBuy.lua", "Craft/GenesisTree.lua",
		"Item/Parser.lua", "Item/Mods.lua", "Item/Lines.lua", "Item/Runes.lua", "Item/Reforging.lua",
		"Data/league_0_5_5.lua", "Core/strings.lua", "Core/i18n.lua",
	}
	local problems = { }
	for _, path in ipairs(files) do
		local f = io.open(path, "rb")
		if f then
			local text = f:read("*a")
			f:close()
			local chunk, err = loadstring(text, path)
			if not chunk then
				problems[#problems + 1] = tostring(err)
			end
		else
			problems[#problems + 1] = "cannot open " .. path
		end
	end
	if #problems == 0 then
		return nil
	end
	return table.concat(problems, " | ")
end

-- In test mode the syntax check runs HERE, before the first module is required: a module that fails to
-- compile takes the rest of this file with it, and then even the failing report is never written. The
-- flag is read directly rather than through Core.util, which is itself a module.
do
	local flag = io.open("run_tests.flag", "rb")
	if flag then
		flag:close()
		local syntaxProblem = checkEngineSyntax()
		if syntaxProblem then
			rawWrite("test_results.txt",
				"syn: the engine's own files compile - FAILED\n  " .. syntaxProblem
				.. "\n\nRESULT: passed=0 failed=1\n")
			rawWrite("test_done.flag", "failed=1\n")
			return
		end
	end
end

--------------------------------------------------------------------------------
-- Bootstrap: load modules, recording any failure instead of dying silently
--------------------------------------------------------------------------------

local util, Parser, Advisor, Win32, i18n, Font, Strings, View, Prefs, Prices, Ocr, Tray, config, ruleset
local bootError = nil

do
	local ok, err = pcall(function()
		util = require("Core.util")
		i18n = require("Core.i18n")
		Font = require("Core.font")
		Strings = require("Core.strings")
		View = require("Core.view")
		Prices = require("Craft.Prices")
		Ocr = require("Item.Ocr")
		Tray = require("Core.tray")
		Prefs = require("Core.prefs")
		Parser = require("Item.Parser")
		Advisor = require("Craft.Advisor")
		Lines = require("Item.Lines")
Ru = require("Item.Ru")
Win32 = require("Core.win32")
		config = require("Data.config")
		ruleset = require(config.leagueFile)
	end)
	if not ok then
		bootError = tostring(err)
		rawWrite("boot_error.txt", "module load failed:\n" .. bootError .. "\n")
	end
end

local state = {
	frame = 0,
	advice = nil,
	-- Bumped whenever the advice changes, so the rendered rows can be cached and the
	-- panel stops rebuilding (and re-wrapping) its text on every single frame.
	adviceRev = 0,
	status = "Hover an item in game and press " .. "F6",
	statusColor = { 0.65, 0.65, 0.65, 1 },
	panelVisible = true,
	pendingCaptureAt = nil,
	interactive = false,
	hwnd = nil,
	detailLevel = 2,
	textScale = 1,
	sections = nil,
	screenW = nil,
	screenH = nil,
	rowsCacheKey = nil,
	rowsCache = nil,
	testMode = false,
	renderCheck = false,
	fontProbe = false,
	fontCompare = false,
	fontShortlist = false,
	-- How long a probe mode keeps its window on screen, in milliseconds (real time,
	-- because the host runs at a few hundred frames per second, not at 60).
	holdMs = 5000,
	holdStart = nil,
	errorReported = false,
	quitting = false,
}

local app = { }
SetMainObject(app)

local keyPrev = { }

local function logLine(text)
	local f = io.open(config.sessionLogPath, "a")
	if f then
		f:write(string.format("[%d] %s\n", GetTime(), text))
		f:close()
	end
end

local function printf(...)
	pcall(ConPrintf, ...)
end

--- Interface string in the active language.
local function L(key, ...)
	return Strings.t(Strings.lang, key, ...)
end

-- Render surface scale: the host scales font sizes by the display DPI, so every
-- layout number (row advance, panel box, wrap width) has to be scaled as well -
-- otherwise rows overlap, as seen in the first render check.
local uiScale = 1
local function px(value)
	return value * uiScale
end

--- Trace helper used only by the headless test mode (the frame loop is not
-- guaranteed to run there, so progress is recorded on disk).
local function trace(msg)
	if not state.testMode then return end
	local f = io.open("test_trace.txt", "a")
	if f then
		f:write(string.format("%d %s\n", GetTime(), msg))
		f:close()
	end
end

--- Edge-triggered global hotkey check (works while the game holds focus).
-- @param name key name from Win32.VK
-- @param modifier optional modifier ("CTRL", "SHIFT", "ALT") that must be held; chords
--        are used for the font preview so the plain F-keys keep their meaning.
local function hotkeyPressed(name, modifier)	local vk = Win32.VK[name]
	if not vk then return false end
	local cacheKey = name .. "/" .. tostring(modifier or "")
	local down = Win32.isKeyDown(vk)
	if modifier then
		local modifierVk = Win32.VK[modifier]
		if not modifierVk or not Win32.isKeyDown(modifierVk) then
			-- Modifier not held: swallow the edge so it cannot fire later.
			keyPrev[cacheKey] = down
			return false
		end
	end
	local was = keyPrev[cacheKey]
	keyPrev[cacheKey] = down
	return down and not was
end

--- Report a runtime failure once, to disk, to the session log and to the console.
local function reportError(where, err)
	if state.errorReported then return end
	state.errorReported = true
	local text = string.format("%s: %s", where, tostring(err))
	rawWrite("runtime_error.txt", text .. "\n")
	logLine("ERROR " .. text)
	printf("[PoE2 Craft Overlay] ERROR %s", text)
	state.status = L("statusError", tostring(err))
	state.statusColor = { 0.95, 0.45, 0.45, 1 }
end

--- Terminate for real. The host ignores Exit() from OnInit and leaves the process
-- alive after engine shutdown, so the process is closed through taskkill.
-- Guarded: it must never throw (an exception here used to spam the log every frame)
-- and never run twice.
local function quitSelf(reason)
	if state.quitting then return end
	state.quitting = true
	logLine("quit requested: " .. tostring(reason))

	local pid = nil
	local okPid, pidOrErr = pcall(function()
		if type(state.hwnd) == "cdata" then
			return Win32.getWindowPid(state.hwnd)
		end
		return nil
	end)
	if okPid then pid = pidOrErr end

	if pid then
		local ok, code = pcall(os.execute, string.format("taskkill /F /PID %d", pid))
		local succeeded = ok and (code == 0 or code == true)
		logLine(string.format("taskkill pid=%d ok=%s code=%s", pid, tostring(ok), tostring(code)))
		if not succeeded then
			pcall(SpawnProcess, "taskkill", string.format("/F /PID %d", pid))
			logLine("taskkill fallback via SpawnProcess")
		end
	else
		logLine("own pid unknown - falling back to Exit() only")
	end

	pcall(Exit, tostring(reason))
end

--------------------------------------------------------------------------------
-- Capture & analysis
--------------------------------------------------------------------------------

--- Publish the current item to the local crafting site (web/server.js).
--
-- The site reads src/last_item.txt, so the page and the panel always show the same
-- capture. The server is started on demand: it writes src/web_server.heartbeat once a
-- second while it runs, so a fresh heartbeat means "already running" and repeated
-- hotkeys never spawn extra copies.
local function publishToWeb(raw)
	local web = config.web
	if not web or web.enabled == false then
		return
	end

	rawWrite("last_item.txt", raw)
	rawWrite("captured_at.txt", os.date("%Y-%m-%d %H:%M:%S"))

	-- Automated runs (render check, tests, MCP) must not open a browser: it steals focus
	-- and the host stops delivering frames, which breaks the screenshot they are waiting
	-- for. The capture files above are still written, so the site picks the item up.
	if state.renderCheck or state.testMode or state.mcpMode then
		return
	end

	local port = tonumber(web.port) or 17427
	local host = web.host or "127.0.0.1"
	local url = string.format("http://%s:%d/", host, port)
	local openBrowser = web.openBrowser ~= false and (" --open") or " --no-open"

	local heartbeat = tonumber(util.trim(util.readFile("web_server.heartbeat") or "")) or 0
	local running = (os.time() * 1000 - heartbeat) < 5000

	if running then
		-- The page updates itself over Server-Sent Events; opening the URL once brings
		-- it to the front for a player who closed the tab.
		if not state.webOpened and openBrowser == " --open" then
			state.webOpened = true
			logLine("crafting site already running, opening " .. url)
			pcall(os.execute, string.format('start "" "%s"', url))
		end
		return
	end

	if web.autoStart == false then
		return
	end

	-- The host runs with src/ as its working directory, but a copy started from the
	-- project root would be just as valid, so the command handles both.
	local command = string.format(
		'start "" /min cmd /c "if exist web\\server.js (node web\\server.js --port %d%s) '
		.. 'else (cd /d .. && node web\\server.js --port %d%s))"',
		port, openBrowser, port, openBrowser)
	logLine("starting the crafting site: " .. command)
	state.webOpened = true
	local ok, err = pcall(os.execute, command)
	if not ok then
		logLine("could not start the crafting site: " .. tostring(err))
	end
end

-- The host starts with a console window, and that console is exactly what flashes on screen when the
-- engine comes up. It is hidden here, before anything else, in every mode - panel, MCP or tests.
pcall(function()
	if Win32 and Win32.hideConsole then
		Win32.hideConsole()
		logLine("console window hidden at startup")
	end
end)
local function analyzeRaw(raw, origin)
	-- A Russian client copies Russian text while the engine is built on English Path of Building
	-- data, so the text is translated first - exactly as the MCP path does it. Without this the
	-- item parsed but was never marked as recognised, and the panel reported a parse failure.
	local parseText = raw
	-- The panel follows the game client's language, and this is where it can be known for certain:
	-- the text the game copied is written in it. The condition is hoisted so the branch below keeps
	-- exactly the shape it had.
	local isRussian = Ru and Ru.looksRussian and Ru.looksRussian(raw)
	Strings.lang = isRussian and "ru" or "en"
	if isRussian then
		parseText = Ru.toEnglish(raw) or raw
	end
	local item = Parser.parse(parseText)
	local advice = Advisor.analyze(item, ruleset)
	advice.origin = origin
	state.advice = advice
	state.adviceRev = state.adviceRev + 1
	-- The panel draws the item from the text the client copied: one language, the values that
	-- rolled, and only what the game itself would show. The rules live in Item/Lines and are
	-- covered by tests, so the panel and the site cannot drift apart on how an item reads.
	state.itemLines = Lines.split(raw)
	if not item.valid then
		state.status = L("statusParseFail", tostring(origin))
		state.statusColor = config.ui.bad
	else
		state.status = L("statusSummary",
			tostring(item.name), tostring(advice.ruleId or L("noRule")), advice.affixes)
		state.statusColor = advice.blocker and config.ui.warn or config.ui.good
	end

	rawWrite("last_advice.txt", Advisor.toText(advice))
	-- The site states where the numbers came from: a picture of the tooltip or the
	-- clipboard. A wrong reading is much easier to spot next to its source.
	rawWrite("capture_source.txt", tostring(origin))
	-- The panel does not publish anything: with no browser and no site there is nothing to
	-- publish to, and the call was what made the panel die on capture. The site remains
	-- available for anyone who still runs the agent, but the panel is self-contained.
	logLine("analyzed " .. tostring(origin) .. " -> " .. tostring(item.name) ..
		" (" .. tostring(item.rarity) .. "), rule=" .. tostring(advice.ruleId))
	printf("%s", Advisor.toText(advice))
	return advice
end

local function beginCapture()
	local gameWindow = Win32.findGameWindow(config.capture.windowImageNames, nil)

	-- The game window is optional now. The player copies the item with the client's own Ctrl+C,
	-- so the clipboard usually already holds it, and refusing to look without a window meant
	-- losing an item that was right there. The synthetic copy is only a bonus when it is
	-- possible; the clipboard is read either way.
	if config.capture.sendCtrlC and gameWindow then
		-- Guarded on purpose: this is the one step that reaches outside the engine, and a
		-- failure in it used to end the whole capture - the panel simply closed. The player
		-- copies the item with the client's own Ctrl+C anyway, so a failed synthetic press
		-- must not cost anything: the clipboard is read either way.
		local okSend, sendErr = pcall(Win32.sendCtrlC)
		if not okSend then
			logLine("synthetic Ctrl+C failed, reading the clipboard instead: " .. tostring(sendErr))
		end
		logLine(string.format("sent Ctrl+C to '%s' (pid %s)", gameWindow.title, tostring(gameWindow.pid)))
	end

	state.pendingCaptureAt = GetTime() + (config.capture.sendCtrlC and gameWindow and (config.capture.ctrlCDelayMs or 180) or 0)
end

local function finishCapture()
	state.pendingCaptureAt = nil
	local raw = Paste()
	if not raw or util.trim(raw) == "" then
		state.status = L("statusClipboardEmpty")
		state.statusColor = config.ui.warn
		logLine("clipboard empty after capture")
		return
	end
	analyzeRaw(raw, "clipboard")
end

--- Ctrl+Q: photograph the item tooltip, read it, and publish the result to the site.
--
-- This is the primary path, and it is the same workflow as the price-check hotkey in
-- Sidekick or Exiled Exchange 2 - hover, press, read the answer. The difference is where
-- the item comes from and where the answer goes: the item is read from a picture of the
-- tooltip (no game hook, no clipboard hijack), and the answer is a local page with room
-- for every number instead of an overlay panel.
--
-- Reading a tooltip is not guaranteed - a bright scene, a moving item or a partial
-- tooltip can defeat any OCR - so an empty reading falls back to the clipboard path. The
-- site always states which source produced the numbers.
local function grabImageItem()
	local capture = config.capture or { }
	local region = capture.imageRegion or { }
	local command = string.format(
		'powershell -NoProfile -ExecutionPolicy Bypass -File "%s" -Width %d -Height %d '
		.. '-OffsetX %d -OffsetY %d -Scale %s -OutPng src\\capture.png -OutText src\\ocr_item.txt',
		capture.grabScript or "tools\\grab_item.ps1",
		tonumber(region.width) or 660, tonumber(region.height) or 800,
		tonumber(region.offsetX) or 24, tonumber(region.offsetY) or -60,
		tostring(capture.grabScale or 2))

	state.status = L("statusGrabbing", config.hotkeys.grabImage)
	state.statusColor = config.ui.dim
	logLine("image capture: " .. command)

	local ok, output = pcall(os.execute, command)
	if not ok then
		logLine("image capture failed to run: " .. tostring(output))
	end

	local text = util.readFile("ocr_item.txt")
	local trimmed = util.trim(text or "")
	if #trimmed < (tonumber(capture.minOcrChars) or 20) then
		logLine(string.format("image capture read %d characters, falling back to the clipboard", #trimmed))
		state.status = L("statusOcrEmpty")
		state.statusColor = config.ui.warn
		guardedCapture("begin", beginCapture)
		return
	end

	logLine(string.format("image capture read %d characters", #trimmed))
	-- OCR does not reproduce the game's section separators, so the text is rebuilt into
	-- the copied-item layout before the parser sees it.
	local itemText, details = Ocr.toItemText(text)
	logLine(string.format("OCR layout: rebuilt=%s header=%d properties=%d modifiers=%d",
		tostring(details.rebuilt), details.header or 0, details.properties or 0, details.modifiers or 0))
	analyzeRaw(itemText, "image")
end

local function analyzeDemo()
	local raw = util.readFile(config.demoItemPath) or util.readFile("../samples/rare_gloves.txt")
	if not raw then
		state.status = L("statusDemoMissing", tostring(config.demoItemPath))
		state.statusColor = config.ui.bad
		return
	end
	analyzeRaw(raw, "demo")
end

--- Fold/unfold one panel block (also driven by clicking a block header).
local function toggleBlock(key, labelKey)
	local on = View.toggleSection(state.sections, key)
	state.sections = View.sectionsFor(state.sections)
	-- `omens` is the legacy alias of `league`; keep both in step.
	if key == "league" then
		state.sections.omens = on
	elseif key == "omens" then
		state.sections.league = on
	end
	state.status = L(on and "statusSectionOn" or "statusSectionOff", L(labelKey))
	state.statusColor = config.ui.dim
	logLine(string.format("block %s: %s", key, on and "expanded" or "collapsed"))
end
--- Row index (1-based) of the row under the cursor, or nil.
-- Only meaningful in interactive mode: in overlay mode the window is click-through.
local function rowUnderCursor()
	if not state.hwnd or not state.rowsCache then
		return nil
	end
	if not (Win32.cursorPos and Win32.screenToClient) then
		return nil
	end
	local cx, cy = Win32.cursorPos()
	if not cx then
		return nil
	end
	local clientX, clientY = Win32.screenToClient(state.hwnd, cx, cy)
	if not clientX then
		return nil
	end
	if clientX < 0 or clientX > px(config.overlay.width) or clientY < 0 then
		return nil
	end
	-- Rows live in unscaled units; the renderer scales them by uiScale.
	return View.rowAt(state.rowsCache, clientY / (uiScale or 1), 8, 7)
end

--- Click on a block header folds/unfolds that block (mouse equivalent of the keys).
local function handlePanelClick()
	local index = rowUnderCursor()
	local row = index and state.rowsCache and state.rowsCache[index]
	if row and row.block then
		toggleBlock(row.block, View.BLOCK_LABEL[row.block])
		return true
	end
	return false
end
--- Switch the glyph atlas live: the panel redraws in the new font on the next frame,
-- which is exactly the preview needed to judge a variant.
local function cycleFont(step)
	local variants = Font.variants()
	if #variants == 0 then
		state.status = L("statusFontNoVariants")
		state.statusColor = config.ui.bad
		return
	end
	local currentIndex = 1
	for index, variant in ipairs(variants) do
		if variant.id == Font.currentId() then
			currentIndex = index
			break
		end
	end
	local nextIndex = View.nextVariantIndex(currentIndex, #variants, step)
	local variant = variants[nextIndex]
	Font.use(variant.id)
	Font.loadAtlas(variant.id)
	-- The panel is cached by content; the font is part of that key, so it re-renders.
	state.status = L("statusFont", tostring(variant.label), nextIndex, #variants,
		config.hotkeys.fontModifier .. "+" .. config.hotkeys.fontNext,
		config.hotkeys.fontModifier .. "+" .. config.hotkeys.fontPrev,
		config.hotkeys.fontModifier .. "+" .. config.hotkeys.fontSave)
	state.statusColor = config.ui.gold
	logLine(string.format("font variant: %s (%d/%d)", variant.id, nextIndex, #variants))
end

--- Persist the current font choice so it survives a restart.
local function saveFontChoice()
	local okFont = Prefs.set("fontVariant", Font.currentId())
	local okScale = Prefs.set("textScale", state.textScale)
	local okSpacing = Prefs.set("letterSpacing", Font.trackingFor())
	local ok = okFont and okScale and okSpacing
	if ok then
		state.status = L("statusFontSaved", tostring(Font.metrics() and Font.metrics().label or Font.currentId()))
		state.statusColor = config.ui.good
	else
		state.status = L("statusError", "prefs.lua not writable")
		state.statusColor = config.ui.bad
	end
	logLine(string.format("font choice saved: %s scale=%.2f (ok=%s)",
		tostring(Font.currentId()), state.textScale, tostring(ok)))
end

--- Change the panel text scale live (Ctrl+F4 smaller, Ctrl+F5 larger).
local function setTextScale(scale)
	local clamped = View.clampTextScale(scale)
	if math.abs(clamped - (state.textScale or 1)) < 0.001 then
		return
	end
	state.textScale = clamped
	state.status = L("statusTextScale", math.floor(clamped * 100 + 0.5),
		config.hotkeys.fontModifier .. "+" .. config.hotkeys.textSmaller,
		config.hotkeys.fontModifier .. "+" .. config.hotkeys.textLarger)
	state.statusColor = config.ui.gold
	logLine(string.format("text scale: %.2f", clamped))
end

--- Change the letter spacing live (Ctrl+F7 tighter, Ctrl+F8 looser).
local function setLetterSpacing(delta)
	local current = Font.trackingFor()
	local next_ = current + delta
	if next_ < 0.80 then next_ = 0.80 end
	if next_ > 1.10 then next_ = 1.10 end
	if math.abs(next_ - current) < 0.001 then
		return
	end
	Font.setTracking(next_)
	state.status = L("statusSpacing", math.floor(next_ * 100 + 0.5),
		config.hotkeys.fontModifier .. "+" .. config.hotkeys.letterTighter,
		config.hotkeys.fontModifier .. "+" .. config.hotkeys.letterLooser)
	state.statusColor = config.ui.gold
	logLine(string.format("letter spacing: %.3f", next_))
end

--- Parse a hotkey spec such as "CTRL+Q" or "F6" and test it.
-- The modifier comes first, separated by "+"; anything without a "+" is a plain key.
local function hotkeyFromSpec(spec)
	if type(spec) ~= "string" or spec == "" then
		return false
	end
	local plus = spec:find("+", 1, true)
	if not plus then
		return hotkeyPressed(spec)
	end
	local modifier = spec:sub(1, plus - 1)
	local key = spec:sub(plus + 1)
	return hotkeyPressed(key, modifier)
end

--- Put the capture agent in the system tray: no panel, no taskbar button, one icon whose
-- menu opens the site, captures an item, or quits.
local function setupTray()
	if config.overlay.tray == false then
		return
	end
	local web = config.web or { }
	local url = string.format("http://%s:%d/", web.host or "127.0.0.1", tonumber(web.port) or 17427)
	local ok, why = Tray.create({
		tooltip = "PoE2 Craft Overlay - hover an item and press " .. tostring(config.hotkeys.grabImage),
		onOpen = function()
			logLine("tray: opening " .. url)
			pcall(os.execute, string.format('start "" "%s"', url))
		end,
		onCapture = function()
			logLine("tray: image capture")
			grabImageItem()
		end,
		onClipboard = function()
			logLine("tray: clipboard capture")
			guardedCapture("begin", beginCapture)
		end,
		onQuit = function()
			quitSelf("tray menu")
		end,
	})
	if ok then
		logLine("tray: icon added (menu: open site, capture, clipboard, quit)")
	else
		logLine("tray: icon not added: " .. tostring(why))
	end
end

local function applyOverlayStyle()
	if not state.hwnd then
		-- Locate OUR window only: exact title restricted to the host process image.
		-- findGameWindow deliberately refuses to guess when given no process names.
		local own = Win32.findOwnWindow(APP_NAME, config.overlay.hostImage)
		if not own then
			logLine("own window not found; overlay styling skipped")
			state.status = L("statusOverlayWindowMissing")
			return
		end
		state.hwnd = own.hwnd
		logLine(string.format("own window: '%s' pid=%d image=%s", own.title, own.pid, tostring(own.image)))
	end

	local detail
	if state.interactive then
		local _, d = Win32.makeInteractive(state.hwnd)
		detail = d
	else
		local _, d = Win32.makeOverlay(state.hwnd, {
			alpha = config.overlay.alpha,
			clickThrough = config.overlay.clickThrough,
			topmost = config.overlay.topmost,
			keyColor = config.overlay.keyColor,
			-- No panel means no reason to appear in the taskbar or Alt+Tab.
			toolWindow = config.overlay.enabled == false,
		})
		detail = d
	end
	logLine("window style: " .. tostring(detail))

	if config.overlay.autoPosition then
		if config.overlay.enabled == false then
			-- Capture-agent mode: the panel is not drawn at all (every number lives on the
			-- local site), so the window only has to exist and stay out of the way - a tiny
			-- transparent, click-through square in the corner.
			local size = px(2)
			Win32.moveWindow(state.hwnd, 0, 0, size, size + px(config.overlay.chromePad or 40))
			logLine("panel disabled: running as a capture agent (hotkeys only)")
			return
		end
		local w = px(config.overlay.width)
		local contentHeight = px(config.overlay.height)
		local windowHeight = contentHeight + px(config.overlay.chromePad or 40)
		local x, y = util.centerPosition(state.screenW or w, state.screenH or contentHeight,
			w, contentHeight, px(config.overlay.marginCenter or 0))
		Win32.moveWindow(state.hwnd, x, y, w, windowHeight)
		logLine(string.format("overlay centred at %d,%d client %dx%d window %dx%d (scale %.2f)",
			x, y, w, contentHeight, w, windowHeight, uiScale))
	end
end

--------------------------------------------------------------------------------
-- Font probe: which of the host's fonts can draw Cyrillic at all?
-- The drawing function itself lives in the Drawing section below, where the colour
-- and background helpers it depends on are already in scope.
--------------------------------------------------------------------------------

-- Font names used by the host. PoB refers to them as VAR / VAR BOLD / FIXED; the
-- underlying files are Fontin (Latin only) and Liberation (which does ship Cyrillic),
-- so the answer has to come from an actual render, not from documentation.
local FONT_CANDIDATES = {
	"VAR", "VAR BOLD", "FIXED",
	"Fontin", "Liberation Sans", "Liberation Sans Bold",
	"Bitstream Vera Sans Mono", "DEFAULT",
}

--------------------------------------------------------------------------------
-- Drawing
-- Two paths: the glyph atlas (ASCII + Cyrillic, needed for the Russian panel) and
-- the host's DrawString (ASCII only) as a fallback when the atlas cannot be loaded.
--------------------------------------------------------------------------------

local function setColor(color)
	SetDrawColor(color[1], color[2], color[3], color[4] or 1)
end

--- Draw one line; alignment is emulated for the atlas path (glyph drawing is
-- left-anchored, so CENTER_X / RIGHT_X are computed from the measured width).
local function drawText(x, y, align, size, font, text)
	if Font.available() then
		local width = Font.width(text, size)
		local left = x
		if align == "CENTER" or align == "CENTER_X" then
			left = x - width / 2
		elseif align == "RIGHT" or align == "RIGHT_X" then
			left = x - width
		end
		Font.draw(text, left, y, size)
		return
	end
	DrawString(x, y, align, size, font, i18n.asciiSafe(text))
end

local function textWidth(height, font, text)
	if Font.available() then
		return Font.width(text, height)
	end
	if DrawStringWidth then
		local ok, w = pcall(DrawStringWidth, height, font, i18n.asciiSafe(text))
		if ok and type(w) == "number" then
			return w
		end
	end
	return #text * (height * 0.5)
end

local function wrapText(text, height, font, maxWidth)
	local lines = { }
	local current = nil
	for word in tostring(text):gmatch("%S+") do
		local candidate = current and (current .. " " .. word) or word
		if (not current) or textWidth(height, font, candidate) <= maxWidth then
			current = candidate
		else
			lines[#lines + 1] = current
			current = word
		end
	end
	if current then lines[#lines + 1] = current end
	return lines
end

--- Truncate long modifier texts so the odds lines stay on one row.
local function shortText(text, limit)
	local s = tostring(text)
	if #s <= limit then
		return s
	end
	return s:sub(1, limit - 3) .. "..."
end

local function buildRows()
	local ui = config.ui
	local rows = { }
	local detail = View.clampDetail(state.detailLevel)
	local sections = View.sectionsFor(state.sections)
	local function push(text, color, font, size, indent, block, right)
		-- Every row goes through here, so the text scale (Ctrl+F4/F5) applies uniformly
		-- and the panel height follows the size automatically. `block` marks a row as a
		-- block header, which makes it clickable in interactive mode. `right` is the
		-- optional right-hand column: chances and prices go there so they line up.
		rows[#rows + 1] = {
			text = text, color = color or ui.text, font = font or ui.font,
			size = View.scaledSize(size or 16, state.textScale), indent = indent or 0,
			block = block, right = right,
		}
	end
	-- Block header: "[+] --- Item ---" / "[-] --- Item ---". The marker is the click
	-- target in interactive mode and states whether the block is folded.
	local function addHeader(block)
		push(string.format("%s %s", View.blockMarker(sections[block] == true), L(View.BLOCK_LABEL[block])),
			ui.gold, ui.fontBold, 14, 0, block)
	end
	-- Prices are only used when the snapshot covers this league; otherwise the panel
	-- stays silent instead of quoting numbers from another league.
	local priceApplies = Prices.matchesLeague(ruleset.league or ruleset.leagueShort,
		config.ui.pricesLeague)
	-- A snapshot that has gone stale has to say so: without the agent nothing refreshes this
	-- file, and a day-old rate presented as today's is worse than showing none at all.
	local priceInfo = Prices.info()
	local priceStamp = priceInfo and priceInfo.fetchedAt
	local priceStale = priceStamp and Prices.isStale(priceStamp, 24)
	-- Lines are wrapped to the widest the panel may become, not to the width it currently has:
-- that is what lets drawPanel shrink the window to the content without a circular dependency.
	-- The fallback keeps the old behaviour for configs that do not set maxWidth.
	local innerWidth = px(config.overlay.maxWidth or config.overlay.width) - px(40)

	push(L("appTitle") .. "   |   " .. L("leagueLabel", tostring(ruleset.leagueShort or ruleset.league)),
		ui.gold, ui.fontBold, 16)
	if priceApplies and priceStamp then
		local russian = (Strings.lang == "ru")
		local text = (russian and "Курсы на " or "Rates as of ") .. tostring(priceStamp)
		if priceStale then
			text = text .. (russian and "  (устарели)" or "  (stale)")
		end
		push(text, priceStale and (ui.warn or ui.bad) or ui.dim, ui.font, 12)
	end
	-- Everything long is wrapped: the monospaced glyph atlas is wider than the host's
	-- proportional font, so unwrapped rows would spill outside the panel.
	for _, line in ipairs(wrapText(state.status, 14, ui.font, innerWidth)) do
		push(line, state.statusColor, ui.font, 14)
	end

	local advice = state.advice
	if not advice then
		push(" ")
		push(L("howTo"), ui.text, ui.fontBold, 15)
		local help = {
			L("howTo1"),
			L("howTo2", config.hotkeys.capture),
			L("howTo3"),
			L("howTo4", config.hotkeys.demo, config.hotkeys.interactive, config.hotkeys.quit),
		}
		for _, line in ipairs(help) do
			for _, wrapped in ipairs(wrapText(line, 14, ui.font, innerWidth)) do
				push(wrapped, ui.dim, ui.font, 14, 12)
			end
		end
		return rows
	end

	local lang = Strings.lang
	addHeader("item")
	if sections.item then
		-- The item name takes the rarity colour and modifier lines the game's magic blue,
		-- the way a real tooltip separates item fields from modifiers.
		local rarity = tostring((advice.item and advice.item.rarity) or ""):lower()
		local nameColor = (config.ui.rarity or { })[rarity] or ui.text
		local lineIndex = 0
		-- The item itself: its name and base in the client's language, its own fields, then its
		-- modifiers. The lines come from Item/Lines, which reads the text the client copied, so
		-- the panel shows one language and the values that actually rolled.
		local itemLines = state.itemLines
		if itemLines and (#itemLines.properties > 0 or #itemLines.mods > 0) then
			-- Name and base come from the client's own text: the parsed item is English because
			-- the engine translates the Russian before parsing, and the panel has to read as the
			-- player's client does.
			local shown = advice.item or { }
			if itemLines.header and itemLines.header.name then
				shown = { name = itemLines.header.name, baseType = itemLines.header.base or shown.baseType }
			end
			if shown.name and shown.name ~= "" then
				for _, wrapped in ipairs(wrapText(shown.name, 15, ui.fontBold, innerWidth - px(4))) do
					push(wrapped, nameColor, ui.fontBold, 15, 12)
				end
			end
			if shown.baseType and shown.baseType ~= "" then
				for _, wrapped in ipairs(wrapText(shown.baseType, 13, ui.font, innerWidth - px(4))) do
					push(wrapped, nameColor, ui.font, 13, 10)
				end
			end
			for _, property in ipairs(itemLines.properties) do
				for _, wrapped in ipairs(wrapText(Strings.displayLabel(property.label, Strings.lang) .. ": " .. property.value, 12, ui.font, innerWidth - px(4))) do
					push(wrapped, ui.text, ui.font, 12, 10)
				end
			end
			for _, mod in ipairs(itemLines.mods) do
				local color = mod.fractured and (ui.fractured or ui.good) or ui.magic
				for _, wrapped in ipairs(wrapText(mod.text, 13, ui.font, innerWidth - px(4))) do
					push(wrapped, color, ui.font, 13, 10)
				end
			end
			if itemLines.flags.corrupted then
				push((lang == "ru") and "Осквернено" or "Corrupted", ui.bad, ui.font, 12, 10)
			end
			if itemLines.flags.sanctified then
				push((lang == "ru") and "Освящено" or "Sanctified", ui.good, ui.font, 12, 10)
			end
		end

		-- Fallback: the advisor's own lines, used when the client's text yielded nothing usable.
		for _, line in ipairs(itemLines and { } or Advisor.stateFor(advice, lang)) do
			-- Per-modifier tier lines are bulky, so they follow the "mod tiers" section
			-- toggle; the rest of the item block is always shown.
			lineIndex = lineIndex + 1
			local isModTier = line:match("^T%d") ~= nil
			if (not isModTier) or sections.modTiers then
				local color = ui.text
				local font = ui.font
				if lineIndex == 1 then
					color = nameColor
					font = ui.fontBold
				elseif isModTier then
					color = ui.magic
				end
				for _, wrapped in ipairs(wrapText(line, 14, ui.font, innerWidth - px(4))) do
					push(wrapped, color, font, 14, 12)
				end
			end
		end
		if advice.runeforging and #advice.runeforging > 0 then
			local text = L("runeforgingLine", Strings.baseName(advice.item and advice.item.baseType or "?", lang),
				table.concat(advice.runeforging, ", "))
			for _, line in ipairs(wrapText(text, 12, ui.font, innerWidth - px(4))) do
				push(line, ui.good, ui.font, 12, 12)
			end
		end		if not sections.modTiers then
			push(L("omitted", L("sectionMods"), config.hotkeys.toggleMods), ui.dim, ui.font, 12, 12)
		end
	else
		push(L("blockCollapsed", config.hotkeys.toggleItem), ui.dim, ui.font, 12, 12)
	end

	-- What a random modifier can reach at this item level, restricted to this base.
	-- Reported over tiered groups only: single-tier groups reach "T1" trivially and
	-- would otherwise make the share look like a probability.
	if advice.rollStats and sections.item then
		local stats = advice.rollStats
		local class = advice.item and advice.item.itemClass or "item"
		for _, line in ipairs(wrapText(L("rollPoolLine", tostring(class), stats.tieredGroups,
			stats.avgBestTierTiered, stats.tieredT1, stats.tieredT1Percent), 12, ui.font, innerWidth)) do
			push(line, ui.dim, ui.font, 12, 12)
		end
	end

	local blocker = (lang == "ru") and advice.blocker or (advice.blockerEn or advice.blocker)
	if blocker then
		for _, line in ipairs(wrapText("!!! " .. tostring(blocker), 14, ui.font, innerWidth)) do
			push(line, ui.bad, ui.font, 14)
		end
	end

	addHeader("plans")
	for _, plan in ipairs(advice.plans) do
		local title = (lang == "ru") and plan.title or (plan.titleEn or plan.title)
		push(tostring(title), plan.id == "min" and ui.good or ui.gold, ui.fontBold, 14, 8)
		if not sections.plans then
			-- Collapsed: keep the route headline so the block still says something.
			local names = { }
			for _, step in ipairs(plan.steps) do
				names[#names + 1] = Strings.name(lang, step.ru, step.en)
			end
			if #names > 0 then
				push(string.format("%s  (%s)", table.concat(names, " -> "), config.hotkeys.togglePlans),
					ui.dim, ui.font, 12, 16)
			end
		end
		local reason = sections.plans and ((lang == "ru") and plan.reason or (plan.reasonEn or plan.reason)) or nil
		if reason then
			for _, line in ipairs(wrapText(reason, 12, ui.font, innerWidth - px(4))) do
				push(line, ui.dim, ui.font, 13, 8)
			end
		end
		-- Collapse consecutive identical steps ("Greater Exalted Orb" twice in a row)
		-- into one row with a count, so odds and descriptions are printed once.
		local display = { }
		for _, step in ipairs(plan.steps) do
			local last = display[#display]
			if last and last.step.id == step.id then
				last.count = last.count + 1
			else
				display[#display + 1] = { step = step, count = 1 }
			end
		end
		for index, entry in ipairs(display) do
			if not sections.plans then break end
			local step = entry.step
			-- Item display name followed by its base type.
			local stepName = Strings.name(lang, step.ru, step.en)
			if entry.count > 1 then
				stepName = string.format("%s ×%d", stepName, entry.count)
			end
			push(string.format("%d) %s  [%s]", index, stepName, tostring(step.cost)), ui.text, ui.font, 13, 12)
			-- Market price when a snapshot for this league exists: a cost tier says
			-- "cheap or not", a number says how much.
			if priceApplies then
				local unit = Prices.unitPrice(step.en)
				if unit then
					-- A price is a number like a chance, so it goes into the same right-hand
					-- column: prices line up with each other and with the percentages above.
					push("", ui.dim, ui.font, 11, 26, nil, {
						text = L("stepPrice", unit * (entry.count or 1), tostring(Prices.info().unit)),
						color = ui.good,
					})
				end
			end
			local effect = (lang == "ru") and step.effect or (step.effectEn or step.effect)
			if View.showEffect(detail) then
				for _, line in ipairs(wrapText(effect, 12, ui.font, innerWidth - px(16))) do
					push(line, ui.dim, ui.font, 12, 26)
				end
			end
			local hint = (lang == "ru") and step.hint or (step.hintEn or step.hint)
			if hint and View.showHints(detail) then
				for _, line in ipairs(wrapText(L("tipLabel") .. hint, 12, ui.font, innerWidth - px(16))) do
					push(line, ui.good, ui.font, 12, 26)
				end
			end
			local warning = (lang == "ru") and step.warning or (step.warningEn or step.warning)
			if warning and View.showHints(detail) then
				for _, line in ipairs(wrapText(warning, 12, ui.font, innerWidth - px(16))) do
					push(line, ui.warn, ui.font, 12, 26)
				end
			end

			-- Roll odds: which modifiers a random add can produce, with the chance of
			-- each (weighted pool from Data/mods.lua, filtered by base, item level,
			-- open side and the currency's minimum modifier level).
			-- Level 2 shows the single best chance inline; level 3 the full list.
			if step.pool and step.pool.groups and View.showTopChance(detail) then
				local sideLabel = L("chancesSideBoth")
				if step.pool.side == "prefix" then
					sideLabel = L("chancesSidePrefix")
				elseif step.pool.side == "suffix" then
					sideLabel = L("chancesSideSuffix")
				end
				local floor = (step.minModLevel or 0) > 0 and L("chancesFloor", step.minModLevel) or ""
				if View.showOdds(detail) then
					for _, line in ipairs(wrapText(L("chancesHeader", step.pool.tierCount, sideLabel, floor),
						13, ui.font, innerWidth - px(16))) do
						push(line, ui.dim, ui.font, 12, 26)
					end
				end

				local limit = View.showOdds(detail) and 3 or 1
				local shownTexts = { }
				for _, group in ipairs(step.pool.groups) do
					if #shownTexts >= limit then break end
					-- Different groups can share a display text (parallel ladders in
					-- the data), so show each text once.
					if not shownTexts[group.bestText] then
						shownTexts[group.bestText] = true
						shownTexts[#shownTexts + 1] = group.bestText
						local modName = Strings.modName(group.bestText, lang)
						local entry = string.format("%s (T%d)", modName, group.bestTier)
						-- The chance goes into the right-hand column of the first line, so the
						-- percentages line up in a column instead of leading every sentence.
						local chanceCell = { text = string.format("%.2f%%", group.chance), color = ui.dim }
						local firstLine = true
						for _, line in ipairs(wrapText(entry, 12, ui.font, innerWidth - px(16))) do
							push(line, ui.dim, ui.font, 12, 30, nil, firstLine and chanceCell or nil)
							firstLine = false
						end
					end
				end
			end

			if step.removal and View.showOdds(detail) then
				push(L("removalLine", step.removal.perModChance, step.removal.affixes), ui.dim, ui.font, 12, 26)
			end
		end
		if sections.plans and #plan.steps == 0 then
			push(L("blockCollapsed", config.hotkeys.togglePlans), ui.dim, ui.font, 12, 12)
		end
	end

	-- Omens and desecration: combinations with the odds each omen changes. Collapsed
	-- by default, because the section is long and the overlay should stay small.
	if advice.omenOptions and #advice.omenOptions > 0 then
		addHeader("league")
	end
	if advice.omenOptions and #advice.omenOptions > 0 and sections.league then
		local shown = 0
		local optionLimit = View.optionLimit(detail)
		for _, omenOption in ipairs(advice.omenOptions) do
			if shown >= optionLimit then break end
			shown = shown + 1
			local title = (lang == "ru") and omenOption.title or omenOption.titleEn
			push(tostring(title), ui.good, ui.font, 13, 10)
			local why = (lang == "ru") and omenOption.why or (omenOption.whyEn or omenOption.why)
			for _, line in ipairs(wrapText(why, 12, ui.font, innerWidth - px(16))) do
				push(line, ui.dim, ui.font, 12, 22)
			end
			if omenOption.kind == "essence" then
				-- Essences always apply their modifier, so the line shows the mod, the
				-- tier and 100% instead of a random-chance list.
				local essence = omenOption.essence
				local text = L("essenceLine", Strings.modName(essence.mod.text, lang),
					essence.mod.tier, essence.mod.lvl, essence.chance)
				for _, line in ipairs(wrapText(text, 12, ui.font, innerWidth - px(16))) do
					push(line, ui.good, ui.font, 12, 22)
				end
			elseif omenOption.kind == "rune" then
				-- Runes grant exactly one modifier for their slot: 100%, with the
				-- per-item limit and the level requirement spelled out.
				local rune = omenOption.rune
				local levelPart = (rune.levelReq or 0) > 0 and L("runeLevel", rune.levelReq) or ""
				local text = L("runeLine", rune.text, rune.chance, rune.limit, levelPart)
				for _, line in ipairs(wrapText(text, 12, ui.font, innerWidth - px(16))) do
					push(line, ui.good, ui.font, 12, 22)
				end
			elseif omenOption.kind == "alloy" then
				-- Alloy pool: no percentages here on purpose, see the note below.
				for index, entry in ipairs(omenOption.pool.entries) do
					if index > 3 then break end
					if type(entry.text) == "string" and entry.text ~= "" then
						local text = string.format("%s (T%d, %s %d)",
							Strings.modName(entry.text, lang), entry.tier, L("modLevelShort"), entry.lvl)
						for _, line in ipairs(wrapText(text, 11, ui.font, innerWidth - px(16))) do
							push(line, ui.dim, ui.font, 11, 22)
						end
					end
				end
				if omenOption.alloyNames and #omenOption.alloyNames > 0 then
					local text = L("alloyList", table.concat(omenOption.alloyNames, ", "))
					for _, line in ipairs(wrapText(text, 11, ui.font, innerWidth - px(16))) do
						push(line, ui.text, ui.font, 11, 22)
					end
				end
				for _, line in ipairs(wrapText(L("alloyNote"), 11, ui.font, innerWidth - px(16))) do
					push(line, ui.warn, ui.font, 11, 22)
				end
				for _, line in ipairs(wrapText(L("alloyNamesNote"), 11, ui.font, innerWidth - px(16))) do
					push(line, ui.dim, ui.font, 11, 22)
				end
			elseif omenOption.deterministic and not omenOption.why then
				-- Only shown when the option has no explicit explanation; the "why" text
				-- already names the target, so printing both duplicated the information.
				local target = omenOption.deterministic
				if target.chance then
					push(L("omenRemovesSide", target.side or "?", target.chance), ui.warn, ui.font, 12, 22)
				else
					push(L("omenRemoves", Strings.modName(target.text, lang), target.level or 0), ui.warn, ui.font, 12, 22)
				end
			elseif omenOption.atLeastOnce then
				for index, entry in ipairs(omenOption.atLeastOnce) do
					if index > 2 then break end
					local text = string.format("  %.2f%%  %s (T%d)  [%s]", entry.chance,
						Strings.modName(entry.text, lang), entry.tier,
						L("omenAtLeastOnce", omenOption.multiRoll or 2, entry.chance, entry.single))
					for _, line in ipairs(wrapText(text, 11, ui.font, innerWidth - px(16))) do
						push(line, ui.dim, ui.font, 11, 22)
					end
				end
			elseif omenOption.pool and omenOption.pool.groups and #omenOption.pool.groups > 0 then
				local shownTexts = { }
				for _, group in ipairs(omenOption.pool.groups) do
					if #shownTexts >= 3 then break end
					if not shownTexts[group.bestText] then
						shownTexts[group.bestText] = true
						shownTexts[#shownTexts + 1] = group.bestText
						local text = string.format("%s (T%d)",
							Strings.modName(group.bestText, lang), group.bestTier)
						-- Chance into the right-hand column of the first line, exactly as in the
						-- plan block above, so percentages line up across both.
						local chanceCell = { text = string.format("%.2f%%", group.chance), color = ui.dim }
						local firstLine = true
						for _, line in ipairs(wrapText(text, 11, ui.font, innerWidth - px(16))) do
							push(line, ui.dim, ui.font, 11, 22, nil, firstLine and chanceCell or nil)
							firstLine = false
						end
					end
				end
			end
			-- Quality on jewellery: a catalyst covers ONE modifier tag and replaces quality of another,
			-- so the choice is the decision. The advisor lists every catalyst that matches a modifier
			-- the item already has; the panel shows the first few rather than picking one.
			if omenOption.catalysts and #omenOption.catalysts > 0 then
				local shownNames = { }
				for index, name in ipairs(omenOption.catalysts) do
					if index > 4 then break end
					shownNames[#shownNames + 1] = name
				end
				for _, line in ipairs(wrapText(L("catalystShortlist",
					table.concat(shownNames, ", ")), 11, ui.font, innerWidth - px(16))) do
					push(line, ui.text, ui.font, 11, 22)
				end
			end
			-- Instilling: the recipe is a fixed set of three emotions in order, and the current
			-- combinations live in the game, so the panel says so instead of inventing one.
			if omenOption.kind == "instil" then
				local text = omenOption.alreadyInstilled
					and L("instilAlready", omenOption.emotions or 0)
					or L("instilHow", omenOption.emotions or 0)
				for _, line in ipairs(wrapText(text, 11, ui.font, innerWidth - px(16))) do
					push(line, omenOption.alreadyInstilled and ui.warn or ui.dim, ui.font, 11, 22)
				end
			end
			-- Waystones: the tier is the thing that matters, and a corrupted tier 15 is the only source
			-- of a tier 16.
			if omenOption.kind == "waystone" then
				local text = omenOption.tier
					and L("waystoneTierRule", omenOption.tier)
					or L("waystoneNoTier")
				for _, line in ipairs(wrapText(text, 11, ui.font, innerWidth - px(16))) do
					push(line, ui.dim, ui.font, 11, 22)
				end
			end
			-- Desecration does not roll one modifier out of the pool: the Well of Souls
			-- offers three, so the reveal chance is printed next to the weighted share.
			if omenOption.pool and omenOption.pool.reveal and (omenOption.pool.reveal.poolSize or 0) > 0 then
				local reveal = omenOption.pool.reveal
				local group = omenOption.pool.groups and omenOption.pool.groups[1]
				local text = L("revealLine", reveal.draws, reveal.poolSize,
					(group and group.revealChance or 0) * 100,
					(group and group.revealEchoes or 0) * 100)
				for _, line in ipairs(wrapText(text, 11, ui.font, innerWidth - px(16))) do
					push(line, ui.good, ui.font, 11, 22)
				end
			end
			if omenOption.oddsNote then
				for _, line in ipairs(wrapText(omenOption.oddsNote, 12, ui.font, innerWidth - px(16))) do
					push(line, ui.warn, ui.font, 12, 22)
				end
			end
			if omenOption.oddsUnknown then
				for _, line in ipairs(wrapText(L("omenNoOdds"), 12, ui.font, innerWidth - px(16))) do
					push(line, ui.warn, ui.font, 12, 22)
				end
			end
			if omenOption.status == "unverified" and ruleset.warnings then
				local text = tostring((lang == "ru") and ruleset.warnings.unverified or ruleset.warnings.unverifiedEn)
				for _, line in ipairs(wrapText(text, 12, ui.font, innerWidth - px(16))) do
					push(line, ui.warn, ui.font, 12, 22)
				end
			end
		end
	elseif advice.omenOptions and #advice.omenOptions > 0 then
		push(L("blockCollapsed", config.hotkeys.toggleOmens), ui.dim, ui.font, 12, 10)
	end

	-- Where the numbers come from: printed with the methods so the odds are checkable.
	-- The data sources are reference material, so they only appear at the detailed level
	-- instead of pushing the useful part of the panel off the screen.
	if detail >= 3 and sections.league and advice.sources and #advice.sources > 0 then
		push(L("sourcesTitle"), ui.gold, ui.font, 12, 10)
		for _, source in ipairs(advice.sources) do
			local text = L("sourceLine", tostring(source.label), tostring(source.detail),
				tostring(source.url))
			for _, line in ipairs(wrapText(text, 11, ui.font, innerWidth - px(16))) do
				push(line, ui.dim, ui.font, 11, 22)
			end
		end
	end

	local notes = Advisor.notesFor(advice, lang)
	if #notes > 0 then
		addHeader("notes")
	end
	if #notes > 0 and sections.notes then
		for _, note in ipairs(notes) do
			for _, line in ipairs(wrapText("* " .. note, 12, ui.font, innerWidth - px(4))) do
				push(line, ui.warn, ui.font, 13, 10)
			end
		end
	elseif #notes > 0 then
		push(L("blockCollapsed", config.hotkeys.toggleNotes), ui.dim, ui.font, 12, 10)
	end

	return rows
end

--- Height the given rows need, including padding and the two footer lines.
--- Widest row, so the window can shrink to its content instead of always using the configured
-- width. The right-hand column counts too: it is drawn at the far edge, so it decides the width.
local function rowsWidth(rows)
	local widest = 0
	for _, row in ipairs(rows) do
		local left = px(8) + px(row.indent) + textWidth(row.size, row.font, row.text or "")
		if row.right then
			left = left + px(16) + textWidth(row.right.size or row.size, row.right.font or row.font,
				row.right.text or "")
		end
		widest = math.max(widest, left)
	end
	return widest + px(16)
end

local function rowsHeight(rows)
	local total = px(10)
	for _, row in ipairs(rows) do
		total = total + px(row.size + 7) + (row.block and px(6) or 0)
	end
	return total + px(72) -- three footer lines plus a gap (see the truncation guard)
end

--- Paint the panel background: erase to the colour key (when enabled) so the rest
-- of the full-size overlay window becomes invisible and click-through.
local function clearBackground()
	if config.overlay.keyColor then
		local c = config.overlay.keyColor
		SetClearColor(c.r / 255, c.g / 255, c.b / 255, 1)
	else
		SetClearColor(0, 0, 0, 1)
	end
end

--- Side-by-side comparison of every available glyph atlas (font_compare.flag).
-- Each variant draws its own sample lines with its own image handle, so spacing and
-- weight can be judged directly instead of from a description.
local function drawFontCompare()
	local ui = config.ui
	-- Wide enough for three readable columns; height is kept inside a 1440p screen.
	local width = px(1240)
	local height = px(760)

	SetDrawLayer(1000)
	SetViewport()
	clearBackground()

	if state.hwnd and state.compareHeight ~= height then
		state.compareHeight = height
		local x, y = util.centerPosition(state.screenW or width, state.screenH or height,
			width, height + px(config.overlay.chromePad or 40), px(config.overlay.marginCenter or 0))
		Win32.moveWindow(state.hwnd, x, y, width, height + px(config.overlay.chromePad or 40))
	end

	setColor(ui.background)
	DrawImage(nil, 0, 0, width, height)
	-- 1px frame: the surface then reads as a panel rather than a floating block of text,
	-- which is how Sidekick's overlay presents itself.
	if ui.border then
		setColor(ui.border)
		DrawImage(nil, 0, 0, width, px(1))
		DrawImage(nil, 0, height - px(1), width, px(1))
		DrawImage(nil, 0, 0, px(1), height)
		DrawImage(nil, width - px(1), 0, px(1), height)
	end
	setColor(ui.gold)
	DrawImage(nil, 0, 0, width, px(2))

	setColor(ui.gold)
	DrawString(px(10), px(8), "LEFT", 15, ui.fontBold, "GLYPH ATLAS COMPARISON / sravnenie shriftov")
	setColor(ui.dim)
	DrawString(px(10), px(26), "LEFT", 12, ui.font,
		"each row: label, then the variant's own render of the same two lines")

	local variants = Font.variants()
	if state.fontShortlist then
		-- Shortlist mode: only the recommended faces, with a three-line sample each so
		-- the differences are easy to judge.
		local wanted = { }
		for _, id in ipairs(config.ui.fontShortlist or { }) do
			wanted[id] = true
		end
		local filtered = { }
		for _, variant in ipairs(variants) do
			if wanted[variant.id] then
				filtered[#filtered + 1] = variant
			end
		end
		if #filtered > 0 then
			variants = filtered
		end
	end
	-- Adaptive columns: enough of them that the rows never run off the bottom.
	local maxRows = state.fontShortlist and 7 or 14
	local columns = math.max(1, math.ceil(#variants / maxRows))
	local perColumn = math.ceil(#variants / columns)
	local columnWidth = width / columns
	local rowHeight = px(state.fontShortlist and 104 or 56)
	for index, variant in ipairs(variants) do
		local column = math.floor((index - 1) / perColumn)
		local row = (index - 1) % perColumn
		local originX = px(10) + column * columnWidth
		local rowY = px(44) + row * rowHeight
		if rowY > height - px(40) then
			break
		end
		setColor(ui.text)
		DrawString(originX, rowY, "LEFT", 11, ui.font, string.format("%2d. %s", index, variant.label))
		local metrics = Font.metricsFor(variant.id)
		local size = metrics and metrics.baseSize or 16
		setColor(ui.gold)
		Font.drawVariant(variant.id, "Exalted Orb 4.92%", originX + px(8), rowY + px(14), size)
		setColor(ui.text)
		Font.drawVariant(variant.id, "T6 +118 to maximum Life", originX + px(8), rowY + px(18 + size), size)
		if state.fontShortlist then
			setColor(ui.dim)
			Font.drawVariant(variant.id, "MAX - best result: 2 steps", originX + px(8), rowY + px(22 + size * 2), size)
		end
	end
end

--- Render sample text through the glyph atlas; a screenshot then answers "can this
-- host draw Cyrillic at all?" (see docs/font_probe.jpg). font_probe.flag marker.
local function drawFontProbe()
	SetDrawLayer(1000)
	SetViewport()
	clearBackground()

	local okAtlas, atlasErr = Font.loadAtlas()
	SetDrawColor(1, 1, 1, 1)
	DrawString(10, 10, "LEFT", 16, "VAR",
		string.format("atlas available=%s (%s)", tostring(okAtlas ~= nil), tostring(atlasErr or "ok")))

	if Font.available() then
		local samples = {
			"Exalted Orb (gold)",
			"Omen of Whittling (gold)",
			"Gloves, item level 82, tier T1",
			"ABCDEF abcdef 1234567890 - 45%",
		}
		local y = 44
		for _, sample in ipairs(samples) do
			Font.draw(sample, 10, y, 20)
			y = y + 28
			Font.draw(sample, 10, y, 16)
			y = y + 26
		end
	else
		DrawString(10, 44, "LEFT", 16, "VAR", "Exalted Orb")
	end
end

local function drawPanel()
	local ui = config.ui
	local width = px(config.overlay.width)
	local sections = View.sectionsFor(state.sections)

	SetDrawLayer(1000)
	SetViewport()
	clearBackground()

	-- Rebuilding (and re-wrapping) every line on every frame is what made the overlay
	-- crawl at a few frames per second, so the rows are cached and only rebuilt when
	-- something they depend on actually changes.
	local cacheKey = table.concat({
		tostring(state.adviceRev), state.status, tostring(Strings.lang),
		tostring(View.clampDetail(state.detailLevel)),
		tostring(sections.modTiers), tostring(sections.omens), tostring(sections.notes),
		tostring(config.overlay.maxWidth or config.overlay.width), tostring(Font.currentId()), string.format("%.3f", Font.trackingFor()),
	}, "|")
	if state.rowsCacheKey ~= cacheKey or not state.rowsCache then
		state.rowsCacheKey = cacheKey
		state.rowsCache = buildRows()
	end
	local rows = state.rowsCache
	-- Window width follows the content, clamped to the configured bounds. maxWidth is also the
	-- width the rows were wrapped to, so the wrapping and the window cannot disagree.
	local minWidth = px(config.overlay.minWidth or 420)
	local capWidth = px(config.overlay.maxWidth or config.overlay.width)
	width = math.max(minWidth, math.min(rowsWidth(rows), capWidth))
	local height = math.min(rowsHeight(rows), px(config.overlay.maxHeight))

	-- The host's window chrome (title bar + borders) is not part of the drawing area,
	-- so the window has to be requested taller than the panel; measured difference on
	-- this build is ~39 px. Drawing uses the content height, which is exactly the
	-- client area the engine gives us.
	local windowHeight = height + px(config.overlay.chromePad or 40)

	-- Auto-fit the window to the content and keep it centred; the window is only moved
	-- when the target size changes, so the compositor is not fought every frame.
	if state.hwnd and (state.windowHeight ~= windowHeight or state.windowWidth ~= width) then
		state.windowHeight = windowHeight
		state.windowWidth = width
		logLine(string.format("panel content height=%d window=%d rows=%d", height, windowHeight, #rows))
		local x, y = util.centerPosition(state.screenW or width, state.screenH or height,
			width, height, px(config.overlay.marginCenter or 0))
		Win32.moveWindow(state.hwnd, x, y, width, windowHeight)
	end

	setColor(ui.background)
	DrawImage(nil, 0, 0, width, height)
	-- 1px frame: the surface then reads as a panel rather than a floating block of text,
	-- which is how Sidekick's overlay presents itself.
	if ui.border then
		setColor(ui.border)
		DrawImage(nil, 0, 0, width, px(1))
		DrawImage(nil, 0, height - px(1), width, px(1))
		DrawImage(nil, 0, 0, px(1), height)
		DrawImage(nil, width - px(1), 0, px(1), height)
	end
	setColor(ui.gold)
	DrawImage(nil, 0, 0, width, px(2))

	-- Highlight the block header under the cursor so clickability is discoverable.
	local hovered = state.interactive and rowUnderCursor() or nil
	local y = px(8)
	for index, row in ipairs(rows) do
		-- Stop above the two footer lines, otherwise the last rows would be drawn
		-- underneath them in the fully expanded view.
		if y > height - px(68) then
			setColor(ui.dim)
			drawText(px(8), y, "LEFT", 11, ui.font, L("truncated"))
			break
		end
		if hovered == index and row.block then
			setColor(ui.gold)
		else
			setColor(row.color)
		end
		drawText(px(8) + px(row.indent), y, "LEFT", row.size, row.font, row.text)
		-- Optional right-hand part of a row: numbers line up in a column instead of drifting
		-- through the sentence, which is what makes chances and prices readable at a glance.
		if row.right then
			local rightSize = row.right.size or row.size
			local rightFont = row.right.font or row.font
			local rightWidth = textWidth(rightSize, rightFont, row.right.text)
			if row.right.color then
				setColor(row.right.color)
			end
			drawText(width - px(8) - rightWidth, y, "LEFT", rightSize, rightFont, row.right.text)
		end
		-- Advance by the scaled glyph height, not the raw font size, or rows overlap.
		y = y + px(row.size + 7) + (row.block and px(6) or 0)
	end

	setColor(ui.dim)
	-- Three compact footer lines: main keys, block keys, look-and-feel keys.
	drawText(px(8), height - px(44), "LEFT", 11, ui.font,
		L("footer", config.hotkeys.capture, config.hotkeys.togglePanel, config.hotkeys.demo,
			config.hotkeys.interactive, config.hotkeys.quit))
	drawText(px(8), height - px(30), "LEFT", 11, ui.font,
		L("footerSections", config.hotkeys.detail, L(View.detailNameKey(state.detailLevel)),
			config.hotkeys.toggleItem, config.hotkeys.togglePlans, config.hotkeys.toggleOmens))
	drawText(px(8), height - px(16), "LEFT", 11, ui.font,
		L("footerFont", config.hotkeys.fontModifier, config.hotkeys.fontNext,
			config.hotkeys.fontPrev, config.hotkeys.fontModifier,
			config.hotkeys.textSmaller, config.hotkeys.textLarger)
		.. " | " .. config.hotkeys.fontModifier .. "+" .. config.hotkeys.toggleNotes .. " " .. L("sectionNotesShort"))
end

--------------------------------------------------------------------------------
-- MCP bridge mode (one request, one JSON reply)
--------------------------------------------------------------------------------

--- Answer one MCP request and write the reply as JSON.
-- The request is a Lua file returning { tool = "...", args = { ... } }: the bridge
-- writes Lua instead of JSON so the request path needs no parser. The reply is JSON
-- because the bridge is JavaScript.
local function runMcpRequest()
	local Mcp = require("Mcp.api")
	local Json = require("Mcp.json")

	-- The bridge names its files after its own process (POE2CRAFT_MCP_ID), so two bridges -
	-- the MCP server and the crafting site - never read each other's answers. Without the
	-- variable the plain names are used, which keeps manual runs working.
	local id = os.getenv("POE2CRAFT_MCP_ID")
	local suffix = (type(id) == "string" and id ~= "") and ("." .. id) or ""
	local requestFile = "mcp_request" .. suffix .. ".lua"
	local responseFile = "mcp_response" .. suffix .. ".json"

	-- The request is read through the host's own file API, not loadfile: the host resolves
	-- relative names for fileExists/readFile against the game's working directory, while
	-- loadfile uses the process directory, and the two are not the same (the request looked
	-- "missing" although the flag next to it was found).
	local content = util.readFile(requestFile)
	if not content then
		rawWrite(responseFile,
			string.format('{"ok":false,"error":%q}', requestFile .. " could not be read"))
		return
	end
	local chunk, compileErr = loadstring(content, "@" .. requestFile)
	if not chunk then
		rawWrite(responseFile,
			string.format('{"ok":false,"error":%q}', requestFile .. " is not valid Lua: " .. tostring(compileErr)))
		return
	end

	local okLoad, request = pcall(chunk)
	if not okLoad or type(request) ~= "table" then
		rawWrite(responseFile,
			string.format('{"ok":false,"error":%q}',
				requestFile .. " did not return a table: " .. tostring(request)))
		return
	end

	local tool = tostring(request.tool or "")
	local args = request.args or { }
	logLine("mcp request: " .. tool)

	local okCall, result, callErr = pcall(Mcp.call, tool, args)
	local payload
	if not okCall then
		payload = { ok = false, tool = tool, error = tostring(result) }
	elseif callErr then
		payload = { ok = false, tool = tool, error = callErr }
	else
		payload = { ok = true, tool = tool, result = result }
	end

	rawWrite(responseFile, Json.encode(payload, "  "))
	logLine("mcp response written: " .. tool)
end

--------------------------------------------------------------------------------
-- Headless self-test mode
--------------------------------------------------------------------------------

local function runHeadlessTests()
	local harness = require("Tests.runner")
	local passed, failed, report = harness.runAll()
	printf("=== PoE2 Craft Overlay self-test ===")
	printf("%s", report)
	printf("passed=%d failed=%d", passed, failed)
	rawWrite("test_results.txt", report .. "\n" ..
		string.format("RESULT: passed=%d failed=%d\n", passed, failed))
	return failed
end

--------------------------------------------------------------------------------
-- Engine callbacks
--------------------------------------------------------------------------------

function app:OnInit()
	local ok, err = pcall(function()
		state.frame = 0

		if bootError then
			reportError("boot", bootError)
			return
		end

		-- Headless test mode: no renderer, no frame loop dependency. The host does
		-- not terminate itself from here, so tests.ps1 owns the lifecycle and waits
		-- for test_done.flag.
		-- The whole capture path, headless: a sample item is analysed exactly as the F6 hotkey
		-- does it. A crash here is the crash the player sees as a panel that closes, and it can
		-- be reproduced without the game, which is the only way to prove this path at all.
		if util.fileExists("capture_check.flag") then
			local report = { }
			-- The host resolves names against the sources directory, while the samples live one
			-- level up in the project, so both are tried.
			local sample = util.readFile("samples/rare_gloves.txt") or util.readFile("../samples/rare_gloves.txt")
			if not sample then
				report[#report + 1] = "error: the sample item could not be read"
			else
				report[#report + 1] = string.format("sample: %d characters", #sample)
				local ok, err = pcall(analyzeRaw, sample, "sample")
				if not ok then
					report[#report + 1] = "error: " .. tostring(err)
				else
					local lines = state.itemLines or { }
					report[#report + 1] = "analysed ok"
					report[#report + 1] = "name: " .. tostring(lines.header and lines.header.name)
					report[#report + 1] = "base: " .. tostring(lines.header and lines.header.base)
					report[#report + 1] = "properties: " .. tostring(#(lines.properties or { }))
					report[#report + 1] = "modifiers: " .. tostring(#(lines.mods or { }))
					report[#report + 1] = "status: " .. tostring(state.status)
				end
			end
			-- The clipboard half of the path as well: F6 ends in finishCapture, and that is the
			-- part a sample file never touches. Whatever goes wrong here is what the player sees.
			local okClip, clipErr = pcall(finishCapture)
			report[#report + 1] = okClip and "clipboard path: ok"
				or ("clipboard path error: " .. tostring(clipErr))
			local clipLines = state.itemLines or { }
			report[#report + 1] = "after clipboard: properties " .. tostring(#(clipLines.properties or { }))
				.. ", modifiers " .. tostring(#(clipLines.mods or { }))
			-- The other half of what the panel must show: the crafting methods and what they
			-- cost. Reported here so the claim "the panel shows plans with prices" is evidence,
			-- not an assumption.
			local check = state.advice or { }
			local applies = Prices.matchesLeague((ruleset and (ruleset.league or ruleset.leagueShort)) or "",
				config.ui.pricesLeague)
			report[#report + 1] = "prices apply to this league: " .. tostring(applies)
			report[#report + 1] = "plans: " .. tostring(#(check.plans or { }))
			local firstPlan = (check.plans or { })[1]
			if firstPlan then
				report[#report + 1] = "first plan: " .. tostring(firstPlan.id or firstPlan.name or "?")
				local steps = firstPlan.steps or { }
				report[#report + 1] = "steps in the first plan: " .. tostring(#steps)
				for index = 1, math.min(3, #steps) do
					local step = steps[index]
					local unit = applies and Prices.unitPrice(step.en) or nil
					report[#report + 1] = string.format("  step %d: %s, count %s, unit price %s",
						index, tostring(step.en), tostring(step.count), tostring(unit))
				end
			end
			local methods = check.leagueMethods or check.methods
			report[#report + 1] = "league methods: " .. tostring(methods and #methods or 0)
			-- The safety net itself, proved rather than assumed: a capture of nonsense must end
			-- as a status line and leave the panel running, because that is exactly the case the
			-- player hit when the window closed on F6.
			-- The last untested piece, and the one the player actually presses: the real entry
			-- point, with the game window lookup and the synthetic key press. The panel must
			-- survive it and either analyse the clipboard or say why it could not.
			local okBegin = guardedCapture("begin-check", beginCapture)
			report[#report + 1] = "beginCapture survived: " .. tostring(okBegin)
			report[#report + 1] = "pending capture scheduled: " .. tostring(state.pendingCaptureAt ~= nil)
			local survived = guardedCapture("stress", function()
				analyzeRaw("мусор\nне предмет вовсе\n--------\n???", "stress")
			end)
			report[#report + 1] = "nonsense capture survived: " .. tostring(survived)
			report[#report + 1] = "status after nonsense: " .. tostring(state.status)
			rawWrite("capture_check.txt", table.concat(report, "\n") .. "\n")
			rawWrite("capture_check_done.flag", "done\n")
			-- Deliberately NOT returning: the analysis is only half the path, and the panel closes
			-- while drawing the result, which a headless run would never reach. The app carries on
			-- into its frame loop, so a drawing error shows up here exactly as the player sees it.
		end

		if util.fileExists("run_tests.flag") then
			state.testMode = true
			trace("OnInit: entering test mode")

			local okTests, failed = pcall(runHeadlessTests)
			if not okTests then
				rawWrite("test_results.txt",
					"RESULT: passed=0 failed=1\ntest run error: " .. tostring(failed) .. "\n")
				failed = 1
			end

			trace("tests finished, failed=" .. tostring(failed))
			rawWrite("test_done.flag", string.format("failed=%d\n", failed))
			return
		end

		-- Serving mode: the same engine, but it stays alive and answers requests from the frame
		-- loop. The bridge keeps one of these running, so capturing an item no longer starts a
		-- process - and therefore no longer flashes a window over the game.
		if util.fileExists("mcp_serve.flag") then
			state.mcpMode = true
			state.serveMode = true
			trace("OnInit: entering serving mode")
			pcall(function()
				local own = Win32.findOwnWindow(APP_NAME, config.overlay.hostImage)
				if own and own.hwnd then
					Win32.moveWindow(own.hwnd, -32000, -32000, 2, 2)
					Win32.showWindow(own.hwnd, 0)
					logLine("serving mode: window hidden")
				end
			end)
		end

		-- MCP mode: answer exactly one request and write the reply as JSON. Like the
		-- test mode nothing is rendered, and the bridge (mcp/server.js) owns the process
		-- lifecycle: it waits for mcp_done.flag and then closes the host.
		if util.fileExists("mcp.flag") then
			state.mcpMode = true

			-- The host creates its own window a moment after this code runs, and the frame handler
			-- that would hide it never gets there: an MCP run answers and exits in a fraction of a
			-- second. So the window is waited for here and hidden by this process itself - only its
			-- own window, found by our own title and image, never anything belonging to anyone else.
			pcall(function()
				for attempt = 1, 20 do
					local own = Win32.findOwnWindow(APP_NAME, config.overlay.hostImage)
					if own and own.hwnd then
						Win32.moveWindow(own.hwnd, -32000, -32000, 2, 2)
						Win32.showWindow(own.hwnd, 0)
						logLine("engine mode: window hidden before answering")
						return
					end
					-- A short wait without Sleep(): the host has no such function, and a busy wait of a
					-- few milliseconds is nothing next to starting the process itself.
					local started = os.clock()
					while os.clock() - started < 0.015 do end
				end
				logLine("engine mode: window never appeared, nothing to hide")
			end)

	-- The bridge starts the host once per request, and its window would otherwise flash over the
	-- game every time the page asks for numbers. In this mode the window is only in the way: the
	-- answer goes through a file, so nothing has to be visible.
	if Win32 and Win32.ShowWindow and state.hwnd then
		local hidden = pcall(Win32.ShowWindow, state.hwnd, 0)
		logLine("mcp mode: host window hidden (" .. tostring(hidden) .. ")")
	end
			trace("OnInit: entering MCP mode")
			-- Engine mode must be invisible: the site spawns this host for every request, and
			-- a window that appears each time flashes over the game. It is pushed off screen
			-- and hidden before anything else happens.
			pcall(function()
				local own = Win32.findOwnWindow(APP_NAME, config.overlay.hostImage)
				if own and own.hwnd then
					Win32.moveWindow(own.hwnd, -32000, -32000, 2, 2)
					Win32.showWindow(own.hwnd, 0)
					logLine("engine mode: window hidden (no flash over the game)")
				else
					logLine("engine mode: own window not found, nothing to hide")
				end
			end)
			local bridgeId = os.getenv("POE2CRAFT_MCP_ID")
			local bridgeSuffix = (type(bridgeId) == "string" and bridgeId ~= "") and ("." .. bridgeId) or ""
			local okRequest, requestErr = pcall(runMcpRequest)
			if not okRequest then
				rawWrite("mcp_response" .. bridgeSuffix .. ".json",
					string.format('{"ok":false,"error":%q}', tostring(requestErr)))
			end
			rawWrite("mcp_done" .. bridgeSuffix .. ".flag", "done\n")
			trace("MCP request finished")
			return
		end

		-- Verification modes hold the window open for a while; src/probe_hold.txt
		-- overrides the default (~5 s) so a comparison can be studied on screen.
		local holdText = util.readFile("probe_hold.txt")
		local holdSeconds = tonumber(util.trim(holdText or ""))
		if holdSeconds and holdSeconds > 0 then
			state.holdMs = math.floor(holdSeconds * 1000)
			logLine(string.format("probe hold: %.0f s", holdSeconds))
		end

		state.renderCheck = util.fileExists("render_check.flag")
		state.fontProbe = util.fileExists("font_probe.flag")
		state.fontCompare = util.fileExists("font_compare.flag")
		state.fontShortlist = util.fileExists("font_shortlist.flag")
		-- src/interactive.flag starts the window clickable, so the panel can be poked
		-- straight away (block headers fold on click). F9 switches back to click-through.
		if util.fileExists("interactive.flag") then
			state.interactive = true
			logLine("interactive mode requested by interactive.flag")
		end
		if state.fontShortlist then
			state.fontCompare = true
		end
		if state.renderCheck or state.fontProbe or state.fontCompare then
			state.holdStart = GetTime()
		end
		if state.fontProbe or state.fontCompare then
			-- Both probes reuse the render-check machinery (screenshot + quit).
			state.renderCheck = true
			logLine(state.fontCompare and "font comparison mode enabled" or "font probe mode enabled")
		end
		logLine(string.format("=== session start | %s / %s | renderCheck=%s ===",
			tostring(jit.version), tostring(jit.arch), tostring(state.renderCheck)))
		logLine("work dir: " .. tostring(GetWorkDir()))

		RenderInit("DPI_AWARE")

		-- Fonts are DPI-scaled by the host; capture the factor so all layout maths
		-- (row advance, panel box, wrap width) uses the same units.
		if GetScreenScale then
			local okScale, scale = pcall(GetScreenScale)
			if okScale and type(scale) == "number" and scale > 0 then
				uiScale = scale
			end
		end
		logLine("render scale: " .. tostring(uiScale))

		-- Display state: interface language, glyph atlas, detail level, section
		-- toggles and the screen size used to keep the panel centred.
		-- The interface is English only, so nothing is loaded here.
		state.detailLevel = View.clampDetail(config.ui.detailLevel)
		state.sections = View.sectionsFor(config.ui.sections)
		state.status = L("statusHover", config.hotkeys.capture)

		local okScreen, screenW, screenH = pcall(GetScreenSize)
		if okScreen and type(screenW) == "number" then
			state.screenW = screenW
			state.screenH = (type(screenH) == "number" and screenH) or screenW
			logLine(string.format("screen: %s x %s", tostring(state.screenW), tostring(state.screenH)))
		end

		Font.use(Prefs.get("fontVariant") or config.ui.fontVariant)
		Font.setTracking(Prefs.get("letterSpacing") or config.ui.letterSpacing)
		local okAtlas, atlasErr = Font.loadAtlas()
		logLine(string.format("interface language=%s, glyph atlas=%s (%s)",
			Strings.lang, tostring(okAtlas ~= nil), tostring(atlasErr or "ok")))
		logLine(string.format("font variant: %s, tracking %.3f", tostring(Font.currentId()), Font.trackingFor()))
		if not okAtlas then
			logLine("WARNING: running without the Cyrillic atlas; the panel will be ASCII only")
		end

		local windows = Win32.listWindows()
		logLine(string.format("visible windows: %d", #windows))
		for _, win in ipairs(windows) do
			logLine(string.format("  win '%s' pid=%d image=%s", win.title, win.pid, tostring(win.image)))
		end
		local game = Win32.findGameWindow(config.capture.windowImageNames, nil)
		logLine(game and ("game window detected: " .. game.title)
			or "game window NOT detected (clipboard mode still works)")
	end)

	if not ok then
		reportError("OnInit", err)
	end
end

--- Runs one step of a capture without letting it take the panel down.
-- An unexpected item, a failing synthetic key press or a parse of something odd must end as a
-- status line: a crafting helper that closes because its input was strange is worse than one
-- that says what it did not like.
function guardedCapture(what, fn)
	local ok, err = pcall(fn)
	if not ok then
		local message = tostring(err)
		logLine("capture step '" .. what .. "' failed: " .. message)
		state.status = ((Strings.lang == "ru") and "Ошибка захвата: " or "Capture error: ") .. message
		state.statusColor = config.ui.bad
		state.pendingCaptureAt = nil
	end
	return ok
end
function app:OnFrame()
	state.frame = state.frame + 1
	-- The host creates its own window a moment AFTER OnInit runs, so the first attempt to style
	-- it finds nothing and the panel would never be made transparent, click-through or placed.
	-- The styling is therefore retried on the first frames, until the window is finally found.
	if not state.hwnd and state.frame <= 240 then
		applyOverlayStyle()
	end
	-- Serving mode: at most one request per frame. The bridge writes a request file and waits
	-- for the answer, so the host never blocks and never has to be restarted. The content is
	-- remembered, so the same request is not answered twice from the same file.
	-- A panel that is already running becomes the engine for the site as soon as the bridge asks
	-- for it: the flag is noticed here, on any frame. This is what makes one process serve both
	-- roles - computing and showing - instead of a second engine being started for the site.
	if not state.serveMode and util.fileExists("mcp_serve.flag") then
		state.serveMode = true
		logLine("serving mode: joined on demand (the panel also answers the site)")
	end
	if state.serveMode then
		local content = util.readFile("mcp_serve_request.lua")
		if content and content ~= state.serveHandled then
			state.serveHandled = content
			local payload
			local okLoad, request = pcall(function()
				local chunk = loadstring(content, "@mcp_serve_request.lua")
				return chunk and chunk()
			end)
			if not okLoad or type(request) ~= "table" then
				payload = { ok = false, error = "the serving request was not a table" }
			else
				local Mcp = require("Mcp.api")
				local tool = tostring(request.tool or "")
				local okCall, result, callErr = pcall(Mcp.call, tool, request.args or { })
				if not okCall then
					payload = { ok = false, tool = tool, error = tostring(result) }
				elseif callErr then
					payload = { ok = false, tool = tool, error = callErr }
				else
					payload = { ok = true, tool = tool, result = result }
				end
				logLine("serving mode: answered " .. tool)
			end
			rawWrite("mcp_serve_response.json", require("Mcp.json").encode(payload))
		end
	end
	-- The tray window has its own messages (icon clicks, menu choices), so its queue is
	-- drained here, once per frame.
	pcall(Tray.pump)
	-- Engine mode: hide the host window as soon as it exists. OnInit cannot do it because
	-- the window is created after OnInit runs, and a visible one flashes over the game every
	-- time the site asks the engine a question.

	if state.mcpMode and state.frame <= 10 then
		pcall(function()
			local ownWindow = Win32.findOwnWindow(APP_NAME, config.overlay.hostImage)
			if ownWindow and ownWindow.hwnd then
				Win32.moveWindow(ownWindow.hwnd, -32000, -32000, 2, 2)
				Win32.showWindow(ownWindow.hwnd, 0)
				if state.frame == 10 then
					logLine("engine mode: window hidden (no flash over the game)")
				end
			end
		end)
	end
	SetDrawLayer(1000)
	SetViewport()

	-- Mode logic first, drawing second: a drawing error must never stop the
	-- verification hooks (screenshot / quit). An early font probe hit exactly that.
	local okMode, modeErr = pcall(function()
		-- Agent mode has no panel to look at, so a periodic line is the only proof that the
		-- process is alive and still polling the hotkey while the game has focus.
		if config.overlay.enabled == false and state.frame % 1200 == 0 then
			logLine(string.format("capture agent alive: frame=%d, watching %s (image) and %s (clipboard)",
				state.frame, tostring(config.hotkeys.grabImage), tostring(config.hotkeys.capture)))
		end

		-- Verification hooks run first: any failure below must never stop the automated
		-- screenshot/quit path, which is how this overlay is tested.
		if state.renderCheck then
			if state.frame == 30 and not state.fontCompare and not state.fontProbe then
				analyzeDemo()
			elseif state.frame >= 120 and not state.shotTaken then
				-- Not "== 120": publishing the capture (files plus starting the local site)
				-- can push the frame loop past that exact frame, and a missed screenshot
				-- used to fail the whole verification silently.
				state.shotTaken = true
				logLine("render check screenshot: " .. tostring(pcall(TakeScreenshot)))
			elseif state.holdStart and GetTime() - state.holdStart >= (state.holdMs or 5000) then
				quitSelf("render check done")
				return
			end
		end

		if state.frame == 3 then
			applyOverlayStyle()
			setupTray()
		end

		if state.pendingCaptureAt and GetTime() >= state.pendingCaptureAt then
			guardedCapture("clipboard", finishCapture)
		end

		-- Click a block header to fold it. Only in interactive mode: in overlay mode the
		-- window is click-through by design.
		if state.interactive then
			local down = Win32.leftButtonDown and Win32.leftButtonDown() or false
			if down and not state.mouseDown then
				pcall(handlePanelClick)
			end
			state.mouseDown = down
		else
			state.mouseDown = false
		end

		-- Hotkeys. Font-preview chords are checked first: while the modifier is held the
		-- plain F-key handlers stay out of the way, otherwise Ctrl+F1 would also cycle
		-- the detail level.
		local ctrlHeld = Win32.isKeyDown(Win32.VK.CTRL)
		if hotkeyPressed(config.hotkeys.fontNext, config.hotkeys.fontModifier) then
			cycleFont(1)
		elseif hotkeyPressed(config.hotkeys.fontPrev, config.hotkeys.fontModifier) then
			cycleFont(-1)
		elseif hotkeyPressed(config.hotkeys.fontSave, config.hotkeys.fontModifier) then
			saveFontChoice()
		elseif hotkeyPressed(config.hotkeys.textSmaller, config.hotkeys.fontModifier) then
			setTextScale((state.textScale or 1) - 0.05)
		elseif hotkeyPressed(config.hotkeys.textLarger, config.hotkeys.fontModifier) then
			setTextScale((state.textScale or 1) + 0.05)
		elseif hotkeyPressed(config.hotkeys.letterTighter, config.hotkeys.fontModifier) then
			setLetterSpacing(-0.02)
		elseif hotkeyPressed(config.hotkeys.letterLooser, config.hotkeys.fontModifier) then
			setLetterSpacing(0.02)
		elseif hotkeyFromSpec(config.hotkeys.grabImage) then
			grabImageItem()
		elseif not ctrlHeld and hotkeyPressed(config.hotkeys.capture) then
			guardedCapture("begin", beginCapture)
		elseif not ctrlHeld and hotkeyPressed(config.hotkeys.demo) then
			analyzeDemo()
		elseif not ctrlHeld and hotkeyPressed(config.hotkeys.togglePanel) then
			state.panelVisible = not state.panelVisible
		elseif not ctrlHeld and hotkeyPressed(config.hotkeys.clear) then
			state.advice = nil
			state.status = L("statusCleared", config.hotkeys.capture)
			state.statusColor = config.ui.dim

		elseif not ctrlHeld and hotkeyPressed(config.hotkeys.detail) then
			state.detailLevel = View.cycleDetail(state.detailLevel)
			state.status = L("statusDetail", L(View.detailNameKey(state.detailLevel)))
			state.statusColor = config.ui.gold
			logLine("detail level: " .. tostring(state.detailLevel))
		elseif not ctrlHeld and hotkeyPressed(config.hotkeys.toggleItem) then
			toggleBlock("item", "sectionItem")
		elseif not ctrlHeld and hotkeyPressed(config.hotkeys.togglePlans) then
			toggleBlock("plans", "sectionPlans")
		elseif not ctrlHeld and hotkeyPressed(config.hotkeys.toggleOmens) then
			toggleBlock("league", "sectionOmens")
		elseif hotkeyPressed(config.hotkeys.toggleNotes, config.hotkeys.fontModifier) then
			toggleBlock("notes", "sectionNotesShort")
		elseif hotkeyPressed(config.hotkeys.toggleMods, config.hotkeys.fontModifier) then
			toggleBlock("modTiers", "sectionMods")
		elseif not ctrlHeld and hotkeyPressed(config.hotkeys.interactive) then
			state.interactive = not state.interactive
			applyOverlayStyle()
			state.status = state.interactive
				and L("statusClickable", config.hotkeys.interactive)
				or L("statusOverlay")
			state.statusColor = config.ui.dim
		elseif not ctrlHeld and hotkeyPressed(config.hotkeys.reapply) then
			applyOverlayStyle()
		elseif not ctrlHeld and hotkeyPressed(config.hotkeys.quit) then
			quitSelf("quit by hotkey")
		end
	end)

	if not okMode then
		reportError("OnFrame/mode", modeErr)
	end

	local okDraw, drawErr = pcall(function()
		if state.fontCompare then
			drawFontCompare()
		elseif state.fontProbe then
			drawFontProbe()
		elseif state.panelVisible and config.overlay.enabled ~= false then
			-- Panel disabled (capture-agent mode): the hotkeys above still work, and every
			-- number is shown on the local site instead.
			drawPanel()
		end
	end)

	if not okDraw then
		reportError("OnFrame/draw", drawErr)
	end
end

function app:CanExit()
	return true
end

function app:OnExit()
	if config and not state.testMode then
		logLine("=== session end ===")
	end
end

if bootError then
	pcall(ConPrintf, "[PoE2 Craft Overlay] module load failed: %s", bootError)
end
