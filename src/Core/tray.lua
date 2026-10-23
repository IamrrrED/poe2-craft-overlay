-- PoE2 Craft Overlay : Core/tray.lua
-- A system-tray icon for the capture agent, so the overlay can live in the background
-- with no panel, no taskbar button and no window on screen.
--
-- The host owns its own window and its own message loop, so this module creates a second,
-- never-shown window of its own to receive the tray callbacks, and pumps that window's
-- messages from the frame loop (Tray.pump). Everything is defensive: if any of it fails on
-- a given machine, the agent keeps working and only the icon is missing.
--
-- Menu: open the crafting site, capture the hovered item (image), capture via clipboard,
-- quit. Double-clicking the icon opens the site.

local ffi = require("ffi")

local Tray = { }

local user32, shell32, kernel32
local okLoad, loadError = pcall(function()
	user32 = ffi.load("user32")
	shell32 = ffi.load("shell32")
	kernel32 = ffi.load("kernel32")
end)
if okLoad then
	Tray.available = true
else
	Tray.available = false
	Tray.reason = "could not load user32/shell32: " .. tostring(loadError)
end

-- Declarations are added one at a time: a single pcall around the whole block would be
-- aborted by the first name that is already declared elsewhere. Everything the icon needs
-- is declared here rather than assumed from win32.lua, because that module may not have
-- been required yet when this one loads - a missing base type silently drops the whole
-- declaration that uses it.
local function def(text)
	pcall(ffi.cdef, text)
end

def [[ typedef void *HWND; ]]
def [[ typedef void *HINSTANCE; ]]
def [[ typedef void *HICON; ]]
def [[ typedef void *HMENU; ]]
def [[ typedef void *HCURSOR; ]]
def [[ typedef void *HBRUSH; ]]
def [[ typedef unsigned long DWORD; ]]
def [[ typedef unsigned int UINT; ]]
def [[ typedef unsigned long long WPARAM; ]]
def [[ typedef long long LPARAM; ]]
def [[ typedef long long LRESULT; ]]
def [[ typedef int BOOL; ]]
def [[ typedef unsigned long long UINT_PTR; ]]
def [[ typedef unsigned short WCHAR; ]]
def [[ typedef WCHAR *LPWSTR; ]]
def [[ typedef const WCHAR *LPCWSTR; ]]
def [[ typedef struct { long x; long y; } POINT; ]]
def [[ typedef struct { long left; long top; long right; long bottom; } RECT; ]]
def [[ typedef LRESULT (*WNDPROC)(HWND, UINT, WPARAM, LPARAM); ]]
def [[ typedef struct {
	UINT      style;
	WNDPROC   lpfnWndProc;
	int       cbClsExtra;
	int       cbWndExtra;
	HINSTANCE hInstance;
	HICON     hIcon;
	HCURSOR   hCursor;
	HBRUSH    hbrBackground;
	LPCWSTR   lpszMenuName;
	LPCWSTR   lpszClassName;
} WNDCLASSW; ]]
def [[ typedef struct {
	HWND   hwnd;
	UINT   message;
	WPARAM wParam;
	LPARAM lParam;
	DWORD  time;
	POINT  pt;
	DWORD  lPrivate;
} MSG; ]]
def [[ HINSTANCE GetModuleHandleW(LPCWSTR lpModuleName); ]]
def [[ DWORD GetLastError(void); ]]
def [[ unsigned short RegisterClassW(const WNDCLASSW *lpWndClass); ]]
def [[ int MultiByteToWideChar(UINT CodePage, DWORD dwFlags, const char *lpMultiByteStr, int cbMultiByte, LPWSTR lpWideCharStr, int cchWideChar); ]]
def [[ HWND CreateWindowExW(DWORD dwExStyle, LPCWSTR lpClassName, LPCWSTR lpWindowName, DWORD dwStyle, int X, int Y, int nWidth, int nHeight, HWND hWndParent, HMENU hMenu, HINSTANCE hInstance, void *lpParam); ]]
def [[ LRESULT DefWindowProcW(HWND hWnd, UINT Msg, WPARAM wParam, LPARAM lParam); ]]
def [[ BOOL DestroyWindow(HWND hWnd); ]]
def [[ BOOL PeekMessageW(MSG *lpMsg, HWND hWnd, UINT wMsgFilterMin, UINT wMsgFilterMax, UINT wRemoveMsg); ]]
def [[ BOOL TranslateMessage(const MSG *lpMsg); ]]
def [[ LRESULT DispatchMessageW(const MSG *lpMsg); ]]
def [[ HMENU CreatePopupMenu(void); ]]
def [[ BOOL AppendMenuW(HMENU hMenu, UINT uFlags, UINT_PTR uIDNewItem, LPCWSTR lpNewItem); ]]
def [[ BOOL DestroyMenu(HMENU hMenu); ]]
def [[ int TrackPopupMenu(HMENU hMenu, UINT uFlags, int x, int y, int nReserved, HWND hWnd, const RECT *prcRect); ]]
def [[ BOOL SetForegroundWindow(HWND hWnd); ]]
def [[ BOOL GetCursorPos(POINT *lpPoint); ]]
def [[ HICON LoadIconW(HINSTANCE hInstance, LPCWSTR lpIconName); ]]

-- The structure must be known before the function that takes a pointer to it: C parsing
-- stops at an unknown type name, which silently drops the declaration otherwise. The GUID
-- is written as raw bytes (4+2+2+8) so the declaration stays flat - LuaJIT's parser is
-- happiest with plain fields, and the layout is identical.
def [[
typedef struct {
	UINT      cbSize;
	HWND      hWnd;
	UINT      uID;
	UINT      uFlags;
	UINT      uCallbackMessage;
	HICON     hIcon;
	WCHAR     szTip[128];
	DWORD     dwState;
	DWORD     dwStateMask;
	WCHAR     szInfo[256];
	UINT      uVersion;
	WCHAR     szInfoTitle[64];
	DWORD     dwInfoFlags;
	unsigned char guidItem[16];
	HICON     hBalloonIcon;
} NOTIFYICONDATAW;
]]
def [[ BOOL Shell_NotifyIconW(DWORD dwMessage, NOTIFYICONDATAW *lpData); ]]

if Tray.available then
	-- Everything the icon needs must exist as a type before anything is created. The
	-- missing names are reported by name, because a bare "declaration specifier expected"
	-- from the C parser says nothing about which type it did not know.
	local okTypes, typesError = pcall(function()
		return ffi.sizeof("NOTIFYICONDATAW") > 0 and ffi.sizeof("MSG") > 0
			and ffi.sizeof("WNDCLASSW") > 0
	end)
	if not okTypes then
		local missing = { }
		for _, name in ipairs({ "HWND", "UINT", "DWORD", "WPARAM", "LPARAM", "HICON", "HINSTANCE",
			"HCURSOR", "HBRUSH", "WCHAR", "LPCWSTR", "MSG", "POINT", "RECT", "WNDCLASSW",
			"NOTIFYICONDATAW" }) do
			if not pcall(function() return ffi.sizeof(name) end) then
				missing[#missing + 1] = name
			end
		end
		Tray.available = false
		Tray.reason = string.format("tray types unavailable (%s); missing: %s",
			tostring(typesError), table.concat(missing, ", "))
	end
end

local WM_APP = 0x8000
local WM_TRAY = WM_APP + 1
local WM_DESTROY = 0x0002
local WM_LBUTTONUP = 0x0202
local WM_LBUTTONDBLCLK = 0x0203
local WM_RBUTTONUP = 0x0205
local PM_REMOVE = 0x0001
local NIM_ADD, NIM_MODIFY, NIM_DELETE = 0, 1, 2
local NIF_MESSAGE, NIF_ICON, NIF_TIP = 0x1, 0x2, 0x4
local TPM_RIGHTBUTTON, TPM_RETURNCMD = 0x0002, 0x0100
local MF_STRING = 0x0000
local IDI_APPLICATION = 32512

local MENU_OPEN, MENU_GRAB, MENU_CLIP, MENU_QUIT = 1, 2, 3, 4

local state = {
	hwnd = nil,
	proc = nil,      -- kept referenced: a collected callback would crash the host
	menu = nil,
	nid = nil,
	callbacks = { },
}

--- Convert UTF-8 to a NUL-terminated UTF-16 buffer.
-- Called either with a destination buffer (a struct field) or with just the text, in which
-- case a buffer big enough for any of the strings here is allocated.
local function toWide(text, out, capacity)
	capacity = capacity or 256
	local buffer = out or ffi.new("WCHAR[?]", capacity)
	local written = kernel32.MultiByteToWideChar(65001, 0, tostring(text), -1, buffer, capacity)
	if written <= 0 then
		buffer[0] = 0
	end
	return buffer
end

local function showMenu()
	local menu = user32.CreatePopupMenu()
	if menu == nil then
		return
	end
	user32.AppendMenuW(menu, MF_STRING, MENU_OPEN, toWide("Open crafting site"))
	user32.AppendMenuW(menu, MF_STRING, MENU_GRAB, toWide("Capture item (Ctrl+Q)"))
	user32.AppendMenuW(menu, MF_STRING, MENU_CLIP, toWide("Capture via clipboard (F6)"))
	user32.AppendMenuW(menu, MF_STRING, MENU_QUIT, toWide("Quit"))

	local point = ffi.new("POINT[1]")
	user32.GetCursorPos(point)
	-- The window must be foreground, or the menu will not close when clicking elsewhere.
	user32.SetForegroundWindow(state.hwnd)
	local choice = user32.TrackPopupMenu(menu,
		bit.bor(TPM_RIGHTBUTTON, TPM_RETURNCMD), point[0].x, point[0].y, 0, state.hwnd, nil)
	user32.DestroyMenu(menu)

	local callback = ({
		[MENU_OPEN] = state.callbacks.onOpen,
		[MENU_GRAB] = state.callbacks.onCapture,
		[MENU_CLIP] = state.callbacks.onClipboard,
		[MENU_QUIT] = state.callbacks.onQuit,
	})[choice]
	if callback then
		pcall(callback)
	end
end

local function windowProc(hwnd, message, wparam, lparam)
	if message == WM_TRAY then
		local event = tonumber(lparam)
		if event == WM_LBUTTONUP or event == WM_LBUTTONDBLCLK then
			if state.callbacks.onOpen then pcall(state.callbacks.onOpen) end
		elseif event == WM_RBUTTONUP then
			showMenu()
		end
		return 0
	elseif message == WM_DESTROY then
		state.hwnd = nil
		return 0
	end
	return user32.DefWindowProcW(hwnd, message, wparam, lparam)
end

--- Create the tray icon.
-- @param opts { tooltip, onOpen, onCapture, onClipboard, onQuit }
-- @return true, or false plus a reason (the caller carries on either way)
function Tray.create(opts)
	opts = opts or { }
	if Tray.available ~= true then
		return false, Tray.reason or "tray unavailable"
	end

	local class = toWide("PoE2CraftOverlayTray")
	local wc = ffi.new("WNDCLASSW[1]")
	wc[0].lpfnWndProc = ffi.cast("WNDPROC", windowProc)
	state.proc = wc[0].lpfnWndProc
	wc[0].hInstance = kernel32.GetModuleHandleW(nil)
	wc[0].lpszClassName = class
	if user32.RegisterClassW(wc) == 0 then
		local error = kernel32.GetLastError and kernel32.GetLastError() or 0
		-- 1410 = class already registered, which is fine when the icon is re-created.
		if error ~= 1410 then
			return false, "RegisterClassW failed (" .. tostring(error) .. ")"
		end
	end

	state.hwnd = user32.CreateWindowExW(0, class, toWide("PoE2 Craft Overlay"),
		0, 0, 0, 0, 0, nil, nil, wc[0].hInstance, nil)
	if state.hwnd == nil then
		return false, "CreateWindowExW failed"
	end

	local nid = ffi.new("NOTIFYICONDATAW[1]")
	nid[0].cbSize = ffi.sizeof("NOTIFYICONDATAW")
	nid[0].hWnd = state.hwnd
	nid[0].uID = 1
	-- An icon is optional: without one the entry still shows the tooltip, and a failed
	-- LoadIconW must not be the reason the whole icon disappears.
	local icon = user32.LoadIconW(nil, ffi.cast("LPCWSTR", IDI_APPLICATION))
	nid[0].hIcon = icon
	local flags = bit.bor(NIF_MESSAGE, NIF_TIP)
	if icon ~= nil then
		flags = bit.bor(flags, NIF_ICON)
	end
	nid[0].uFlags = flags
	nid[0].uCallbackMessage = WM_TRAY
	toWide(opts.tooltip or "PoE2 Craft Overlay", nid[0].szTip, 128)

	if shell32.Shell_NotifyIconW(NIM_ADD, nid) == 0 then
		return false, string.format("Shell_NotifyIconW failed (cbSize=%d, icon=%s, error=%d)",
			tonumber(nid[0].cbSize), tostring(icon ~= nil), tonumber(kernel32.GetLastError()))
	end
	state.nid = nid
	state.callbacks = {
		onOpen = opts.onOpen,
		onCapture = opts.onCapture,
		onClipboard = opts.onClipboard,
		onQuit = opts.onQuit,
	}
	return true
end

--- Pump the tray window's messages. Called once per frame.
function Tray.pump()
	if not state.hwnd then
		return
	end
	local message = ffi.new("MSG[1]")
	while user32.PeekMessageW(message, state.hwnd, 0, 0, PM_REMOVE) ~= 0 do
		user32.TranslateMessage(message)
		user32.DispatchMessageW(message)
	end
end

--- Remove the icon and destroy the window.
function Tray.destroy()
	if state.nid then
		pcall(function() shell32.Shell_NotifyIconW(NIM_DELETE, state.nid) end)
		state.nid = nil
	end
	if state.hwnd then
		pcall(function() user32.DestroyWindow(state.hwnd) end)
		state.hwnd = nil
	end
end

function Tray.status()
	return {
		available = Tray.available ~= false,
		created = state.hwnd ~= nil,
	}
end

return Tray
