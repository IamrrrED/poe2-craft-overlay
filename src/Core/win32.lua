-- PoE2 Craft Overlay : Core/win32.lua
-- Win32 glue through LuaJIT FFI. Kept in one place so the rest of the overlay stays
-- pure Lua and testable headless.
--
-- Why FFI instead of the engine API:
--  * global hotkeys must work while the *game* owns the keyboard focus, so we poll
--    GetAsyncKeyState (the engine's IsKeyDown only fires for our own window),
--  * the overlay needs WS_EX_TRANSPARENT / WS_EX_TOPMOST / WS_EX_NOACTIVATE,
--  * sending the in-game "copy item" keystroke has to reach the game window.

local ffi = require("ffi")

ffi.cdef [[
	typedef void*    HWND;
	typedef void*    HANDLE;
	typedef void*    HINSTANCE;
	typedef unsigned long  DWORD;
	typedef int            BOOL;
	typedef unsigned short WCHAR;
	typedef unsigned char  BYTE;
	typedef unsigned int   UINT;
	typedef int64_t        LONG_PTR;
	typedef LONG_PTR       LPARAM;
	typedef uintptr_t      WPARAM;
	typedef unsigned int   ULONG_PTR;

	HWND  GetForegroundWindow(void);
	HWND  GetActiveWindow(void);
	BOOL  EnumWindows(BOOL (*lpEnumFunc)(HWND, LPARAM), LPARAM lParam);
	int   GetWindowTextW(HWND hWnd, WCHAR* lpString, int nMaxCount);
	int   GetWindowTextLengthW(HWND hWnd);
	BOOL  IsWindowVisible(HWND hWnd);
	DWORD GetWindowThreadProcessId(HWND hWnd, DWORD* lpdwProcessId);
	HANDLE OpenProcess(DWORD dwDesiredAccess, BOOL bInheritHandle, DWORD dwProcessId);
	BOOL  QueryFullProcessImageNameW(HANDLE hProcess, DWORD dwFlags, WCHAR* lpExeName, DWORD* lpdwSize);
	BOOL  CloseHandle(HANDLE hObject);

	LONG_PTR GetWindowLongPtrW(HWND hWnd, int nIndex);
	LONG_PTR SetWindowLongPtrW(HWND hWnd, int nIndex, LONG_PTR dwNewLong);
	BOOL  SetLayeredWindowAttributes(HWND hWnd, unsigned int crKey, BYTE bAlpha, DWORD dwFlags);
	BOOL  SetWindowPos(HWND hWnd, HWND hWndInsertAfter, int X, int Y, int cx, int cy, UINT uFlags);
	BOOL  ShowWindow(HWND hWnd, int nCmdShow);
    void* GetConsoleWindow(void);
	BOOL  SetForegroundWindow(HWND hWnd);
	short GetAsyncKeyState(int vKey);
	short GetKeyState(int vKey);
	void  keybd_event(BYTE bVk, BYTE bScan, DWORD dwFlags, ULONG_PTR dwExtraInfo);
	BOOL  GetWindowRect(HWND hWnd, void* lpRect);
	BOOL  GetCursorPos(void* lpPoint);
	BOOL  ScreenToClient(HWND hWnd, void* lpPoint);
	DWORD GetLastError(void);
]]

-- POINT is declared once: ffi.cdef rejects a second definition if the type already
-- exists, so this is guarded for the case where the host predeclares it.
pcall(ffi.cdef, [[
	typedef struct { long x; long y; } POINT;
]])

local Win32 = { }
local user32 = ffi.load("user32")
local kernel32 = ffi.load("kernel32")

Win32.user32 = user32

-- Window style constants.
Win32.GWL_EXSTYLE = -20
Win32.WS_EX_TOPMOST = 0x00000008
Win32.WS_EX_TRANSPARENT = 0x00000020
Win32.WS_EX_TOOLWINDOW = 0x00000080
Win32.WS_EX_LAYERED = 0x00080000
Win32.WS_EX_NOACTIVATE = 0x08000000

Win32.LWA_ALPHA = 0x2
Win32.LWA_COLORKEY = 0x1
Win32.SWP_NOSIZE = 0x1
Win32.SWP_NOMOVE = 0x2
Win32.SWP_NOACTIVATE = 0x10
Win32.SWP_SHOWWINDOW = 0x40
Win32.HWND_TOPMOST = ffi.cast("HWND", -1)
Win32.HWND_NOTOPMOST = ffi.cast("HWND", -2)

-- Virtual key codes we care about.
Win32.VK = {
	F1 = 0x70, F2 = 0x71, F3 = 0x72, F4 = 0x73, F5 = 0x74, F6 = 0x75,
	F7 = 0x76, F8 = 0x77, F9 = 0x78, F10 = 0x79, F11 = 0x7A, F12 = 0x7B,
	-- CTRL/SHIFT/ALT are the names used in Data/config.lua; CONTROL/ESCAPE are kept as
	-- aliases because both spellings appear in this codebase.
	CTRL = 0x11, CONTROL = 0x11,
	SHIFT = 0x10,
	ALT = 0x12,
	ESC = 0x1B, ESCAPE = 0x1B,
	SPACE = 0x20,
	C = 0x43,
}

Win32.KEYEVENTF_KEYUP = 0x0002

--- Convert a Lua (ASCII) string into a NUL-terminated wide buffer.
function Win32.toWide(s)
	local buffer = ffi.new("WCHAR[?]", #s + 1)
	for i = 1, #s do
		buffer[i - 1] = s:byte(i)
	end
	return buffer
end

--- Read a wide (UTF-16LE) NUL-terminated buffer back into a Lua string (ASCII/UTF-8 passthrough).
local function fromWide(buffer, maxChars)
	local chars = { }
	for i = 0, maxChars - 1 do
		local code = buffer[i]
		if code == 0 then break end
		if code < 128 then
			chars[#chars + 1] = string.char(code)
		else
			-- Latin-1 fallback; window titles are ASCII for our purposes.
			chars[#chars + 1] = "?"
		end
	end
	return table.concat(chars)
end

function Win32.getWindowTitle(hwnd)
	local length = user32.GetWindowTextLengthW(hwnd)
	if length <= 0 then return "" end
	local buffer = ffi.new("WCHAR[?]", length + 2)
	user32.GetWindowTextW(hwnd, buffer, length + 1)
	return fromWide(buffer, length + 1)
end

function Win32.getWindowPid(hwnd)
	local pid = ffi.new("DWORD[1]")
	user32.GetWindowThreadProcessId(hwnd, pid)
	return tonumber(pid[0])
end

function Win32.getProcessImageName(pid)
	local PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
	local handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid)
	if handle == nil then return nil end
	local buffer = ffi.new("WCHAR[512]")
	local size = ffi.new("DWORD[1]", 512)
	local ok = kernel32.QueryFullProcessImageNameW(handle, 0, buffer, size)
	kernel32.CloseHandle(handle)
	if ok == 0 then return nil end
	return fromWide(buffer, 511)
end

--- Enumerate visible top-level windows.
-- @return list of { hwnd = cdata, title = string, pid = number, image = string|nil }
function Win32.listWindows()
	local found = { }
	local callback = ffi.cast("BOOL (*)(HWND, LPARAM)", function(hwnd)
		if user32.IsWindowVisible(hwnd) ~= 0 then
			local title = Win32.getWindowTitle(hwnd)
			if title ~= "" then
				local pid = Win32.getWindowPid(hwnd)
				found[#found + 1] = {
					hwnd = hwnd,
					title = title,
					pid = pid,
					image = Win32.getProcessImageName(pid),
				}
			end
		end
		return true
	end)
	user32.EnumWindows(callback, 0)
	return found
end

--- Find a window whose process image matches one of `imageNames`
-- (e.g. "PathOfExile2.exe"), optionally requiring a title substring.
-- Refuses to guess: with no process names supplied it returns nothing rather than
-- handing back an arbitrary window (styling/killing a foreign process would be a
-- catastrophic failure mode).
function Win32.findGameWindow(imageNames, titleSubstring)
	local wanted = { }
	for _, name in ipairs(imageNames or { }) do
		wanted[name:lower()] = true
	end
	if not next(wanted) then
		return nil
	end

	for _, win in ipairs(Win32.listWindows()) do
		local image = win.image and win.image:lower() or ""
		local imageOk = false
		for name in pairs(wanted) do
			if image:sub(-#name) == name then
				imageOk = true
				break
			end
		end
		local titleOk = true
		if titleSubstring then
			titleOk = win.title:lower():find(titleSubstring:lower(), 1, true) ~= nil
		end
		if imageOk and titleOk then
			return win
		end
	end
	return nil
end

--- Find a window by exact title, optionally restricted to a process image suffix.
-- Used to locate the overlay's own window (never a foreign one).
function Win32.findOwnWindow(title, imageSuffix)
	for _, win in ipairs(Win32.listWindows()) do
		if win.title == title then
			if not imageSuffix then
				return win
			end
			local image = (win.image or ""):lower()
			if image:sub(-#imageSuffix) == imageSuffix:lower() then
				return win
			end
		end
	end
	return nil
end

--- Global key state (works while another process has focus).
function Win32.isKeyDown(vk)
	if type(vk) ~= "number" then
		return false
	end
	return user32.GetAsyncKeyState(vk) < 0
end

--- Is the left mouse button held? (0x01 = VK_LBUTTON)
function Win32.leftButtonDown()
	return user32.GetAsyncKeyState(0x01) < 0
end

--- Cursor position in screen coordinates, or nil.
function Win32.cursorPos()
	local point = ffi.new("POINT[1]")
	if user32.GetCursorPos(point) == 0 then
		return nil
	end
	return tonumber(point[0].x), tonumber(point[0].y)
end

--- Convert screen coordinates to client coordinates of a window.
function Win32.screenToClient(hwnd, x, y)
	if not hwnd then
		return nil
	end
	local point = ffi.new("POINT[1]")
	point[0].x = math.floor(x or 0)
	point[0].y = math.floor(y or 0)
	if user32.ScreenToClient(hwnd, point) == 0 then
		return nil
	end
	return tonumber(point[0].x), tonumber(point[0].y)
end

--- Guard every window-style entry point: callers must pass a raw HWND (cdata),
-- not the window-info table returned by listWindows/find*.
local function checkHwnd(hwnd)
	if hwnd == nil then
		return false, "нет окна"
	end
	if type(hwnd) ~= "cdata" then
		return false, "нужен HWND (cdata), получено " .. type(hwnd)
	end
	return true
end

--- Style our own window as a click-through, always-on-top overlay.
-- @param hwnd cdata raw HWND
-- @param opts table {
--   alpha = 0..255, clickThrough = bool, topmost = bool, noActivate = bool,
--   keyColor = { r, g, b } (0..255) - pixels of this exact colour become fully
--              transparent AND click-through, which is how the panel stays small
--              while the host keeps the window at full render-surface size.
-- }
function Win32.makeOverlay(hwnd, opts)
	opts = opts or { }
	local okHwnd, hwndErr = checkHwnd(hwnd)
	if not okHwnd then return false, hwndErr end

	local style = user32.GetWindowLongPtrW(hwnd, Win32.GWL_EXSTYLE)
	local want = style
	want = bit.bor(want, Win32.WS_EX_LAYERED)
	if opts.topmost ~= false then want = bit.bor(want, Win32.WS_EX_TOPMOST) end
	if opts.clickThrough ~= false then want = bit.bor(want, Win32.WS_EX_TRANSPARENT) end
	-- A tool window keeps the agent out of the taskbar and out of Alt+Tab, which is what
	-- "runs in the background with only a tray icon" needs.
	if opts.toolWindow then want = bit.bor(want, Win32.WS_EX_TOOLWINDOW) end
	if opts.noActivate ~= false then
		want = bit.bor(want, Win32.WS_EX_NOACTIVATE, Win32.WS_EX_TOOLWINDOW)
	end
	user32.SetWindowLongPtrW(hwnd, Win32.GWL_EXSTYLE, want)

	local flags = Win32.LWA_ALPHA
	local key = 0
	local keyNote = "alpha"
	if opts.keyColor then
		local c = opts.keyColor
		key = bit.bor(c.r or 0, bit.lshift(c.g or 0, 8), bit.lshift(c.b or 0, 16))
		flags = bit.bor(flags, Win32.LWA_COLORKEY)
		keyNote = string.format("colorkey #%02X%02X%02X", c.r or 0, c.g or 0, c.b or 0)
	end
	user32.SetLayeredWindowAttributes(hwnd, key, opts.alpha or 235, flags)
	user32.SetWindowPos(hwnd, Win32.HWND_TOPMOST, 0, 0, 0, 0,
		bit.bor(Win32.SWP_NOMOVE, Win32.SWP_NOSIZE, Win32.SWP_NOACTIVATE))
	return true, string.format("exstyle 0x%X -> 0x%X (%s)", style, want, keyNote)
end

--- Undo overlay styling (interactive mode: window can be focused and clicked).
function Win32.makeInteractive(hwnd)
	local okHwnd, hwndErr = checkHwnd(hwnd)
	if not okHwnd then return false, hwndErr end
	local style = user32.GetWindowLongPtrW(hwnd, Win32.GWL_EXSTYLE)
	local want = bit.band(style, bit.bnot(bit.bor(Win32.WS_EX_TRANSPARENT, Win32.WS_EX_NOACTIVATE)))
	user32.SetWindowLongPtrW(hwnd, Win32.GWL_EXSTYLE, want)
	-- Drop the colour key too, otherwise the window stays partially invisible.
	user32.SetLayeredWindowAttributes(hwnd, 0, 255, Win32.LWA_ALPHA)
	return true, string.format("exstyle 0x%X -> 0x%X", style, want)
end

--- Show or hide a window. SW_HIDE = 0, SW_SHOW = 5, SW_SHOWNA = 8.
-- Used by the engine mode, where the host must never appear on screen.
function Win32.showWindow(hwnd, command)
	if not hwnd then
		return false
	end
	return user32.ShowWindow(hwnd, command or 0) ~= 0
end

function Win32.moveWindow(hwnd, x, y, w, h)
	local okHwnd = checkHwnd(hwnd)
	if not okHwnd then return false end
	return user32.SetWindowPos(hwnd, Win32.HWND_TOPMOST, x, y, w, h,
		bit.bor(Win32.SWP_NOACTIVATE, Win32.SWP_SHOWWINDOW)) ~= 0
end

--- Resize the window without moving it or stealing focus (used for auto-height).
function Win32.resizeWindow(hwnd, w, h)
	local okHwnd = checkHwnd(hwnd)
	if not okHwnd then return false end
	return user32.SetWindowPos(hwnd, Win32.HWND_TOPMOST, 0, 0, w, h,
		bit.bor(Win32.SWP_NOMOVE, Win32.SWP_NOACTIVATE, Win32.SWP_SHOWWINDOW)) ~= 0
end

--- Send Ctrl+C to the foreground window (the game's "copy item" keystroke).
-- The game must already be foreground; we deliberately do not steal focus.
--- Hides the host's own console window.
-- That console is what the player sees flashing the moment the engine starts: the host creates it
-- before our Lua runs, so it is hidden here, as the very first thing every mode does.
function Win32.hideConsole()
	local ok, console = pcall(function()
		return kernel32.GetConsoleWindow()
	end)
	if ok and console and console ~= nil then
		pcall(function()
			user32.ShowWindow(console, 0)
		end)
		return true
	end
	return false
end
function Win32.sendCtrlC()
	user32.keybd_event(Win32.VK.CONTROL, 0, 0, 0)
	user32.keybd_event(Win32.VK.C, 0, 0, 0)
	user32.keybd_event(Win32.VK.C, 0, Win32.KEYEVENTF_KEYUP, 0)
	user32.keybd_event(Win32.VK.CONTROL, 0, Win32.KEYEVENTF_KEYUP, 0)
	return true
end

function Win32.getForegroundWindow()
	return user32.GetForegroundWindow()
end

return Win32
