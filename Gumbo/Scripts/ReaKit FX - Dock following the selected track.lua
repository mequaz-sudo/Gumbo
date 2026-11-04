-- ReaKit FX -- a docker tab that shows the selected track's ReaKit FX, whole and live, and follows your selection
-- (the user, 2026-10-03: "a meter that is docked follows the track selection would be dope", "keep the last one
-- and show the whole gainkit", then a PIN, reopening with REAPER, "the same ... dock for the other five effects",
-- and "Will a wide dock show all the plugins? Or as many can fit?"). A bar across the top: the track's name, a
-- button for each effect (GainKit, 3-Band EQ, DDC, De-Esser, Saturation, Stereo Width; the ones the track does
-- not have are dim: right-click one to add it to the track, a divider between the two groups), two window icons
-- (close this track's FX windows; close all of them), STRIP, SLOT (the same effect row on top of every mixer
-- strip at once, like a console's navigator: a click lists the slots, the wheel over it steps; the user,
-- 2026-10-07; how it works: SLOT below), a PIN icon (stay on this track, the master say,
-- whatever you click), TABS (REAPER's docker tabs off or on), a GEAR (options: the track's number, its colour as a
-- stripe or a band across the bar, its icon, full or short chip names, double-click pops out, the FOLD), a chevron
-- (folds the bar) and an X (closes the dock). The gear's menu is a ReaImGui window in the EON palette (as EON
-- Floatter's panel and the Swing FX picker; REAPER's own menu without ReaImGui). FOLD (the user, 2026-10-05: "make it thin but still able to be seen
-- so it can drop down"): the bar's chevron folds it to a thin handle, in the track's colour if wanted; a click on the
-- handle drops it open again, the plugins giving it the row; nothing folds or opens it by itself. Every icon shows a
-- tooltip after a moment, unless the gear's Tooltips is off (it turns the icon picker's off too). The track's
-- effects sit on the bar in the order they run on the track (a second copy numbered; other plugins as a grey marker, an FX container as one), the
-- ones it does not have after them: drag one along the bar to move that effect in the track's chain (one undo
-- step), drag a dim one in to add it there (the user, 2026-10-04: "can the names of each fx be chips we can drag
-- around for the order?", "Real order", "when a non reakit plugin is there will it say so?").
-- STRIP off: the chosen effect fills the dock. Click a track without it and the dock keeps the last; a track with
-- two shows the first. The wheel over the bar steps to the track's next or previous effect, in chain order.
-- STRIP on: every one of the seven on the track, side by side in chain order, like a channel strip; as many as fit
-- at a usable width, the rest a click away (< and >, an effect's button, or the wheel over the bar). Click a track
-- with none of them and the dock keeps the last. Effects inside an FX container are not shown.
-- Open a docked effect's own window (its strip, the FX chain) and the dock steps aside for it until it closes.
-- Double-click an effect's name in its own window (GainKit Plus running): the dock opens on its track with it;
-- double-click the name of a docked one: it pops out into its own window.
-- Run the action again to close the dock; on a toolbar the button lights while it runs. GainKit Plus, when it
-- starts with REAPER, opens the dock again if it was open when REAPER closed.
--
-- How: REAPER floats the effect, this script takes the float's drawing surface (the "jsfx_gfx" child window,
-- the plugin itself without REAPER's preset bar) into its own dockable window and hides the empty float; in a
-- strip, one float and one surface per effect. Every way out hands a surface back to a float, at its exact place,
-- BEFORE anything else: a REAPER window moved outside its tree is never taken back by REAPER (EON Swing Dock's
-- lesson, 2026-08-25). The same mechanism as EON Swing Dock, written for the seven. Windows only; needs
-- js_ReaScriptAPI (ReaPack). EON Free Licence 1.0, EON Studios, 2026.
local r = reaper
local DIR = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""   -- this script's folder (the picker lives beside it)
-- A dock of ONE plugin (2026-10-31, the user: "I definitely want each plugin to have its own separate dock tab"): a
-- wrapper action ("ReaKit FX - Dock <name>.lua") sets REAKIT_DOCK_ONLY = { key = <its KINDS key>, title = <its name> }
-- and runs this file. Its own docker tab (labelled with the plugin's name), its own saved settings (its own EXT), that
-- plugin alone: no STRIP, no SLOT, no chips for the others. Any number of them can be open beside the full dock; a
-- plugin another open dock holds is left to it (held_elsewhere).
local ONLY = type(REAKIT_DOCK_ONLY) == "table" and REAKIT_DOCK_ONLY or nil
local TITLE = ONLY and ONLY.title or "ReaKit FX Dock"   -- the docker tab's label; also how the script finds its own window
local EXT = ONLY and ("EON_ReaKitDock_" .. ONLY.key) or "EON_ReaKitDock"
local C = {                            -- the dock's fixed numbers (one table, not eleven locals: the 200-local limit)
  W0 = 350, H0 = 572,                  -- the size when not docked: GainKit's window and the bar
  WAIT_TICKS = 30,                     -- how long to wait for REAPER to make a float and its surface
  GAP = 3,                             -- STRIP: the line between two effects, at 100 %
  BAR = 26,                            -- the bar's height at 100 %; times the display scale (sc)
  FOLD_H = 8,                          -- the folded bar's handle, px at 100 %
  STRIPE_H = 3,                        -- the track-colour stripe along the top, px at 100 %
  TIP_DELAY = 0.5,                     -- the tooltip's delay, s
  COMPACT_NAME = "dockers: compact when small and single tab",   -- REAPER's action (TABS)
  DRW = 31365520, DRW_MAX = 64,        -- the drawer band in Swing_Media_Transfer (publish_drw)
}

if not r.GetOS():match("^Win") then
  r.MB("The ReaKit FX dock works on Windows only.", "ReaKit FX", 0)
  return
end
if not r.APIExists("JS_Window_SetParent") then
  r.MB("The ReaKit FX dock needs the js_ReaScriptAPI extension.\n\n" ..
       "Extensions > ReaPack > Browse packages > js_ReaScriptAPI, install it, restart REAPER.", "ReaKit FX", 0)
  return
end

-- The seven, each by its FILE, the exact name, as every GainKit Plus action finds GainKit (wiki 6.16). w = its own
-- window's width (the plugin's @gfx line; Saturation and Stereo Width: the width their header fits on one line,
-- seen 2026-10-03: narrower, THEME drops onto the knob row); minw = the least STRIP gives it before it moves one
-- off the dock (3-Band EQ 250: at 226 its three crossover labels ran into each other, seen in the release
-- pictures); src = the file as it is spelled on disk (a right-click adds one).
local KINDS = {
  -- w / minw: the natural and the smallest width when the effects stand side by side (ACROSS); h / minh: the same
  -- for the dock laid out DOWN (a side docker: the effects stacked, each the dock's full width; the user, 2026-10-07).
  -- h = the window the Add-a-track action opens; minh = the shortest window that still reads whole (the size prints
  -- of 2026-10-07, after the first six's compact layouts: one row / folded rows from about 140), so those six stack on
  -- a 1080 screen (about 155 each); with the Filter the seven need about 1020, so on 1080 the last one moves off.
  -- In the chain's order (the user, 2026-10-07: "gain, filter, de-esser, saturation, eq, compressor, then width"):
  -- the dim chips follow it. The Filter (the seventh, ReaKit FX 1.5.0) has no short layout: its knobs read whole
  -- from about 145 of surface (filter_sizes prints, 2026-10-07), cut at about 105.
  { key = "gk",  name = "GainKit",      long = "GAINKIT",  short = "GK",  file = "channeltool_reakit.jsfx", w = 450, minw = 230, h = 546, minh = 150, src = "ChannelTool_ReaKit.jsfx" },
  { key = "flt", name = "Filter",       long = "FILTER",   short = "FLT", file = "filter_reakit.jsfx",      w = 260, minw = 240, h = 404, minh = 145, src = "Filter_ReaKit.jsfx" },
  { key = "des", name = "De-Esser",     long = "DE-ESSER", short = "DE",  file = "deesser_reakit.jsfx",     w = 540, minw = 240, h = 376, minh = 150, src = "DeEsser_ReaKit.jsfx" },
  { key = "sat", name = "Saturation",   long = "SAT",      short = "SAT", file = "saturation_reakit.jsfx",  w = 280, minw = 260, h = 506, minh = 140, src = "Saturation_ReaKit.jsfx" },
  { key = "eq3", name = "3-Band EQ",    long = "3-BAND",   short = "EQ",  file = "3bandeq_reakit.jsfx",     w = 460, minw = 250, h = 228, minh = 140, src = "3BandEQ_ReaKit.jsfx" },
  -- Quezy (the eighth, the free EQ, 2026-10-30): its window's design size and its smallest (the face folds its
  -- editor below 534 and fits down to 489 x 260, Quezy's own size rig); with the EQs in the chain's order
  { key = "qzy", name = "Quezy",        long = "QUEZY",    short = "QZ",  file = "quezy_reakit.jsfx",       w = 648, minw = 489, h = 534, minh = 260, src = "Quezy_ReaKit.jsfx" },
  { key = "ddc", name = "DDC",          long = "DDC",      short = "DDC", file = "ddc_reakit.jsfx",         w = 600, minw = 260, h = 319, minh = 140, src = "DDC_ReaKit.jsfx" },
  { key = "wid", name = "Stereo Width", long = "WIDTH",    short = "W",   file = "stereowidth_reakit.jsfx", w = 300, minw = 280, h = 364, minh = 140, src = "StereoWidth_ReaKit.jsfx" },
}
-- Gumbo (the SFZ player, 2026-11-01; the owner: "i want gumbo to dock all its own"): only in its own tab ("Gumbo -
-- Dock", Gumbo's package carries a copy of this file), never a chip in the effects' bar
if ONLY and ONLY.key == "gmb" then
  KINDS[#KINDS + 1] = { key = "gmb", name = "Gumbo", long = "GUMBO", short = "GB", file = "gumbo_reakit.jsfx", w = 1000, minw = 700, h = 640, minh = 420, src = "Gumbo_ReaKit.jsfx" }
end
local kind = 1
for i, k in ipairs(KINDS) do if k.key == r.GetExtState(EXT, "kind") then kind = i end end
local strip = r.GetExtState(EXT, "strip") == "1"
if ONLY then
  for i, k in ipairs(KINDS) do if k.key == ONLY.key then kind = i end end
  strip = false
end

local function basename(p) return (p:gsub("^.*[/\\]", "")) end
local function kind_of(tr, f)
  local ok, id = r.TrackFX_GetNamedConfigParm(tr, f, "fx_ident")
  if not ok then return nil end
  local b = basename(id):lower()
  for k, v in ipairs(KINDS) do if v.file == b then return k end end
end
local function first_of(tr, k)
  if not tr then return nil end
  for f = 0, r.TrackFX_GetCount(tr) - 1 do
    if kind_of(tr, f) == (k or kind) then return f end
  end
end
-- Every effect in a track's own chain, in order: { { fg, fx, kind } } for the seven, { fg, fx, name } for any other
-- (its name without the "VST3: " kind and the "(maker)" tail; an FX container is one). The bar's chips and markers.
local function chain_items(tr)
  local out = {}
  if not tr then return out end
  for f = 0, r.TrackFX_GetCount(tr) - 1 do
    local e = { fg = r.TrackFX_GetFXGUID(tr, f), fx = f, kind = kind_of(tr, f) }
    if not e.kind then
      local _, nm = r.TrackFX_GetFXName(tr, f)
      nm = (nm or ""):gsub("^%w+:%s*", ""):gsub("%s*%b()%s*$", "")
      e.name = nm ~= "" and nm or "FX"
    end
    out[#out + 1] = e
  end
  return out
end
-- What the dock shows of a track, in chain order: { { fg, fx, kind }, ... }. STRIP off: the first of the chosen
-- effect, or the copy last asked for on that track by a double-click on its name (prefer, by track GUID). STRIP
-- on: every one of the seven. The track's own chain only: an effect inside a container is not shown.
local prefer = {}
-- A plugin another open dock holds (the full dock or a one-plugin tab: its "held" list, while its "alive" stamp is
-- fresh) is never taken here too: two docks pulling one surface would leave it in neither. wanted_skipped tells the
-- empty dock's note why.
local wanted_skipped = false
local function held_elsewhere(fg)
  local now = r.time_precise()
  local function in_ext(x)
    if x == EXT or now - (tonumber(r.GetExtState(x, "alive")) or 0) > 1.0 then return false end
    return (("," .. r.GetExtState(x, "held") .. ","):find("|" .. fg .. ",", 1, true)) ~= nil
  end
  if in_ext("EON_ReaKitDock") then return true end
  for _, k in ipairs(KINDS) do if in_ext("EON_ReaKitDock_" .. k.key) then return true end end
  return false
end
local function wanted(tr)
  local out = {}
  wanted_skipped = false
  if not tr then return out end
  local pick
  local want_fg = not strip and prefer[r.GetTrackGUID(tr)]
  for f = 0, r.TrackFX_GetCount(tr) - 1 do
    local k = kind_of(tr, f)
    if k and (strip or k == kind) and held_elsewhere(r.TrackFX_GetFXGUID(tr, f)) then wanted_skipped = true; k = nil end
    if k and (strip or k == kind) then
      local e = { fg = r.TrackFX_GetFXGUID(tr, f), fx = f, kind = k }
      if strip then out[#out + 1] = e
      elseif e.fg == want_fg then pick = e; break
      elseif not pick then pick = e; if not want_fg then break end end
    end
  end
  if pick then out[1] = pick end
  return out
end

-- a track and an FX are kept by GUID (a MediaTrack pointer or an FX index can move, wiki 6.2 / 6.9), in the
-- project they came from; the last pointer is tried first and the project searched only when it fails
local function track_by_guid(proj, g, hint)
  if not g or not r.ValidatePtr(proj, "ReaProject*") then return nil end   -- its project tab may be closed
  if hint and r.ValidatePtr2(proj, hint, "MediaTrack*") and r.GetTrackGUID(hint) == g then return hint end
  local m = r.GetMasterTrack(proj)
  if r.GetTrackGUID(m) == g then return m end
  for i = 0, r.CountTracks(proj) - 1 do
    local tr = r.GetTrack(proj, i)
    if r.GetTrackGUID(tr) == g then return tr end
  end
end
local function fx_by_guid(tr, g, hint)
  if not (tr and g) then return nil end
  if hint and r.TrackFX_GetFXGUID(tr, hint) == g then return hint end
  for f = 0, r.TrackFX_GetCount(tr) - 1 do
    if r.TrackFX_GetFXGUID(tr, f) == g then return f end
  end
end

-- the float's drawing surface: its child of class "jsfx_gfx"
local function find_canvas(float_hwnd)
  local ok, list = r.JS_Window_ListAllChild(float_hwnd)
  if not ok or not list or list == "" then return nil end
  for addr in list:gmatch("[^,]+") do
    local h = r.JS_Window_HandleFromAddress(tonumber(addr))
    if h and r.JS_Window_GetClassName(h) == "jsfx_gfx" then return h end
  end
end

-- A trace for tests: SetExtState("EON_ReaKitDock", "debug", "1") and the dock appends its steps to
-- %TEMP%\reakit_dock_trace.txt. Off (the default): nothing is written.
local function dbg(msg)
  if r.GetExtState(EXT, "debug") ~= "1" then return end
  local fh = io.open((os.getenv("TEMP") or ".") .. "\\reakit_dock_trace.txt", "a")
  if fh then fh:write(string.format("%.3f %s\n", r.time_precise(), msg)); fh:close() end
end

-- ── state ────────────────────────────────────────────────────────────────────────────────────────
local dock                             -- this script's own window
local cur = nil                        -- the track the dock shows: { proj, tg, tr, name, list = wanted(it) }
-- The effects on view, left to right, one record each: { proj, tg, fg, tr, fx, kind, name, x, y, w, h } and
-- then either its surface (wrapper, canvas, home, wait), or away = true (open in the user's own window), or
-- retry = a time (its float never came: try again then), or gone = true (deleted: dropped at the next sweep).
local slots = {}
local first = 1                        -- STRIP: the list's first effect on view
local more_left, more_right = false, false
local on_view = {}                     -- STRIP: the effects on view, by FX GUID (their chips light)
local last_sel_g = false               -- the followed track's GUID last tick (false = never looked)
local scan_cool = 0
local chain_t = 0                      -- when the shown track's chain was last looked at (0 = look now)
local recheck_t = 0                    -- when the followed track was last looked at while the dock shows another
-- What the dock let go of in each project tab the user went away from, by project: { cur, first, held }. One per
-- tab (2026-10-03, dockfix_probe.lua: a single slot was overwritten by the second tab, and coming back to the
-- first, the windows REAPER shows again there stayed open as windows).
local tabs_left = {}
local note = nil                       -- why the dock is empty, when it is: "No De-Esser on Vocal."
local pin = r.GetExtState(EXT, "pin")  -- "" = follow the selection; "MASTER" or a track's GUID = stay on it
local sc = 1
-- The bar's icons (draw_bar's chip() draws them by hand, icon_draw): names that are not words
local ICON = {}                        -- the bar's icons (one table: the 200-local limit); the names start with byte 1 (not words)
for _, k in ipairs({ "ctrack", "call", "pin", "gear", "fold", "x" }) do ICON[k] = string.char(1) .. k end
ICON.set = { [ICON.ctrack] = true, [ICON.call] = true, [ICON.pin] = true, [ICON.gear] = true, [ICON.fold] = true, [ICON.x] = true }
-- The gear's options, saved like STRIP and PIN (ExtState opt_<key>); tests set one with opt_req = "key=value"
local opt = {}
local OPT_DEF = { trackno = "1", color = "stripe", icon = "1", labels = "long", dblclick = "1", fold = "1", fold_color = "1",
                  menu_stay = "1", tint = "0", tintk = "50",   -- tintk: the icon colour's strength, % (TINT.pct)
                  layout = "auto",                             -- layout: auto (taller than wide = down) | across | down
                  tips = "1" }                                 -- tips: the bar's and the picker's tooltips (the user,
                                                               -- 2026-10-07: "the tooltips get in the way")
local function opt_set(k, v) opt[k] = v; r.SetExtState(EXT, "opt_" .. k, v, true) end
for k, d in pairs(OPT_DEF) do local v = r.GetExtState(EXT, "opt_" .. k); opt[k] = v ~= "" and v or d end
local fold_open = r.GetExtState(EXT, "fold_open") ~= "0"   -- FOLD on: the bar is open, or folded to its handle; a
                                       -- click on the handle opens it, the bar's chevron folds it; nothing folds or
                                       -- opens it on its own (the user, 2026-10-05: "i just wanted it to drop down not
                                       -- auto close"). Remembered per dock (its EXT) from one start to the next (the
                                       -- owner, 2026-11-01: "can it remember the top bar open and close?")
local hover_act, hover_t = nil, 0      -- the tooltip: what is under the pointer, since when (C.TIP_DELAY)
local want_close = false               -- the X: the dock closes at the end of this tick
local pub = { tip = nil, drw = nil, beat = -1 }   -- what was last published for tests (ExtState tip / held / view / bar / hover / menu / picker / name_edit / name_hit / ticon_hit, the C.DRW gmem beat): one table, not twelve locals (the 200-local limit)

local function where(rec)
  local tr = track_by_guid(rec.proj, rec.tg, rec.tr)
  local fx = tr and fx_by_guid(tr, rec.fg, rec.fx)
  rec.tr, rec.fx = tr, fx
  return tr, fx
end
local function track_name(tr)
  if tr == r.GetMasterTrack(0) then return "MASTER" end
  local _, nm = r.GetTrackName(tr)
  return nm
end
local function label(rec) return rec.name .. ":" .. KINDS[rec.kind].short end
local bar_rows = 1                     -- 2+ when the dock is too narrow for one row (draw_bar decides)
local bar_chip_rows = 1                -- of those, the rows the chips take (the name and the buttons get the last)
bar_rows_ar = { [false] = 1, [true] = 1 }   -- the rows without and with STRIP's < > (layout(); a GLOBAL: the 200-local limit)
local function stripe_h() return opt.color == "stripe" and math.floor(C.STRIPE_H * sc + 0.5) or 0 end
local function folded() return opt.fold == "1" and not fold_open end
local function bar_h(arrows)           -- as drawn; arrows true / false: as it would be with or without the < >
  if folded() then return math.floor(C.FOLD_H * sc + 0.5) end
  return math.floor(C.BAR * sc + 0.5) * (arrows == nil and bar_rows or bar_rows_ar[arrows]) + stripe_h()
end
-- The shown track's colour (GetTrackColor; 0 = none), looked up about twice a second with the chain.
local tcol = { tr = nil, t = 0, has = false, r = 0, g = 0, b = 0 }
local function track_color(tr)
  local now = r.time_precise()
  if tr ~= tcol.tr or now - tcol.t > 0.5 then
    tcol.tr, tcol.t = tr, now
    local c = tr and r.GetTrackColor(tr) or 0
    tcol.has = c ~= 0
    if tcol.has then
      local cr, cg, cb = r.ColorFromNative(c)
      tcol.r, tcol.g, tcol.b = cr / 255, cg / 255, cb / 255
    end
  end
  return tcol.has, tcol.r, tcol.g, tcol.b
end
-- The shown track's icon (P_ICON: what was set, a bare name or a path; measured 2026-10-05), loaded into gfx image
-- slot 1 when it changes; a bare or relative name lives in REAPER's Data/track_icons.
local ticon = { path = nil, ok = false, w = 0, h = 0, tr = nil, t = 0, pth = "" }
local function track_icon(tr)
  if opt.icon ~= "1" or not tr then return false end
  local now = r.time_precise()
  if tr ~= ticon.tr or now - ticon.t > 0.5 then                   -- the field read twice a second, not every frame
    ticon.tr, ticon.t = tr, now
    local _, pth = r.GetSetMediaTrackInfo_String(tr, "P_ICON", "", false)
    ticon.pth = pth
  end
  local pth = ticon.pth
  if pth == "" then ticon.path = ""; ticon.ok = false; return false end
  if pth ~= ticon.path then
    ticon.path = pth
    local full = pth
    if not (pth:match("^%a:[/\\]") or pth:match("^[/\\]")) then full = r.GetResourcePath() .. "/Data/track_icons/" .. pth end
    ticon.ok = gfx.loadimg(1, full) >= 0
    if ticon.ok then ticon.w, ticon.h = gfx.getimgdim(1) end
  end
  return ticon.ok
end

-- Put a surface back in its float, where it came from: INSIDE the float's plugin container (the "#32770" child
-- that REAPER lays out, measured 2026-10-05: style_probe.lua), not under the float's top window. Handed to the top
-- window, the surface sat beside that container, and every resize step of the float wiped its whole face bare
-- until the plugin drew again: the user's "3 band still blinks" after a plugin left the dock (filmed on the user's
-- screen, then drag_run.py --dockbg: DDC 10 of 47 frames whole-face bare; a never-docked copy 0). The container it
-- came from when it still exists in this float; else this float's own container (REAPER rebuilt the float); else
-- the float itself. True when it landed.
local function container_of(wrapper)
  local ok, list = r.JS_Window_ListAllChild(wrapper)
  if not ok or not list or list == "" then return nil end
  for addr in list:gmatch("[^,]+") do
    local h = r.JS_Window_HandleFromAddress(tonumber(addr))
    if h and r.JS_Window_GetParent(h) == wrapper and r.JS_Window_GetClassName(h) == "#32770" then return h end
  end
end
local function give_back(rec, wrapper)
  if not (rec.canvas and wrapper and r.JS_Window_IsWindow(rec.canvas) and r.JS_Window_IsWindow(wrapper)) then return false end
  local hp = rec.home and rec.home.parent
  local target = (hp and r.JS_Window_IsWindow(hp) and r.JS_Window_IsChild(wrapper, hp)) and hp or container_of(wrapper) or wrapper
  r.JS_Window_SetParent(rec.canvas, target)
  if rec.home then
    r.JS_Window_Move(rec.canvas, rec.home.x, rec.home.y)
    r.JS_Window_Resize(rec.canvas, rec.home.w, rec.home.h)
  end
  return true
end

-- An effect moved to ANOTHER track keeps its instance, its GUID and its surface; REAPER opens its window on the new
-- track, empty (measured 2026-10-03, dockedge_probe.lua: the surface stayed in the dock). Found anywhere in its
-- project by its GUID, so the surface goes back to it there.
local function fx_anywhere(proj, fg)
  if not r.ValidatePtr(proj, "ReaProject*") then return nil end
  local m = r.GetMasterTrack(proj)
  local f = fx_by_guid(m, fg)
  if f then return m, f end
  for i = 0, r.CountTracks(proj) - 1 do
    local tr = r.GetTrack(proj, i)
    f = fx_by_guid(tr, fg)
    if f then return tr, f end
  end
end

-- Let go of one effect: its surface back in a float first, then the float hidden and closed. One that is open in
-- the user's own window stays there. keep (a track switch only): the hidden float is KEPT a few seconds instead of
-- closed (KEEP, below), so going back to that track takes it again at once.
local function release(rec, keep)
  if rec.away then return end
  local tr, fx = where(rec)
  if not (tr and fx) and rec.canvas and r.JS_Window_IsWindow(rec.canvas) then
    tr, fx = fx_anywhere(rec.proj, rec.fg)
    if tr then dbg("release " .. label(rec) .. ": moved to another track, handed back there") end
  end
  dbg("release " .. label(rec) .. " canvas " .. tostring(rec.canvas) .. " lives " .. tostring(rec.canvas and r.JS_Window_IsWindow(rec.canvas)))
  if rec.canvas and r.JS_Window_IsWindow(rec.canvas) then
    local w = rec.wrapper
    if tr and fx then
      local fw = r.TrackFX_GetFloatingWindow(tr, fx)
      if fw then w = fw end            -- REAPER may have rebuilt the float
      if not (w and r.JS_Window_IsWindow(w)) then
        -- REAPER closed the float itself (another project tab: REAPER puts a background project's windows
        -- away; measured 2026-10-03) while the surface lives here. A new float to give it back to, so it is
        -- never left behind: left here, that effect's next window opens empty.
        r.TrackFX_Show(tr, fx, 3)
        w = r.TrackFX_GetFloatingWindow(tr, fx)
        dbg("release: float gone, a new one " .. tostring(w))
      end
    end
    give_back(rec, w)
    if w and r.JS_Window_IsWindow(w) then r.JS_Window_Show(w, "HIDE") end
    if keep and tr and fx and w and r.JS_Window_IsWindow(w) then
      KEEP.list[rec.fg] = { proj = rec.proj, tg = rec.tg, fg = rec.fg, tr = tr, fx = fx, w = w, t = r.time_precise() }
      rec.canvas, rec.wrapper = nil, nil
      return
    end
  end
  if tr and fx then r.TrackFX_Show(tr, fx, 2) end
  rec.canvas, rec.wrapper = nil, nil
end
local function release_all()
  for _, s in ipairs(slots) do release(s) end
  for _, s in ipairs(KEEP.leaving) do release(s) end         -- a switch's old surfaces, still on view
  KEEP.leaving, KEEP.reveal_t = {}, nil
  slots = {}
end
-- KEEP: the floats of the effects a track switch let go, kept open and HIDDEN for KEEP.S seconds (the user,
-- 2026-10-07: "can we make it faster and not flicker when i switch tracks"). REAPER takes 50-140 ms to open a JSFX's
-- float and stalls while it does (float_cost_probe.lua: about 300 ms for four effects), against a few ms to take a
-- kept one back. Not for long, and never past the dock's end: REAPER saves an open float as open even when it is
-- hidden, and opens it on screen with the project (float_reload_probe.lua). A kept float REAPER closed (a click on
-- the strip, its track deleted) or the user opened is dropped from the list, theirs from then on. A global table
-- (the 200-local limit).
-- Only while the mixer is closed (the user, 2026-10-09: "it takes a while for the script to give the track back its
-- view"): REAPER draws "PLUG-IN UI OPEN" in an effect's embedded face on its mixer strip while its float is open, kept
-- floats too, so with the mixer on screen (KEEP.seen) a switch closes the old track's floats at once and the strip
-- shows its faces again (switching back opens them afresh, a little slower: the user's choice), and a mixer opened
-- during a hold ends it within KEEP.LOOK. With the mixer closed nobody sees the strips and the hold stays. Faces
-- embedded in the track panel are not looked at (the handoff Dock_Handback_Filter_Long_View_2026-10-09.md says why).
KEEP = { list = {}, S = 8, MAX = 16,
         leaving = {}, staging = false, reveal_t = nil, REVEAL = 0.08,   -- the switch's staging (layout, fit)
         look_t = 0, LOOK = 0.25 }                                        -- a hold looks at the mixer this often
-- The mixer on screen: its toggle on AND a strip window shown (SLOT.displays finds them by class under the main window
-- and the windows it owns, never by title; a mixer in a docker behind another tab is not shown). Unsure = not shown:
-- the hold, as before.
function KEEP.seen()
  if r.GetToggleCommandState(40078) ~= 1 then return false end
  local ok, d = pcall(SLOT.displays)
  return ok and d ~= nil
end
function KEEP.close(k)
  local tr = track_by_guid(k.proj, k.tg, k.tr)
  local fx = tr and fx_by_guid(tr, k.fg, k.fx)
  if tr and fx and r.TrackFX_GetFloatingWindow(tr, fx) == k.w then r.TrackFX_Show(tr, fx, 2) end
end
-- every tick (all = true: close every kept float now, at the dock's end or a project change; also once the mixer is
-- on screen, looked at every KEEP.LOOK while anything is kept)
function KEEP.tick(all)
  local now, order = r.time_precise(), {}
  if not all and next(KEEP.list) and now >= KEEP.look_t then
    KEEP.look_t = now + KEEP.LOOK
    if KEEP.seen() then all = true; dbg("kept floats closed: the mixer is on screen") end
  end
  for fg, k in pairs(KEEP.list) do
    if not (k.w and r.JS_Window_IsWindow(k.w)) or r.JS_Window_IsVisible(k.w) then
      KEEP.list[fg] = nil                                    -- REAPER closed it, or it is on screen: not ours now
    elseif all or now - k.t > KEEP.S then
      KEEP.close(k); KEEP.list[fg] = nil
    else
      order[#order + 1] = k
    end
  end
  if #order > KEEP.MAX then                                   -- too many: the oldest go first
    table.sort(order, function(a, b) return a.t < b.t end)
    for i = 1, #order - KEEP.MAX do KEEP.close(order[i]); KEEP.list[order[i].fg] = nil end
  end
end
-- drop the deleted ones; the shown track's chain is looked at again on the next tick
local function sweep()
  local kept = {}
  for _, s in ipairs(slots) do if not s.gone then kept[#kept + 1] = s end end
  if #kept ~= #slots then chain_t = 0 end
  slots = kept
end

-- A surface fills its place in the dock (the layout below sets x, y, w, h). One move and size together, and no
-- erase: the erase painted the plugin's place bare until it drew again, a blink on every step of a resize (filmed
-- 2026-10-05).
local function fit(rec)
  if not (rec.canvas and rec.w and rec.w >= 2 and rec.h >= 2) then return end
  -- hold_out: a surface just taken from a NEW float has not drawn yet (blank: the dock's own colour shows through it);
  -- it waits just outside the dock's client area, where it is clipped from view but still draws, until KEEP.reveal
  local x = rec.hold_out and -(rec.w + 200) or rec.x
  local key = x .. " " .. rec.y .. " " .. rec.w .. " " .. rec.h
  if key == rec.shown then return end
  r.JS_Window_SetPosition(rec.canvas, x, rec.y, rec.w, rec.h)
  r.JS_Window_InvalidateRect(rec.canvas, 0, 0, rec.w, rec.h, false)
  rec.shown = key
end

-- Its float never came, or came without a surface: let go, and try again in a while (1, 2, 4, 8 s).
local function retry_later(rec, why)
  dbg("capture " .. label(rec) .. ": " .. why .. ", gave up")
  release(rec)
  rec.tries = (rec.tries or 0) + 1
  rec.retry = r.time_precise() + math.min(8, 2 ^ (rec.tries - 1))
end

-- Take the float's surface once it exists. The float is hidden the moment it is found, so it is not seen.
local function capture(rec)
  local tr, fx = where(rec)
  if not (tr and fx) then dbg("capture: target gone"); release(rec); rec.gone = true; return end
  if not rec.wrapper then
    rec.wrapper = r.TrackFX_GetFloatingWindow(tr, fx)
    if not rec.wrapper then
      rec.wait = rec.wait - 1
      if rec.wait <= 0 then retry_later(rec, "no float") end
      return
    end
    dbg("capture: float " .. tostring(rec.wrapper))
    r.JS_Window_Show(rec.wrapper, "HIDE")
  end
  if not rec.canvas then
    local c = find_canvas(rec.wrapper)
    if not c then
      rec.wait = rec.wait - 1
      if rec.wait <= 0 then retry_later(rec, "no surface") end
      return
    end
    dbg("capture: surface " .. tostring(c))
    local ok, L, T, R, B = r.JS_Window_GetRect(c)   -- its home, saved before it moves: its parent (the float's
    if ok then                                        -- plugin container) and its place in that parent
      local hp = r.JS_Window_GetParent(c) or rec.wrapper
      local x, y = r.JS_Window_ScreenToClient(hp, L, T)
      rec.home = { parent = hp, x = x, y = y, w = R - L, h = B - T }
    end
    rec.canvas, rec.tries, rec.shown = c, 0, nil
    r.JS_Window_SetParent(c, dock)
    r.JS_Window_SetZOrder(c, "TOP")   -- over the surfaces of a track being switched away from, which go just after
  end
  fit(rec)
end

-- force: take it even when its own window is open (back on a project tab, below)
local function take(rec, force)
  local tr, fx = where(rec)
  if not (tr and fx) then rec.gone = true; return end
  rec.retry = nil
  -- already open in its own window or the FX chain: the user is looking at it there, so it stays there
  local fw = r.TrackFX_GetFloatingWindow(tr, fx)
  if not force and ((fw and r.JS_Window_IsVisible(fw)) or r.TrackFX_GetChainVisible(tr) == fx) then
    rec.away = true
    dbg("acquire " .. label(rec) .. ": open elsewhere, left there")
    return
  end
  rec.away = nil
  rec.wrapper, rec.canvas, rec.home, rec.shown = nil, nil, nil, nil
  rec.wait = C.WAIT_TICKS
  local k = KEEP.list[rec.fg]                                -- kept from a switch a moment ago: no new float, and
  KEEP.list[rec.fg] = nil                                    -- its surface has drawn already
  if k and fw == k.w and r.JS_Window_IsWindow(k.w) then
    dbg("acquire " .. label(rec) .. " fx " .. fx .. " (kept)")
    rec.wrapper = k.w
    capture(rec)
    return
  end
  dbg("acquire " .. label(rec) .. " fx " .. fx)
  rec.hold_out = KEEP.staging                                -- a new float's surface waits out of view (fit)
  r.TrackFX_Show(tr, fx, 3)
  capture(rec)                         -- the float usually exists at once: hidden before it is drawn
end

-- The user opened a held effect somewhere else (its float shown, or the FX chain on it), or REAPER closed its
-- float (a click on the strip toggles the window, the strip's house rule). Opened elsewhere: the surface goes
-- back where the user is looking and its place in the dock says so. Closed by REAPER: it opens again as its own
-- window, with its surface (below). Either way, once that window closes the dock takes it back.
local function watch_held(rec)
  local tr, fx = where(rec)
  if not (tr and fx) then release(rec); rec.gone = true; return end
  if not rec.canvas then capture(rec); return end
  local fw = r.TrackFX_GetFloatingWindow(tr, fx)
  local chain = r.TrackFX_GetChainVisible(tr) == fx
  if fw and fw ~= rec.wrapper and not (rec.wrapper and r.JS_Window_IsWindow(rec.wrapper)) then rec.wrapper = fw end
  local float_shown = fw and r.JS_Window_IsVisible(fw)
  if float_shown or chain then
    if not fw then r.TrackFX_Show(tr, fx, 3); fw = r.TrackFX_GetFloatingWindow(tr, fx) end
    give_back(rec, fw)
    if chain and not float_shown then r.TrackFX_Show(tr, fx, 2) end   -- the chain re-hosts it
    rec.away, rec.canvas, rec.wrapper = true, nil, nil
    dbg("away: " .. label(rec) .. (chain and " (chain)" or " (its window)"))
    return
  end
  if not fw or not r.JS_Window_IsWindow(rec.canvas) then
    local surface_lives = r.JS_Window_IsWindow(rec.canvas)
    dbg("held float gone: " .. label(rec) .. " fw " .. tostring(fw) .. " surface lives " .. tostring(surface_lives)
      .. " wrapper lives " .. tostring(rec.wrapper and r.JS_Window_IsWindow(rec.wrapper)))
    if not fw and surface_lives then
      -- REAPER closed the hidden float (a click on the strip toggles the window, and REAPER counts a
      -- docked effect's float as open). REAPER keeps the plugin's one surface alive and makes no new one for
      -- a new float (measured 2026-10-03: a re-float came up without it), so the surface must go to a new
      -- float, not be left here. The click meant "open the window": it opens, with the surface, and the dock
      -- steps aside; the next click on the strip closes it and the dock takes it back.
      r.TrackFX_Show(tr, fx, 3)
      local nw = r.TrackFX_GetFloatingWindow(tr, fx)
      if nw and give_back(rec, nw) then
        rec.away, rec.canvas, rec.wrapper = true, nil, nil
        dbg("away: " .. label(rec) .. " (the float was closed: opened again, with its surface)")
        return
      end
    end
    -- the surface is gone too (the dock window went first, or REAPER made a new view): take it afresh
    rec.canvas, rec.wrapper = nil, nil
    take(rec)
  end
end

-- Back from its own window: once that window has closed (and the chain is not on it), the dock takes it again.
local function watch_away(rec)
  local tr, fx = where(rec)
  if not (tr and fx) then rec.gone = true; return end
  local fw = r.TrackFX_GetFloatingWindow(tr, fx)
  if not (fw and r.JS_Window_IsVisible(fw)) and r.TrackFX_GetChainVisible(tr) ~= fx then take(rec) end
end

local function watch(rec)
  if rec.retry then
    if r.time_precise() >= rec.retry then take(rec) end
  elseif rec.away then watch_away(rec)
  else watch_held(rec) end
end

-- The track the dock follows: the pinned one, or the selected one (the master counts).
local function pinned_track()
  if pin == "MASTER" then return r.GetMasterTrack(0) end
  return track_by_guid(r.EnumProjects(-1), pin, nil)
end
local function followed()
  if pin ~= "" then
    local tr = pinned_track()
    if tr then return tr end
    pin = ""                                             -- its track is gone, or another project: follow again
    r.SetExtState(EXT, "pin", "", true)
  end
  return r.GetSelectedTrack2(0, 0, true)
end

local function show_track(tr, list)
  local proj, g = r.EnumProjects(-1), r.GetTrackGUID(tr)
  if not (cur and cur.tg == g and cur.proj == proj) then first = 1 end
  cur = { proj = proj, tg = g, tr = tr, name = track_name(tr), list = list }
  note = nil
end
local function none_note(tr)
  release_all(); cur = nil
  note = wanted_skipped and string.format("%s is shown in another dock tab.", strip and "ReaKit FX" or KINDS[kind].name)
         or string.format("No %s on %s.", strip and "ReaKit FX" or KINDS[kind].name, tr and track_name(tr) or "the selected track")
end

-- force: the effect or the pin changed, so look again even when the followed track did not change
local function follow(force)
  local tr = followed()
  local g = tr and r.GetTrackGUID(tr) or ""
  local now = r.time_precise()
  if g ~= last_sel_g or force then
    last_sel_g, recheck_t = g, now
    local list = wanted(tr)
    if #list > 0 then
      show_track(tr, list)
    elseif force or pin ~= "" or note then
      -- the effect switched (or the dock is pinned, or already says why it is empty) and this track has none
      -- of it: nothing to keep, say so
      none_note(tr)
    end
    -- following, and the selected track has none of it: keep the last one
  elseif tr and (note or (cur and cur.tg ~= g)) and now - recheck_t >= 0.5 then
    -- the dock says why it is empty, or keeps the last track because this one had none: one added here since
    -- shows without a click elsewhere (2026-10-03, dockfix_probe.lua: it waited for a reselect)
    recheck_t = now
    local list = wanted(tr)
    if #list > 0 then show_track(tr, list) end
  end
  if not cur and not note and pin == "" then
    if scan_cool > 0 then scan_cool = scan_cool - 1; return end
    scan_cool = 30                                       -- showing nothing: look about once a second
    dbg("holding nothing: scan")
    local cands = {}
    if tr then cands[1] = tr end
    cands[#cands + 1] = r.GetMasterTrack(0)
    for i = 0, r.CountTracks(0) - 1 do cands[#cands + 1] = r.GetTrack(0, i) end
    for _, t in ipairs(cands) do
      local list = wanted(t)
      if #list > 0 then show_track(t, list); return end
    end
  end
end

-- The shown track's chain, about twice a second: an effect added, moved or deleted there shows at once.
local function check_chain()
  if not cur then return end
  local now = r.time_precise()
  if now - chain_t < 0.5 then return end
  chain_t = now
  local tr = track_by_guid(cur.proj, cur.tg, cur.tr)
  if not tr then dbg("its track is gone"); release_all(); cur = nil; last_sel_g = false; return end
  cur.tr, cur.name = tr, track_name(tr)
  local list = wanted(tr)
  local same = #list == #cur.list
  for i = 1, #list do
    if not same then break end
    same = list[i].fg == cur.list[i].fg
  end
  if same then return end
  dbg("its chain changed: " .. #cur.list .. " -> " .. #list)
  -- a strip keeps the effect that was first on view first on view (an undo, a reorder in REAPER's own FX
  -- window): by position, the view jumped to another effect and let go of the one on view (2026-10-04)
  local anchor = strip and slots[1] and slots[1].fg
  if anchor then for i, e in ipairs(list) do if e.fg == anchor then first = i end end end
  if #list > 0 then cur.list = list
  elseif pin ~= "" then none_note(tr)
  else release_all(); cur = nil end
end

-- ── a double-click on an effect's name (rk_theme's rkth_dock_name, served by GainKit Plus) ──────────
-- The user (2026-10-03): "swing i double click the logo it docks. can we get that same functionality?"
local force_fg = nil                   -- taken even from its own window, by the next layout
-- Docked here: out to its own window. Closing that window brings it back, as for any window the user opens.
local function pop_out(s)
  local tr, fx = where(s)
  if not (tr and fx) then return end
  local w = r.TrackFX_GetFloatingWindow(tr, fx)
  if not (w and r.JS_Window_IsWindow(w)) then r.TrackFX_Show(tr, fx, 3); w = r.TrackFX_GetFloatingWindow(tr, fx) end
  if give_back(s, w) then
    r.JS_Window_Show(w, "SHOW")                          -- the float the dock had hidden, the plugin in it again
    s.away, s.canvas, s.wrapper = true, nil, nil
    dbg("pop out: " .. label(s))
  end
end
-- Not docked: its track in the dock, that effect on view, taken out of its own window (where the double-click
-- was). The dock goes on following from there: a pin moves to its track, else its track is selected (as EON
-- Swing's logo does). In the FX chain the chain keeps it (the dock's rule for the chain), its place says so.
-- req = "track GUID|FX GUID|time"; one older than 5 s (left from a run that ended) is dropped.
local function show_req(req)
  local tg, fg, t = req:match("^([^|]+)|([^|]+)|(.+)$")
  t = tonumber(t)
  if not (tg and fg and t) or r.time_precise() - t > 5 then dbg("show_req: stale or bad " .. req); return end
  local tr = track_by_guid(r.EnumProjects(-1), tg, nil)
  local fx = tr and fx_by_guid(tr, fg, nil)
  local k = fx and kind_of(tr, fx)
  if not k then dbg("show_req: not in this project"); return end
  for _, s in ipairs(slots) do
    if s.fg == fg and s.canvas then
      if opt.dblclick == "1" then
        pop_out(s)
        -- a one-plugin tab that asks for it (Gumbo's: ONLY.close_on_pop; the owner, 2026-11-01: "when you float it,
        -- the dock is still there") closes with the pop-out: the bar's X, at the end of this tick
        if ONLY and ONLY.close_on_pop and s.away then want_close = true end
      else dbg("show_req: pop-out off (the gear)") end
      return
    end
  end
  if k ~= kind then kind = k; r.SetExtState(EXT, "kind", KINDS[k].key, true) end   -- STRIP off later: this one
  prefer[tg] = fg
  local master = tr == r.GetMasterTrack(0)
  if pin ~= "" then
    pin = master and "MASTER" or tg
    r.SetExtState(EXT, "pin", pin, true)
  else
    -- exactly its track selected, by the API (an action could add an undo point): every selected track off, the
    -- master too (the dock follows a selected master FIRST: left on, it would win over this track; the audit)
    for i = r.CountSelectedTracks(0) - 1, 0, -1 do r.SetTrackSelected(r.GetSelectedTrack(0, i), false) end
    r.SetTrackSelected(r.GetMasterTrack(0), false)
    r.SetTrackSelected(tr, true)
  end
  last_sel_g = tg
  local list = wanted(tr)
  show_track(tr, list)
  for i, e in ipairs(list) do if e.fg == fg then first = i end end   -- on view (a strip steps back at its end)
  force_fg = fg
  for _, s in ipairs(slots) do
    if s.fg == fg and s.away then take(s, true) end      -- on view already, in its own window: back in
  end
  dbg("show_req: " .. track_name(tr) .. ":" .. KINDS[k].short)
end

-- Where each effect goes, then the dock takes the new ones and lets go of the ones that left. STRIP off: the
-- first fills the dock. STRIP on: from the first on view, as many as fit at their least widths; the room left
-- over goes to each in proportion to how far it can grow, up to its own window's width, and past that in
-- proportion to its width, so the strip always fills the dock. Scrolled to the end with room to spare, it steps
-- back so no room is wasted.
-- STRIP's < > can wrap the bar a row taller, so the arrows are decided from the bar as it is without them and, when
-- some do not fit, again with them (as many or fewer fit then, so they stay): never from the last frame's arrows. A
-- dock one bar row tall flipped forever on those (2026-10-09: the arrows took the row, no room, no arrows, room...,
-- ~8 times a second, new floats each time). No room even then: nothing on view, the bar one row, no arrows.
local function layout()
  local ok, w, h = r.JS_Window_GetClientSize(dock)
  if not ok then return end
  local list = cur and cur.list or {}
  local b, want
  -- ACROSS (side by side, the dock's full height each) or DOWN (stacked, the dock's full width each: a side
  -- docker; the user, 2026-10-07). The gear's Layout: auto = down when the plugin area (under the bar without the
  -- arrows) is taller than wide. lay_down is a GLOBAL on purpose (the 200-local limit; publish() reads it).
  lay_down = opt.layout == "down" or (opt.layout == "auto" and h - bar_h(false) > w)
  for pass = 1, 2 do
    b, want = bar_h(pass == 2), {}
    on_view, more_left, more_right = {}, false, false
    if #list > 0 and w >= 2 and h >= b + 2 then
      local body = h - b
      if not strip then
        want[1] = { e = list[1], x = 0, y = b, w = w, h = body }
      else
        local gap = math.max(1, math.floor(C.GAP * sc + 0.5))
        local span = lay_down and body or w                           -- the axis the effects line up on
        local function mn(e) local k = KINDS[e.kind]; return math.floor((lay_down and k.minh or k.minw) * sc + 0.5) end
        local function nat(e) local k = KINDS[e.kind]; return (lay_down and k.h or k.w) * sc end
        local function fits_from(s)
          local n, used = 0, 0
          for i = s, #list do
            local need = mn(list[i]) + (n > 0 and gap or 0)
            if n > 0 and used + need > span then break end
            n, used = n + 1, used + need
          end
          return n
        end
        first = math.max(1, math.min(first, #list))
        while first > 1 and first - 1 + fits_from(first - 1) - 1 >= #list do first = first - 1 end
        local n = fits_from(first)
        local last = first + n - 1
        more_left, more_right = first > 1, last < #list
        local room = span - gap * (n - 1)
        local smin, snat = 0, 0
        for i = first, last do smin = smin + mn(list[i]); snat = snat + nat(list[i]) end
        local pos = 0
        for i = first, last do
          local e = list[i]
          local m, nt = mn(e), nat(e)
          local cw
          if room <= smin then cw = m
          elseif room <= snat then cw = m + (nt - m) * (room - smin) / (snat - smin)
          else cw = nt * room / snat end
          cw = i == last and span - pos or math.floor(cw + 0.5)
          cw = math.max(2, cw)
          if lay_down then want[#want + 1] = { e = e, x = 0, y = b + pos, w = w, h = cw }
          else want[#want + 1] = { e = e, x = pos, y = b, w = cw, h = body } end
          pos = pos + cw + gap
          on_view[e.fg] = true
        end
      end
    end
    if not (more_left or more_right) then break end
  end
  local have = {}
  for _, s in ipairs(slots) do have[s.fg] = s end
  for _, s in ipairs(KEEP.leaving) do if not have[s.fg] then have[s.fg] = s end end   -- still on view from a switch
  KEEP.leaving = {}
  local new, fresh = {}, {}
  for _, v in ipairs(want) do
    local s = have[v.e.fg]
    if s then
      have[v.e.fg] = nil
    else
      s = { proj = cur.proj, tg = cur.tg, tr = cur.tr, fg = v.e.fg, fx = v.e.fx, kind = v.e.kind, name = cur.name }
      fresh[#fresh + 1] = s
    end
    s.x, s.y, s.w, s.h = v.x, v.y, v.w, v.h
    new[#new + 1] = s
  end
  -- A switch (the user, 2026-10-07: "not flicker when i switch tracks"; dock_switch_run.py filmed a blank frame or
  -- two on every one): the new effects are taken while the ones going stay on view. A surface from a NEW float has
  -- not drawn yet, so it waits out of view (hold_out, fit) for KEEP.REVEAL; then all of them come on view at once,
  -- on top, and only then do the old ones go (their floats KEPT a few seconds, KEEP). A kept surface has drawn
  -- already and comes on view at once.
  slots = new
  KEEP.staging = next(have) ~= nil
  for _, s in ipairs(fresh) do take(s, s.fg == force_fg) end
  KEEP.staging = false
  force_fg = nil
  local now, waiting = r.time_precise(), false
  for _, s in ipairs(slots) do if s.hold_out then waiting = true end end
  if waiting and not KEEP.reveal_t then KEEP.reveal_t = now + KEEP.REVEAL end
  if KEEP.reveal_t and (now >= KEEP.reveal_t or not waiting) then
    for _, s in ipairs(slots) do s.hold_out = nil end
    KEEP.reveal_t, waiting = nil, false
  end
  for _, s in ipairs(slots) do fit(s) end
  for _, s in pairs(have) do KEEP.leaving[#KEEP.leaving + 1] = s end
  if not waiting and KEEP.leaving[1] then
    local t0 = r.time_precise()
    local keep = not KEEP.seen()                             -- the mixer on screen: the old strip's faces back now
    dbg(string.format("switch: %d let go, %s (looked in %.1f ms)", #KEEP.leaving,
      keep and "kept (the mixer is not on screen)" or "closed (the mixer is on screen)", (r.time_precise() - t0) * 1000))
    for _, s in ipairs(KEEP.leaving) do release(s, keep) end
    KEEP.leaving = {}
  end
end

-- ── REAPER's docker tabs (the user: "maybe an action to turn them on and off") ───────────────────────
-- REAPER's own option, "Dockers: Compact when small and single tab" (the preference dockcompactsingle): a
-- docker holding one window shows a thin edge instead of its tab bar while it is smaller than
-- dock_mini_tab_size. Off here = compact on with that size raised past any screen, so every docker with one
-- window loses its tabs; a docker holding two keeps them (they switch between the two). It is REAPER-wide.
-- Measured 2026-10-03 (tabs_probe.lua, tabs2_probe.lua): it takes effect when the dockers are laid out again;
-- set_config_var_string REFUSES dockcompactsingle (returns 0, the value stays), so the switch is flipped with
-- REAPER's own action and only read here; dock_mini_tab_size it does set. Showing the tabs again puts back what
-- the user had: the switch as it was, and the size limit.
local compact_cmd
local function cfg_num(name)
  local ok, v = r.get_config_var_string(name)
  return ok and tonumber(v) or nil
end
local function compact_on() return (cfg_num("dockcompactsingle") or 0) ~= 0 end
-- The action: 41691 in REAPER 7.81 when its name says so, or, in a translated REAPER (its name is not English
-- there: the audit, 2026-10-03), when it is an on/off action whose state is the preference's own; else the English
-- name anywhere in the list (another REAPER numbering). 0 = none.
local function compact_action()
  if compact_cmd then return compact_cmd end
  local t = r.kbd_getTextFromCmd(41691, 0)
  local st = r.GetToggleCommandState(41691)
  if (t and t:lower() == C.COMPACT_NAME) or (st >= 0 and (st == 1) == compact_on()) then compact_cmd = 41691; return 41691 end
  for i = 40000, 70000 do
    t = r.kbd_getTextFromCmd(i, 0)
    if t and t:lower() == C.COMPACT_NAME then compact_cmd = i; return i end
  end
  compact_cmd = 0
  return 0
end
-- Flip the preference through its action, and check that it flipped: an action that turns out to be another
-- one is run again (put back) and never used again.
local function flip_compact()
  local cmd = compact_action()
  if cmd == 0 then return false end
  local before = compact_on()
  r.Main_OnCommand(cmd, 0)
  if compact_on() ~= before then return true end
  r.Main_OnCommand(cmd, 0)
  compact_cmd = 0
  dbg("tabs: action " .. cmd .. " did not flip dockcompactsingle: put back, not used again")
  return false
end
local function tabs_hidden()
  return compact_on() and (cfg_num("dock_mini_tab_size") or 0) >= 4000
end
local function set_tabs_hidden(on)
  if not r.set_config_var_string or compact_action() == 0 then return end   -- an older REAPER: nothing to do
  local compact = compact_on()
  if on then
    local size = cfg_num("dock_mini_tab_size")
    if size and size < 4000 then r.SetExtState(EXT, "mini_tab_size_was", tostring(size), true) end
    r.SetExtState(EXT, "compact_was", compact and "1" or "0", true)
    r.set_config_var_string("dock_mini_tab_size", "4000", 1)
    if not compact then flip_compact() end
  else
    if compact and r.GetExtState(EXT, "compact_was") == "0" then flip_compact() end
    local was = tonumber(r.GetExtState(EXT, "mini_tab_size_was")) or 200      -- REAPER's own default
    r.set_config_var_string("dock_mini_tab_size", tostring(math.min(was, 3999)), 1)
  end
  r.DockWindowRefresh()
  dbg("tabs hidden: " .. tostring(on) .. " -> " .. tostring(tabs_hidden()) .. " (compact " ..
    tostring(cfg_num("dockcompactsingle")) .. ", size " .. tostring(cfg_num("dock_mini_tab_size")) .. ")")
end

-- ── the bar ──────────────────────────────────────────────────────────────────────────────────────
local hits = {}                        -- this frame's buttons: { x0, x1, y0, y1, act }
local pub_name_hit, pub_ticon_hit = "", ""   -- the name's and the icon's boxes this frame (tests)
local bar_chips = {}                   -- this frame's chips: { kind, fg (nil = dim), long, short, x0, x1, y0, y1 }
local drag = nil                       -- a chip held down: { i, kind, fg, x0, y0, dx, moved, before, mark, noop, inside }
local has_cache, has_key, has_t = { list = {}, has = {} }, "", 0
-- the shown track's chain in order (chain_items) and which of the seven it has (the dim chips), looked up about
-- twice a second and at once after the dock moves or adds one (has_key = "")
local function bar_chain(tr)
  local key = tr and (r.GetTrackGUID(tr) .. r.TrackFX_GetCount(tr)) or ""
  local now = r.time_precise()
  if key ~= has_key or now - has_t > 0.5 then
    has_key, has_t = key, now
    local list, has = chain_items(tr), {}
    for _, e in ipairs(list) do if e.kind then has[e.kind] = true end end
    has_cache = { list = list, has = has }
  end
  return has_cache
end

local function shown_track()
  if cur then return track_by_guid(cur.proj, cur.tg, cur.tr) end
  return followed()
end

-- One row when everything fits (long labels, then short); two rows in a narrow dock (seen 2026-10-03: a
-- 255 px dock cut TABS off and dropped the name): the chips on top, the track's name with the rest under. A
-- chain too long for one row of chips even then wraps them onto more rows (Codex delta audit, 2026-10-05: the
-- chips past the edge could not be reached), the name and the buttons always on the last row.
-- The chips: the track's chain in the order it runs, the seven as chips (a second copy numbered: 3-BAND, 3-BAND 2),
-- any other plugins as a grey marker, one per run of them (the first one's name, "+2" for two more; the user,
-- 2026-10-04: "when a non reakit plugin is there will it say so?"), then the kinds it does not have, dim.
-- STRIP on: the ones on view light, and < > appear when the track has more than fit; STRIP off: the one shown
-- lights (the chosen kind's dim chip when nothing is shown). A marker is never dragged, only dropped beside.
-- An icon drawn by hand in the current colour, inside the box x, y, w, h (u = one unit at the display scale).
local function icon_draw(which, x, y, w, h)
  local u = math.max(1, math.floor(sc + 0.5))
  local k = math.max(2, math.floor(2 * sc))
  if which == ICON.ctrack or which == ICON.call then
    -- a window with a cross; "all": a second window behind it
    local iw, ih = w - 3 * u, math.floor(9 * sc)
    local ix, iy = x, y + math.floor((h - ih - 3 * u) / 2)
    if which == ICON.call then
      gfx.rect(ix + 3 * u, iy, iw, ih, 0)                                       -- the window behind
      local cr, cg, cb = gfx.r, gfx.g, gfx.b
      gfx.set(0.11, 0.12, 0.14, 1); gfx.rect(ix, iy + 3 * u, iw, ih, 1)        -- the one in front covers it
      gfx.set(cr, cg, cb, 1)
    else
      ix = ix + math.floor(1.5 * u)
    end
    local fy = iy + 3 * u
    gfx.rect(ix, fy, iw, ih, 0)
    gfx.rect(ix, fy, iw, 2 * u, 1)                                              -- its title bar
    local cx, cy = ix + iw / 2, fy + 2 * u + (ih - 2 * u) / 2
    gfx.line(cx - k, cy - k, cx + k, cy + k); gfx.line(cx - k, cy + k, cx + k, cy - k)
  elseif which == ICON.pin then
    -- a push pin: the head, the collar under it, the needle down the middle
    local cx = x + w / 2
    local hw, hh = math.floor(w * 0.45), math.floor(h * 0.3)
    local top = y + math.floor(h * 0.12)
    gfx.rect(cx - hw / 2, top, hw, hh, 1)
    gfx.rect(cx - w * 0.4, top + hh, w * 0.8, 2 * u, 1)
    gfx.line(cx, top + hh + 2 * u, cx, y + h - math.floor(h * 0.12))
  elseif which == ICON.gear then
    -- a ring with eight teeth and a hole
    local cx, cy = x + w / 2, y + h / 2
    local rr = math.max(3, math.floor(h * 0.26))
    gfx.circle(cx, cy, rr, 0, 1)
    gfx.circle(cx, cy, math.max(1, math.floor(rr * 0.35)), 0, 1)
    for i = 0, 7 do
      local a = i * math.pi / 4
      gfx.line(cx + math.cos(a) * rr, cy + math.sin(a) * rr, cx + math.cos(a) * (rr + 2 * u), cy + math.sin(a) * (rr + 2 * u), 1)
    end
  elseif which == ICON.fold then
    -- a chevron pointing up: fold the bar
    local cx, cy = x + w / 2, y + h / 2
    gfx.line(cx - 2 * k, cy + k, cx, cy - k, 1); gfx.line(cx, cy - k, cx + 2 * k, cy + k, 1)
  elseif which == ICON.x then
    local cx, cy = x + w / 2, y + h / 2
    local kk = k + u
    gfx.line(cx - kk, cy - kk, cx + kk, cy + kk, 1); gfx.line(cx - kk, cy + kk, cx + kk, cy - kk, 1)
  end
end

-- What a button or chip says when the pointer rests on it (C.TIP_DELAY)
ICON.tips = {
  closetrack = "Close this track's FX windows", closeall = "Close all FX windows",
  strip = "STRIP: every effect side by side", pin = "PIN: stay on this track", tabs = "The docker's tabs",
  gear = "Options", fold = "Fold the bar", close = "Close the dock", left = "Earlier effects", right = "Later effects",
  handle = "Click: open the bar", ticon = "Track icon: click to pick one; right-click for the track's menu", name = "Click to rename the track; right-click for its menu",
  num = "Track colour: click for the palette",
  slot = "SLOT: the same effect row on every mixer strip; the wheel here steps it",
}

-- ── renaming the track on the bar ─────────────────────────────────────────────────────────────────
-- A click on the track's name turns it into a text field in place (the user, 2026-10-05: "change the track name
-- right there in the top"). Enter sets the name on the track in one undo step, Escape puts the old one back, a click
-- anywhere else on the bar sets it too, and the field closes by itself when the dock loses the keyboard or the
-- shown track changes. Keys come from gfx.getchar while the field is open (drained every frame, so none reach the
-- close check below); a Unicode key arrives as REAPER sends it and is kept as UTF-8. The master keeps "MASTER".
-- Test hooks: name_req = "start" | "commit" | "cancel" | "type:<text>"; published name_edit ("1 <text>" / "0"),
-- name_hit and ticon_hit (the two spots' boxes in client pixels, "x0,y0,x1,y1").
local NAME = { on = false, tr = nil, text = "", cur = 0 }
local function name_edit_start(tr)
  if not tr or tr == r.GetMasterTrack(0) then return end
  local _, raw = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)   -- the field itself: "" for an unnamed track
  NAME.on, NAME.tr, NAME.text = true, tr, raw or ""
  NAME.cur = #NAME.text
  dbg("rename: start on " .. NAME.text)
end
local function name_edit_end(commit)
  if not NAME.on then return end
  local tr = NAME.tr
  if commit and tr and r.ValidatePtr2(0, tr, "MediaTrack*") then
    local _, old = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
    if NAME.text ~= old then
      r.Undo_BeginBlock()
      r.GetSetMediaTrackInfo_String(tr, "P_NAME", NAME.text, true)
      r.Undo_EndBlock("ReaKit FX dock: rename track to " .. NAME.text, -1)
      r.TrackList_AdjustWindows(false)
      dbg("rename: " .. old .. " -> " .. NAME.text)
    end
  elseif not commit then dbg("rename: cancelled") end
  NAME.on, NAME.tr = false, nil
  has_key = ""
end
local function name_insert(ch)
  NAME.text = NAME.text:sub(1, NAME.cur) .. ch .. NAME.text:sub(NAME.cur + 1)
  NAME.cur = NAME.cur + #ch
end
local function name_keys()                                        -- false when the window is gone
  while true do
    local c = gfx.getchar()
    if c < 0 then return false end
    if c == 0 then return true end
    local uni = c >= 0x10000000                                   -- REAPER's flag on a Unicode key
    if uni then c = c - 0x10000000 end
    if c == 13 then name_edit_end(true)
    elseif c == 27 then name_edit_end(false)
    elseif c == 8 then                                              -- backspace: the character before the caret
      if NAME.cur > 0 then
        local p = utf8.offset(NAME.text, -1, NAME.cur + 1) or NAME.cur
        NAME.text = NAME.text:sub(1, p - 1) .. NAME.text:sub(NAME.cur + 1); NAME.cur = p - 1
      end
    elseif c == 6579564 then                                        -- delete: the character after it
      if NAME.cur < #NAME.text then
        local n = utf8.offset(NAME.text, 2, NAME.cur + 1) or (#NAME.text + 1)
        NAME.text = NAME.text:sub(1, NAME.cur) .. NAME.text:sub(n)
      end
    elseif c == 1818584692 then if NAME.cur > 0 then NAME.cur = (utf8.offset(NAME.text, -1, NAME.cur + 1) or 1) - 1 end
    elseif c == 1919379572 then if NAME.cur < #NAME.text then NAME.cur = (utf8.offset(NAME.text, 2, NAME.cur + 1) or (#NAME.text + 1)) - 1 end
    elseif c == 1752132965 then NAME.cur = 0
    elseif c == 6647396 then NAME.cur = #NAME.text
    elseif c >= 32 and c ~= 127 and (uni or c < 256) and c < 0x110000 then name_insert(utf8.char(math.floor(c)))
    else dbg("rename: key " .. tostring(c) .. " ignored") end
    if not NAME.on then return true end
  end
end

-- The bar folded: a handle in the track's colour (or the bar's grey), a small tab with a chevron at the middle.
local function draw_handle(tr)
  local w, hb = gfx.w, bar_h()
  local has, cr, cg, cb = track_color(tr)
  -- the track's colour on the handle: only while the track colour is on at all (the user, 2026-10-05, set it Off and
  -- the handle stayed green: "the menu changes dont take effect")
  if has and opt.fold_color == "1" and opt.color ~= "0" then gfx.set(cr, cg, cb, 1) else gfx.set(0.25, 0.27, 0.31, 1) end
  gfx.rect(0, 0, w, hb, 1)
  local tw = math.floor(26 * sc)
  local tx = math.floor((w - tw) / 2)
  gfx.set(0.11, 0.12, 0.14, 0.9); gfx.rect(tx, 0, tw, hb, 1)
  gfx.set(0.80, 0.82, 0.86, 1)
  local cx, cy, k = tx + tw / 2, hb / 2, math.max(2, math.floor(1.5 * sc))
  gfx.line(cx - 2 * k, cy - k, cx, cy + k, 1); gfx.line(cx, cy + k, cx + 2 * k, cy - k, 1)
  hits = { { 0, w, 0, hb, "handle" } }
  bar_chips = {}
  bar_rows, bar_chip_rows = 1, 1
end

local function draw_bar()
  local w = gfx.w
  local tr = shown_track()
  if folded() then draw_handle(tr); return end
  local fs = math.max(9, math.floor(11 * sc + 0.5))
  gfx.setfont(1, "Arial", fs, string.byte("b"))
  local pad, gap = math.floor(7 * sc), math.floor(3 * sc)
  local ipad = math.floor(4 * sc)                        -- an icon's padding (narrower than a word's)
  local nx = math.floor(8 * sc)
  local th = select(2, gfx.measurestr("Hg"))
  local bc = bar_chain(tr)
  local chips, count = {}, {}
  for _, e in ipairs(bc.list) do
    if ONLY and e.kind ~= kind then                      -- a one-plugin tab: its own chips alone
    elseif e.kind then
      count[e.kind] = (count[e.kind] or 0) + 1
      local n = count[e.kind]
      chips[#chips + 1] = { kind = e.kind, fg = e.fg, long = KINDS[e.kind].long .. (n > 1 and " " .. n or ""),
                            short = KINDS[e.kind].short .. (n > 1 and tostring(n) or "") }
    else
      local m = chips[#chips]
      if m and m.other then
        m.n = m.n + 1                                    -- another one in the same run
      else
        chips[#chips + 1] = { other = true, ofg = e.fg, n = 1, name = e.name }
      end
    end
  end
  local function cut(s, n)                               -- n characters, never half of a UTF-8 one
    local len = utf8.len(s)
    if not len then return #s > n and s:sub(1, n) .. ".." or s end
    return len > n and s:sub(1, utf8.offset(s, n) - 1) .. ".." or s
  end
  for _, c in ipairs(chips) do
    if c.other then
      local more = c.n > 1 and " +" .. (c.n - 1) or ""
      c.long, c.short = cut(c.name, 14) .. more, cut(c.name, 5) .. more
    end
  end
  local n_chain = #chips                                 -- the chain's chips; the dim ones follow a divider
  for k = 1, #KINDS do
    if not bc.has[k] and (not ONLY or k == kind) then chips[#chips + 1] = { kind = k, long = KINDS[k].long, short = KINDS[k].short } end
  end
  bar_chips = chips
  local div_w = (n_chain > 0 and #chips > n_chain) and math.floor(7 * sc) or 0   -- the divider's room
  local slim = math.floor(6 * sc)                        -- a marker with no words (label false): a thin box
  local icon_w = math.floor(13 * sc)                     -- every icon's width
  local function width(labels)
    local t = 0
    for _, s in ipairs(labels) do
      local s1 = type(s) == "table" and s[1] or s
      if s == false then t = t + slim + gap
      elseif ICON.set[s1] then t = t + icon_w + 2 * ipad + gap
      else t = t + gfx.measurestr(s1) + 2 * pad + gap end
    end
    return t
  end
  local pinned, hidden = pin ~= "", tabs_hidden()
  local function right_set(tabs_label, arrows)           -- { label, act, lit, dim }
    local t = {}
    if arrows then
      t[#t + 1] = { "<", "left", false, not more_left }
      t[#t + 1] = { ">", "right", false, not more_right }
    end
    t[#t + 1] = { ICON.ctrack, "closetrack", false, false }
    t[#t + 1] = { ICON.call, "closeall", false, false }
    if not ONLY then                                     -- a one-plugin tab: no STRIP, no SLOT
      t[#t + 1] = { "STRIP", "strip", strip, false }
      t[#t + 1] = { "SLOT", "slot", false, false }        -- the same effect row on every mixer strip (SLOT below)
    end
    t[#t + 1] = { ICON.pin, "pin", pinned, false }
    t[#t + 1] = { tabs_label, "tabs", false, false }
    t[#t + 1] = { ICON.gear, "gear", false, false }
    if opt.fold == "1" then t[#t + 1] = { ICON.fold, "fold", false, false } end
    t[#t + 1] = { ICON.x, "close", false, false }
    return t
  end
  local long, short = {}, {}
  for i, c in ipairs(chips) do long[i], short[i] = c.long, c.short end
  -- "Full effect names" (the gear): on = the full names ALWAYS, the bar wrapping to more rows when they do not fit
  -- in one (the user, 2026-10-05: it looked dead when the bar quietly fell back to the short ones); off = the short
  local full = opt.labels == "long"
  if not full then for i = 1, #long do long[i] = short[i] end end
  local row = math.floor(C.BAR * sc + 0.5)
  local sy = stripe_h()                                  -- the rows start under the stripe
  local labels, right, rows, crows
  local function cwidth(i)
    local c = chips[i]
    if c.other then return labels[i] and gfx.measurestr(labels[i]) + 2 * pad or slim end
    return gfx.measurestr(labels[i]) + 2 * pad
  end
  -- The bar's rows with STRIP's < > or without them: layout() decides the arrows from both, never from the last
  -- frame's (a dock one bar row tall flipped forever, 2026-10-09). The last call sets the chips' rows: this frame's.
  local function fit_rows(arrows)
    local right_long = right_set(hidden and "SHOW TABS" or "HIDE TABS", arrows)
    local right_short = right_set("TABS", arrows)
    labels, right, rows = long, right_long, 1
    if width(right) + width(labels) + div_w + 60 * sc > w then
      right = right_short
      if width(right) + width(labels) + div_w + nx + 4 * sc > w then
        rows = 2                                         -- the chips on their own row(s), the rest under them
        right = width(right_long) + nx + 40 * sc <= w and right_long or right_short
        if not full and width(labels) + div_w + nx > w then   -- a long chain in a narrow dock: markers lose their words
          local tiny = {}
          for i, c in ipairs(chips) do tiny[i] = (not c.other) and c.short end
          labels = tiny
        end
      end
    end
    -- each chip's row: one row unless even the narrow layout's labels run past the edge; then they wrap
    crows = 1
    local x0 = nx - pad
    local x = x0
    for i, c in ipairs(chips) do
      local cw = cwidth(i) + (i == n_chain + 1 and div_w or 0)
      if rows > 1 and x > x0 and x + cw > w then crows = crows + 1; x = x0 end
      c.row = crows - 1
      x = x + cw + gap
    end
    if rows > 1 then rows = crows + 1 end
    bar_rows_ar[arrows] = rows
  end
  local arrows = strip and (more_left or more_right)
  if strip then fit_rows(not arrows) end
  fit_rows(arrows)
  bar_rows, bar_chip_rows = rows, crows
  local b = bar_h()
  -- the bar's face: its grey, or the track's colour as a band across it; the stripe along the top
  local has, cr, cg, cb = track_color(tr)
  if opt.color == "band" and has then gfx.set(0.11 * 0.55 + cr * 0.45, 0.12 * 0.55 + cg * 0.45, 0.14 * 0.55 + cb * 0.45, 1)
  else gfx.set(0.11, 0.12, 0.14, 1) end
  gfx.rect(0, 0, w, b, 1)
  if sy > 0 then
    if has then gfx.set(cr, cg, cb, 1) else gfx.set(0.25, 0.27, 0.31, 1) end
    gfx.rect(0, 0, w, sy, 1)
  end
  gfx.set(0.25, 0.27, 0.31, 1); gfx.line(0, b - 1, w, b - 1)
  hits = {}
  local function chip(x, y, text, lit, dim, act)
    local icon = ICON.set[text]
    local cw = icon and (icon_w + 2 * ipad) or (gfx.measurestr(text) + 2 * pad)
    local y0, ch = y + math.floor(4 * sc), row - math.floor(8 * sc)
    local hot = hover_act == act and not drag
    if lit then gfx.set(0.84, 0.44, 0.14, 1); gfx.rect(x, y0, cw, ch, 1)
    elseif hot and not dim then gfx.set(1, 1, 1, 0.07); gfx.rect(x, y0, cw, ch, 1) end
    if lit then gfx.set(0.08, 0.08, 0.09, 1) elseif dim then gfx.set(0.38, 0.40, 0.44, 1)
    elseif hot then gfx.set(0.96, 0.97, 0.99, 1) else gfx.set(0.80, 0.82, 0.86, 1) end
    if icon then
      icon_draw(text, x + ipad, y0, icon_w, ch)
    else
      gfx.x, gfx.y = x + pad, y0 + (ch - th) / 2
      gfx.drawstr(text)
    end
    hits[#hits + 1] = { x, x + cw, y, y + row, act }
    return x + cw + gap
  end
  local name = tr and track_name(tr) or ""
  local master = tr and tr == r.GetMasterTrack(0)
  if NAME.on and (NAME.tr ~= tr or folded()) then name_edit_end(NAME.tr == tr) end   -- the track changed: dropped; folded: set
  pub_name_hit, pub_ticon_hit = "", ""
  local num = (tr and not master and opt.trackno == "1") and tostring(math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))) or nil
  local has_icon = track_icon(tr)
  local function name_at(y, room)                        -- icon, number, the name cut with ".." to its room
    if room <= 20 * sc or (name == "" and (master or not tr)) then return false end
    local x = nx
    local ih = row - math.floor(8 * sc)
    if has_icon and ticon.w > 0 and ticon.h > 0 then
      local iw = math.floor(ih * ticon.w / ticon.h + 0.5)
      gfx.blit(1, 1, 0, 0, 0, ticon.w, ticon.h, x, y + math.floor(4 * sc), iw, ih)
      hits[#hits + 1] = { x, x + iw, y, y + row, "ticon" }     -- the picker's door
      pub_ticon_hit = string.format("%d,%d,%d,%d", x, y, x + iw, y + row)
      x = x + iw + math.floor(5 * sc)
    elseif opt.icon == "1" and not master then                 -- no icon yet: a faint square where one would sit
      local iw, y0 = ih, y + math.floor(4 * sc)
      local hot = hover_act == "ticon"
      gfx.set(1, 1, 1, hot and 0.35 or 0.16); gfx.rect(x, y0, iw, ih, 0)
      local k = math.max(1, math.floor(sc)); local cx, cy = x + iw / 2, y0 + ih / 2
      gfx.rect(cx - 3 * k, cy - k / 2, 6 * k, k, 1); gfx.rect(cx - k / 2, cy - 3 * k, k, 6 * k, 1)
      hits[#hits + 1] = { x, x + iw, y, y + row, "ticon" }
      pub_ticon_hit = string.format("%d,%d,%d,%d", x, y, x + iw, y + row)
      x = x + iw + math.floor(5 * sc)
    end
    if num then                                                -- a small swatch in the track's colour: the palette's door
      local has, cr, cg, cb = track_color(tr)
      local nw, p2 = gfx.measurestr(num), math.floor(4 * sc)
      local y0, ih2 = y + math.floor(5 * sc), row - math.floor(10 * sc)
      local hot = hover_act == "num"
      if has then gfx.set(cr, cg, cb, hot and 1 or 0.85); gfx.rect(x, y0, nw + 2 * p2, ih2, 1)
      else gfx.set(1, 1, 1, hot and 0.35 or 0.16); gfx.rect(x, y0, nw + 2 * p2, ih2, 0) end
      local lum = has and (0.3 * cr + 0.59 * cg + 0.11 * cb) or 0
      if has and lum > 0.55 then gfx.set(0.08, 0.08, 0.09, 1) elseif has then gfx.set(0.97, 0.97, 0.98, 1) else gfx.set(0.55, 0.58, 0.63, 1) end
      gfx.x, gfx.y = x + p2, y + (row - th) / 2
      gfx.drawstr(num)
      hits[#hits + 1] = { x, x + nw + 2 * p2, y, y + row, "num" }
      x = x + nw + 2 * p2 + math.floor(5 * sc)
    end
    local left = room - (x - nx)
    if left <= 10 * sc then return true end
    if NAME.on and NAME.tr == tr then                          -- the field, in the name's place
      local fx0, fy0, fw, fh = x - math.floor(3 * sc), y + math.floor(4 * sc), left, ih
      gfx.set(0.10, 0.11, 0.13, 1); gfx.rect(fx0, fy0, fw, fh, 1)
      local has, cr, cg, cb = track_color(tr)
      if has then gfx.set(cr, cg, cb, 1) else gfx.set(0.84, 0.44, 0.14, 1) end
      gfx.rect(fx0, fy0, fw, fh, 0)
      local inner = fw - math.floor(8 * sc)
      local st = 1                                             -- the text scrolls so the caret stays in view
      while st <= NAME.cur and gfx.measurestr(NAME.text:sub(st, NAME.cur)) > inner do st = utf8.offset(NAME.text, 2, st) or (st + 1) end
      local shown = NAME.text:sub(st)
      gfx.set(0.95, 0.96, 0.98, 1)
      gfx.x, gfx.y = x, y + (row - th) / 2
      gfx.drawstr(shown, 0, fx0 + fw - math.floor(2 * sc), y + row)
      if math.floor(r.time_precise() * 2.5) % 2 == 0 then        -- the caret
        local cx = x + gfx.measurestr(NAME.text:sub(st, NAME.cur))
        gfx.rect(cx, fy0 + math.floor(2 * sc), math.max(1, math.floor(sc)), fh - math.floor(4 * sc), 1)
      end
      hits[#hits + 1] = { fx0, fx0 + fw, y, y + row, "name" }
      pub_name_hit = string.format("%d,%d,%d,%d", fx0, y, fx0 + fw, y + row)
      return true
    end
    local s = name
    while gfx.measurestr(s) > left and #s > 1 do s = s:sub(1, -2) end
    if s ~= name then s = s:sub(1, math.max(1, #s - 2)) .. ".." end
    if name == "" then s = "name"; gfx.set(0.45, 0.48, 0.52, 1) else gfx.set(0.92, 0.93, 0.95, 1) end   -- unnamed: a dim word to click
    gfx.x, gfx.y = x, y + (row - th) / 2
    gfx.drawstr(s)
    if not master then
      local nw = gfx.measurestr(s)
      hits[#hits + 1] = { x, x + nw, y, y + row, "name" }
      pub_name_hit = string.format("%d,%d,%d,%d", x, y, x + nw, y + row)
    end
    return true
  end
  local shown_fg = not strip and cur and cur.list[1] and cur.list[1].fg
  local function lit(c)
    if strip then return c.fg ~= nil and on_view[c.fg] == true end
    if c.fg then return c.fg == shown_fg end
    return c.kind == kind and not shown_fg               -- STRIP off and nothing shown: the chosen kind, as before
  end
  local function chips_from(x)                           -- each chip's box kept for the drag (bar_mouse)
    local xs, cr_ = x, 0
    for i, c in ipairs(chips) do
      if c.row ~= cr_ then cr_, x = c.row, xs end        -- the next row (draw_bar wrapped it)
      local yr = sy + cr_ * row
      if i == n_chain + 1 and div_w > 0 then             -- the divider: the chain's chips end, the dim ones begin
        gfx.set(0.36, 0.39, 0.44, 1)
        gfx.rect(x + math.floor(div_w / 2), yr + math.floor(6 * sc), math.max(1, math.floor(sc)), row - math.floor(12 * sc), 1)
        x = x + div_w
      end
      local x0 = x
      if c.other then                                    -- a marker: grey words in a thin box, never lit
        local cw = cwidth(i)
        local y0, ch = yr + math.floor(4 * sc), row - math.floor(8 * sc)
        gfx.set(0.30, 0.32, 0.36, 1); gfx.rect(x, y0, cw, ch, 0)
        if labels[i] then
          gfx.set(0.58, 0.60, 0.64, 1)
          gfx.x, gfx.y = x + pad, y0 + (ch - th) / 2
          gfx.drawstr(labels[i])
        end
        hits[#hits + 1] = { x, x + cw, yr, yr + row, "chip" .. i }
        x = x + cw + gap
      else
        x = chip(x, yr, labels[i], lit(c), not c.fg, "chip" .. i)
      end
      c.x0, c.x1, c.y0, c.y1 = x0, x - gap, yr, yr + row
    end
    return x
  end
  local rw = width(right)
  local x
  if rows == 1 then
    local room = w - rw - width(labels) - div_w - nx - math.floor(8 * sc)
    x = nx + (name_at(sy, room) and room or 0) + math.floor(4 * sc)
    x = chips_from(x)
    x = math.max(x, w - rw)
    for _, c in ipairs(right) do x = chip(x, sy, c[1], c[3], c[4], c[2]) end
  else
    x = chips_from(nx - pad)
    local ly = sy + row * crows                          -- the last row: the name and the buttons
    name_at(ly, w - rw - nx - math.floor(8 * sc))
    x = math.max(nx, w - rw)
    for _, c in ipairs(right) do x = chip(x, ly, c[1], c[3], c[4], c[2]) end
  end
  -- a chip being dragged: its own place faded, a line where it would land, the chip under the pointer
  if drag and drag.moved then
    local c = chips[drag.i]
    if c then
      gfx.set(0.11, 0.12, 0.14, 0.75); gfx.rect(c.x0, c.y0, c.x1 - c.x0, c.y1 - c.y0, 1)
      local my_ = sy + (drag.inside and drag.mrow or c.row or 0) * row   -- the row it would land on, else its own
      if drag.inside and drag.mark and not drag.noop then
        gfx.set(0.95, 0.55, 0.15, 1)
        gfx.rect(math.floor(drag.mark - sc), my_ + math.floor(3 * sc), math.max(2, math.floor(2 * sc)), row - math.floor(6 * sc), 1)
      end
      local gx = math.floor(gfx.mouse_x - drag.dx)
      local y0, ch = my_ + math.floor(4 * sc), row - math.floor(8 * sc)
      gfx.set(0.84, 0.44, 0.14, drag.inside and 0.9 or 0.45); gfx.rect(gx, y0, c.x1 - c.x0, ch, 1)
      gfx.set(0.08, 0.08, 0.09, 1)
      gfx.x, gfx.y = gx + pad, y0 + (ch - th) / 2
      gfx.drawstr(labels[drag.i])
    end
  end
  -- the tooltip: the pointer at rest on a button or chip for C.TIP_DELAY, a label beside it, inside the bar
  local tip_shown = nil                                  -- what the published tip says now (nothing = "")
  if opt.tips ~= "0" and hover_act and not drag and r.time_precise() - hover_t >= C.TIP_DELAY and not (NAME.on and hover_act == "name")
     and not SLOT.msg then                                 -- (SLOT's word has the room while it shows)
    local tip = ICON.tips[hover_act]
    local ci = hover_act:sub(1, 4) == "chip" and tonumber(hover_act:sub(5))
    local c = ci and chips[ci]
    if c then
      if c.other then tip = "Not a ReaKit effect; drop a chip beside it"
      elseif not c.fg then tip = "Not on this track: right-click or drag in to add"
      else tip = KINDS[c.kind].name .. ": click to show, drag to move it in the chain" end
    end
    if tip then
      gfx.setfont(1, "Arial", math.max(9, math.floor(10 * sc + 0.5)))
      local tw2, th2 = gfx.measurestr(tip)
      local bw, bh = tw2 + math.floor(12 * sc), th2 + math.floor(6 * sc)
      local mx, my = gfx.mouse_x, gfx.mouse_y
      local hr = math.max(0, math.min(math.floor((my - sy) / row), rows - 1))   -- the pointer's row
      local ty = sy + hr * row + math.floor((row - bh) / 2)
      local tx = math.max(0, math.min(mx + math.floor(14 * sc), w - bw))
      gfx.set(0.95, 0.95, 0.96, 1); gfx.rect(tx, ty, bw, bh, 1)
      gfx.set(0.10, 0.10, 0.12, 1)
      gfx.x, gfx.y = tx + math.floor(6 * sc), ty + math.floor(3 * sc)
      gfx.drawstr(tip)
      tip_shown = tip
    end
  end
  tip_shown = tip_shown or ""                            -- for tests: the tip on screen, "" when none (the Tooltips
  if tip_shown ~= pub.tip then pub.tip = tip_shown; r.SetExtState(EXT, "tip", tip_shown, false) end   -- switch off)
  -- SLOT's word when a run moved nothing or missed strips: an amber box at the button for a few seconds (a side door
  -- that stops working must say so, not go quiet; the user, 2026-10-08). SLOT.hit: the button's box, for the tests
  SLOT.hit = ""
  for _, h in ipairs(hits) do if h[5] == "slot" then SLOT.hit = string.format("%d,%d,%d,%d", h[1], h[3], h[2], h[4]) end end
  if SLOT.msg and r.time_precise() - SLOT.msg_t < 4 then
    gfx.setfont(1, "Arial", math.max(9, math.floor(10 * sc + 0.5)))
    local tw2, th2 = gfx.measurestr(SLOT.msg)
    local bw, bh = tw2 + math.floor(12 * sc), th2 + math.floor(6 * sc)
    local cx, cy = nx, sy
    for _, h in ipairs(hits) do if h[5] == "slot" then cx, cy = h[1], h[3] end end
    local tx = math.max(0, math.min(cx - math.floor(bw / 2), w - bw))
    local ty = cy + math.floor((row - bh) / 2)
    gfx.set(0.93, 0.72, 0.30, 1); gfx.rect(tx, ty, bw, bh, 1)
    gfx.set(0.10, 0.10, 0.12, 1)
    gfx.x, gfx.y = tx + math.floor(6 * sc), ty + math.floor(3 * sc)
    gfx.drawstr(SLOT.msg)
  elseif SLOT.msg then SLOT.msg = nil end
end

-- STRIP on: an effect's button brings its first one on view
local function scroll_to(k)
  if not cur then return end
  for i, e in ipairs(cur.list) do
    if e.kind == k then
      for _, s in ipairs(slots) do if s.fg == e.fg then return end end
      first = i
      return
    end
  end
end
local function set_kind(k)
  if ONLY and k ~= kind then return end   -- a one-plugin tab keeps its plugin
  if strip then
    if k ~= kind then kind = k; r.SetExtState(EXT, "kind", KINDS[k].key, true) end
    scroll_to(k)
    return
  end
  if k == kind then return end
  kind = k
  r.SetExtState(EXT, "kind", KINDS[k].key, true)
  follow(true)
end
-- The wheel over the bar (and < >, and the scroll_req test hook). STRIP on: the strip's view, one effect at a time.
-- STRIP off: the next (d > 0) or previous effect THE TRACK HAS, in chain order (cur.list holds only the shown one,
-- so the chain is read again), each of the seven once; nothing past the ends. A track without the shown effect (the
-- dock kept the last) steps onto its first or last (the user, 2026-10-12: "supposed to scroll when only one plugin
-- shows right?").
local function scroll(d)
  if not cur or d == 0 or ONLY then return end
  if strip then
    if d < 0 and more_left then first = first - 1 elseif d > 0 and more_right then first = first + 1 end
    return
  end
  local tr = track_by_guid(cur.proj, cur.tg, cur.tr)
  if not tr then return end
  local kinds, seen, i = {}, {}, nil
  for _, e in ipairs(chain_items(tr)) do
    if e.kind and not seen[e.kind] then seen[e.kind] = true; kinds[#kinds + 1] = e.kind end
  end
  for n, k in ipairs(kinds) do if k == kind then i = n; break end end
  local k = i and kinds[i + (d < 0 and -1 or 1)] or (not i and kinds[d > 0 and 1 or #kinds]) or nil
  if k then set_kind(k) end
end
-- STRIP on or off: the same track, the other way
local function set_strip(on)
  if on == strip or ONLY then return end
  strip = on
  r.SetExtState(EXT, "strip", on and "1" or "0", true)
  first = 1
  local tr = cur and track_by_guid(cur.proj, cur.tg, cur.tr)
  if not tr then follow(true); return end
  local list = wanted(tr)
  if #list > 0 then show_track(tr, list) else none_note(tr) end
end
local function set_pin(on)
  if on then
    local tr = shown_track()
    if not tr then return end
    pin = tr == r.GetMasterTrack(0) and "MASTER" or r.GetTrackGUID(tr)
  else
    pin = ""
  end
  r.SetExtState(EXT, "pin", pin, true)
  last_sel_g = false
  follow(true)
end
-- A chip clicked (not dragged): that copy. STRIP on: brought on view; STRIP off: the one the dock shows, on the
-- shown track (the chips are that track's).
local function show_copy(fg, k)
  if k ~= kind then kind = k; r.SetExtState(EXT, "kind", KINDS[k].key, true) end
  if strip then
    if not cur then return end
    for i, e in ipairs(cur.list) do
      if e.fg == fg then
        for _, s in ipairs(slots) do if s.fg == fg then return end end   -- on view already
        first = i
        return
      end
    end
    return
  end
  local tr = shown_track()
  if not tr then return end
  prefer[r.GetTrackGUID(tr)] = fg
  local list = wanted(tr)
  if #list > 0 then show_track(tr, list) end
end

-- After the dock changed the shown track's chain: the chips and the strip look again at once, and a strip keeps
-- the effect that was first on view first on view (anchor = its FX GUID), so a drop never makes the view jump.
-- ⚠ Not a nicety: an effect the dock lets go of closes its float, and REAPER adds its own "Close FX config" undo
-- point the first time any FX window closes (measured 2026-10-03). Scrolling to the moved effect let go of the one
-- on view in a narrow dock, that point landed on top, and Ctrl+Z undid it instead of the move (dockmove_probe.lua,
-- 2026-10-04, a narrow run). Anchored, a drop lets go of nothing unless the moved one itself leaves the view.
local function chain_changed(tr, anchor)
  has_key = ""
  if not (cur and cur.tg == r.GetTrackGUID(tr)) then return end
  cur.list = wanted(tr)
  chain_t = r.time_precise()                             -- just read: check_chain need not
  if not (strip and anchor) then return end
  for i, e in ipairs(cur.list) do if e.fg == anchor then first = i end end
end

-- A chip dragged along the bar: that effect moved in the track's own chain, right before the effect or plugin it
-- was dropped on (before = its FX GUID), or to the end (before = false). Everything else keeps its order; an FX
-- container moves nothing in or out of it. TrackFX_CopyToTrack's dest is the index in the FINAL chain, up or down
-- (measured 2026-10-04, fxmove_probe.lua: 0 -> 2 gives BCADE, 3 -> 1 gives ADBCE). One undo step.
local function move_fx(fg, before)
  local tr = shown_track()
  local s = tr and fx_by_guid(tr, fg)
  if not s then return end
  local dest
  if before then
    local t = fx_by_guid(tr, before)
    if not t then return end
    dest = s < t and t - 1 or t
  else
    dest = r.TrackFX_GetCount(tr) - 1
  end
  if dest == s then return end
  local k = kind_of(tr, s)
  local anchor = slots[1] and slots[1].fg                -- the first on view, kept first on view
  r.Undo_BeginBlock()
  r.TrackFX_CopyToTrack(tr, s, tr, dest, true)
  -- laid out NOW, inside the undo step: an effect the move pushes out of view (not only the moved one: a neighbour
  -- can leave a wide strip) is let go of here, so REAPER's "Close FX config" point joins this step instead of
  -- landing on top of it (Codex delta audit, 2026-10-05)
  chain_changed(tr, anchor)
  layout()
  r.Undo_EndBlock("ReaKit FX dock: move " .. KINDS[k].name .. " on " .. track_name(tr), -1)
  dbg("moved " .. KINDS[k].name .. " on " .. track_name(tr) .. ": " .. s .. " -> " .. dest)
end

-- Right-click a dim effect button (the shown track has none of it): add it to that track (the user, 2026-10-03:
-- "when the track does not have the fx can we right click add it"). Found as "Add a track with all seven" finds
-- them: by its listed name (any install), then the ReaPack package's path, then the EON install's; the right FILE
-- only, a namesake is taken out again. GainKit goes first in the chain (where the GainKit Plus actions put it),
-- the others at the end. Then it is the effect shown (STRIP off), or brought on view (STRIP on).
-- Dragged in from a dim chip (before ~= nil): where it was dropped, as move_fx places one (right before that
-- effect or plugin, or at the end of the chain).
local function add_kind(k, before)
  local tr = shown_track()
  if not tr or first_of(tr, k) then return end
  local at = k == 1 and -1000 or -1                      -- -1000 = position 0; -1 = a new one at the end
  if before then
    local t = fx_by_guid(tr, before)
    if not t then return end
    at = -1000 - t
  elseif before == false then
    at = -1
  end
  local anchor = slots[1] and slots[1].fg                -- a drop keeps the view where it was (chain_changed)
  r.Undo_BeginBlock()
  local fx = -1
  for _, n in ipairs({ "JS: EON: " .. KINDS[k].name, "ReaKit FX/FX/Eon_JSFX/FX/" .. KINDS[k].src, "EON/Eon_JSFX/FX/" .. KINDS[k].src }) do
    fx = r.TrackFX_AddByName(tr, n, false, at)
    if fx >= 0 then
      if kind_of(tr, fx) == k then break end
      r.TrackFX_Delete(tr, fx); fx = -1
    end
  end
  local fg, list
  if fx >= 0 and before ~= nil then
    -- dragged in: laid out now, inside the undo step, as move_fx does (an effect pushed out of view is let go of
    -- within it); the strip stays where it was
    if k ~= kind then kind = k; r.SetExtState(EXT, "kind", KINDS[k].key, true) end
    list = wanted(tr)
    show_track(tr, list)
    chain_changed(tr, anchor)
    layout()
  end
  r.Undo_EndBlock("ReaKit FX dock: add " .. KINDS[k].name .. " to " .. track_name(tr), -1)
  if fx < 0 then dbg("add " .. KINDS[k].name .. ": not found"); return end
  dbg("added " .. KINDS[k].name .. " to " .. track_name(tr) .. " at " .. fx)
  if before ~= nil then return end                       -- dragged in: done above
  if k ~= kind then kind = k; r.SetExtState(EXT, "kind", KINDS[k].key, true) end
  fg = r.TrackFX_GetFXGUID(tr, fx)
  list = wanted(tr)
  show_track(tr, list)
  for i, e in ipairs(list) do if e.fg == fg then first = i end end
  has_key = ""                                           -- the buttons look again at once
end

-- Where a dragged chip would land: the gap the pointer is in, among everything else on the track's chain (the
-- chips and the markers, in the order they run). before = the FX GUID it would sit right before (a marker: the
-- first plugin of its run), false = the end of the chain; mark = the line's x; noop = a move that changes nothing
-- (dropped back where it sits, or nothing else on the track).
local function drop_at(x, y)
  local others, me = {}, nil
  for _, c in ipairs(bar_chips) do
    if c.fg or c.ofg then
      if c.fg and c.fg == drag.fg then me = #others + 1 else others[#others + 1] = c end
    end
  end
  if drag.fg and #others == 0 then return nil, nil, true, 0 end
  -- the chips run in reading order over their rows: one counts as before the pointer on an earlier row, or on the
  -- pointer's row left of it (the row under the pointer, kept to the chip rows)
  local row = math.floor(C.BAR * sc + 0.5)
  local pr = math.max(0, math.min(math.floor((y - stripe_h()) / row), bar_chip_rows - 1))   -- under the stripe
  local j = 0
  for _, c in ipairs(others) do
    local cr = c.row or 0
    if cr < pr or (cr == pr and x > (c.x0 + c.x1) / 2) then j = j + 1 end
  end
  local nxt = others[j + 1]
  local mark, mrow
  if nxt and ((nxt.row or 0) == pr or j == 0) then mark, mrow = nxt.x0 - math.floor(2 * sc), nxt.row or 0
  elseif j > 0 then mark, mrow = others[j].x1 + math.floor(2 * sc), others[j].row or 0 end
  return nxt and (nxt.fg or nxt.ofg) or false, mark, drag.fg ~= nil and me == j + 1, mrow
end

-- The bar's mouse. A chip acts when it is let go: not moved, a click (that copy on view, or shown; a dim one: the
-- kind chosen, as before); moved, a drag (drop_at says where; let go off the bar, nothing happens). A right-click on
-- a dim chip adds that effect. The other buttons act on the press.
local last_cap = 0
-- ── the bar's window icon: close the FX windows ─────────────────────────────────────────────────────
-- The user, 2026-10-05: "i want a close all floating fx windows options in the dock. Maybe just an icon for like
-- close this tracks floating windows and all floating fx windows options." A click opens a menu with both. A float
-- the dock keeps hidden (it holds that plugin's surface, here or in EON Swing's dock) is not a window the user sees
-- and stays; one the user opened from the dock closes, and the dock takes that plugin back as it always does.
-- Each counts the windows it closed (for tests: ExtState "closed").
local function close_track_floats(tr)
  local n = 0
  if not (tr and r.ValidatePtr2(0, tr, "MediaTrack*")) then return 0 end
  local function walk(fx)
    local fw = r.TrackFX_GetFloatingWindow(tr, fx)
    if fw and r.JS_Window_IsVisible(fw) then r.TrackFX_Show(tr, fx, 2); n = n + 1 end
    local ok, cc = r.TrackFX_GetNamedConfigParm(tr, fx, "container_count")   -- inside an FX container too
    cc = ok and tonumber(cc)
    for i = 0, (cc or 0) - 1 do
      local ok2, id = r.TrackFX_GetNamedConfigParm(tr, fx, "container_item." .. i)
      if ok2 and tonumber(id) then walk(tonumber(id)) end
    end
  end
  for fx = 0, r.TrackFX_GetCount(tr) - 1 do walk(fx) end
  for fx = 0, r.TrackFX_GetRecCount(tr) - 1 do walk(0x1000000 + fx) end   -- input FX (the master's: monitoring)
  return n
end
local function close_all_floats()
  local n = close_track_floats(r.GetMasterTrack(0))
  for i = 0, r.CountTracks(0) - 1 do n = n + close_track_floats(r.GetTrack(0, i)) end
  for i = 0, r.CountMediaItems(0) - 1 do                -- take FX
    local it = r.GetMediaItem(0, i)
    for t = 0, r.CountTakes(it) - 1 do
      local tk = r.GetTake(it, t)
      for fx = 0, (tk and r.TakeFX_GetCount(tk) or 0) - 1 do
        local fw = r.TakeFX_GetFloatingWindow(tk, fx)
        if fw and r.JS_Window_IsVisible(fw) then r.TakeFX_Show(tk, fx, 2); n = n + 1 end
      end
    end
  end
  return n
end
local function close_floats(which)
  local n = which == "all" and close_all_floats() or close_track_floats(shown_track() or r.GetSelectedTrack2(0, 0, true))
  r.SetExtState(EXT, "closed", tostring(n), false)
  dbg("close floats (" .. which .. "): " .. n)
end
-- The gear: the options (gfx.showmenu; "!" = on). A FLAT menu, no separators and no submenu, so the number the menu
-- returns is the item's position and nothing else (how separators count is not documented). Tests: gear_req = that
-- number.
local PICK                              -- the track icon picker: its own file, loaded after the menu below
local function gear_pick(pick)
  if pick == 1 then opt_set("trackno", opt.trackno == "1" and "0" or "1")
  elseif pick == 2 then opt_set("color", "0")
  elseif pick == 3 then opt_set("color", "stripe")
  elseif pick == 4 then opt_set("color", "band")
  elseif pick == 5 then opt_set("icon", opt.icon == "1" and "0" or "1")
  elseif pick == 6 then opt_set("labels", opt.labels == "long" and "short" or "long")
  elseif pick == 7 then opt_set("dblclick", opt.dblclick == "1" and "0" or "1")
  elseif pick == 8 then opt_set("fold", opt.fold == "1" and "0" or "1"); fold_open = true
  elseif pick == 9 then opt_set("fold_color", opt.fold_color == "1" and "0" or "1")
  elseif pick == 10 then PICK.open()
  elseif pick == 11 then opt_set("tint", opt.tint == "1" and "0" or "1"); TINT.pass(true)
  elseif pick >= 12 and pick <= 14 then                           -- the icon colour's strength (TINT.soft)
    opt_set("tintk", ({ "30", "50", "100" })[pick - 11]); if opt.tint == "1" then TINT.pass(true) end
  elseif pick >= 15 and pick <= 17 then opt_set("layout", ({ "auto", "across", "down" })[pick - 14])
  elseif pick == 18 then opt_set("tips", opt.tips == "0" and "1" or "0") end
  has_key = ""
end
-- The EON palette (EON Floatter's P; the Swing FX picker's slate): 0xRRGGBBAA
local MENU = { on = false, ImGui = nil, ctx = nil, font = nil, font_b = nil, x = 0, y = 0, armed = false }   -- the gear's menu; .c its palette
MENU.c = { bg = 0x1C2732FF, line = 0x34465AFF, text = 0xDBE3EAFF, muted = 0x8B95A1FF, dim = 0x5B6773FF, accent = 0xD67024FF }
MENU.blue = 0x3A86D0FF
function MENU.rgba(cr, cg, cb) return (math.floor(cr * 255 + 0.5) << 24) | (math.floor(cg * 255 + 0.5) << 16) | (math.floor(cb * 255 + 0.5) << 8) | 0xFF end
function MENU.alpha(col, a) return (col & 0xFFFFFF00) | a end
function MENU.imgui()
  if MENU.ImGui then return MENU.ImGui end
  if not r.ImGui_GetBuiltinPath then return nil end
  package.path = r.ImGui_GetBuiltinPath() .. "/?.lua;" .. package.path
  local ok, mod = pcall(function() return require("imgui")("0.10") end)
  if not ok or type(mod) ~= "table" then return nil end
  MENU.ImGui = mod
  return mod
end
-- ReaImGui lays its windows out in LOGICAL screen units: on a monitor scaled s (150 % = 1.5) the unit (x, y) stands at
-- physical origin + (x - origin) * s, origin being that monitor's top-left, and sizes are scaled the same, fonts
-- with them (measured 2026-10-06 on the user's 3440 x 1440 at 150 %: the picker asked for 3000,200 640 x 520 stood
-- at 3540,387 960 x 780 with GetWindowDpiScale 1.5, and looked right; the gear menu asked for at the dock's physical
-- 4910 opened at 6405, off the screen). REAPER's own calls (JS_Window_*, ClientToScreen, gfx) speak physical pixels.
-- So a physical point is converted before it goes to SetNextWindowPos, with the scale of the monitor it is on: the
-- dock's own (gfx.ext_retina, sc) for the menu, the palette and a fresh picker, which open at the bar; a remembered
-- picker place is saved physical with the scale it was seen at and corrected on its first frames when that monitor
-- is scaled otherwise now. Sizes inside ImGui are logical and NOT multiplied by sc (ReaImGui scales them).
-- DPI is a global on purpose (the 200-local limit, see TINT).
DPI = {}
function DPI.origin(px, py)                                       -- the monitor under a physical point: its top-left
  local vl, vt = r.JS_Window_GetViewportFromRect(px, py, px + 1, py + 1, false)
  return vl or 0, vt or 0
end
function DPI.to_logical(px, py, s)
  local ox, oy = DPI.origin(px, py)
  return ox + (px - ox) / s, oy + (py - oy) / s
end
-- A window placed with the DOCK's scale can land on a monitor scaled otherwise (a dock across two monitors; outside
-- audit 2026-10-07: the menu 376 px off the bottom of a 150 % screen). Once it is up, the scale of the monitor it
-- really stands on is read and it is placed again from its physical anchor, kept on that monitor. Only in its first
-- frames: later the user's own moves stand. o = { px, py, lw, lh (its logical size), used (the scale it was placed
-- with) }; returns true when o.x, o.y were set anew.
function DPI.settle(o, ImGui, ctx)
  o.n = (o.n or 0) + 1
  if o.n > 6 or not (ImGui.GetWindowDpiScale and r.JS_Window_GetViewportFromRect) then return false end
  local real = ImGui.GetWindowDpiScale(ctx)
  if not real or real <= 0 or math.abs(real - (o.used or real)) <= 0.01 then return false end
  o.used = real
  local sx, sy = o.px, o.py
  local vl, vt, vr, vb = r.JS_Window_GetViewportFromRect(sx, sy, sx + 1, sy + 1, true)
  if vr and sx + o.lw * real > vr then sx = vr - math.floor(o.lw * real) end
  if vb and sy + o.lh * real > vb then sy = vb - math.floor(o.lh * real) end
  if vl and sx < vl then sx = vl end
  if vt and sy < vt then sy = vt end
  o.x, o.y = DPI.to_logical(sx, sy, real)
  dbg("placed again for a screen scaled " .. real .. " at " .. sx .. "," .. sy)
  return true
end
-- A press of the left button ANYWHERE on the screen outside this ImGui window (call between its Begin and End). ImGui
-- hears no click on REAPER's own windows, so its IsMouseClicked never fired there and the palette and the gear menu
-- stayed open over the track area (the user, 2026-10-07: "the color menu dont wanna close easy"; colp_close_run.py:
-- seven real clicks, none closed it). The button is read for the whole screen (js_ReaScriptAPI) and the pointer is
-- compared, in screen pixels, with the window's corners. o.gdown starts true at the open, so the opening click (still
-- down) is no press.
function DPI.outside_press(o, ImGui, ctx)
  if not r.JS_Mouse_GetState then return false end
  local down = (r.JS_Mouse_GetState(1) & 1) == 1
  local press = down and not o.gdown
  o.gdown = down
  if not press then return false end
  local wx, wy = ImGui.GetWindowPos(ctx)
  local ww, wh = ImGui.GetWindowSize(ctx)
  local ok0, x0, y0 = pcall(ImGui.PointConvertNative, ctx, wx, wy, true)
  local ok1, x1, y1 = pcall(ImGui.PointConvertNative, ctx, wx + ww, wy + wh, true)
  if ok0 and ok1 and x0 and x1 then
    local mx, my = r.GetMousePosition()
    return not (mx >= math.min(x0, x1) and mx < math.max(x0, x1) and my >= math.min(y0, y1) and my < math.max(y0, y1))
  end
  local ix, iy = ImGui.GetMousePos(ctx)                           -- no conversion: ImGui's own idea of the pointer
  return not (ix >= wx and ix < wx + ww and iy >= wy and iy < wy + wh)
end
function MENU.open(sx, sy)
  local ImGui = MENU.imgui()
  if not ImGui then return false end
  MENU.ctx = ImGui.CreateContext("ReaKit FX Dock menu")
  local okf, f = pcall(ImGui.CreateFont, "sans-serif", 0)                      -- ReaImGui 0.10: the size at PushFont
  MENU.font = okf and f or nil
  local okb, fb = pcall(ImGui.CreateFont, "sans-serif", ImGui.FontFlags_Bold)
  MENU.font_b = okb and fb or nil
  if MENU.font then pcall(ImGui.Attach, MENU.ctx, MENU.font) end
  if MENU.font_b then pcall(ImGui.Attach, MENU.ctx, MENU.font_b) end
  -- kept on the screen: a dock at the bottom would hang the menu off it; then it opens above the bar instead
  if r.JS_Window_GetViewportFromRect then
    local vl, vt, vr, vb = r.JS_Window_GetViewportFromRect(sx, sy, sx + 1, sy + 1, true)   -- four numbers, no flag
    local mh, mw = math.floor(374 * sc), math.floor(310 * sc)   -- the menu's size, physical here: 306 x 374 logical
                                                                -- (menu_width_run.py, 2026-10-07, once it stopped
                                                                -- growing; the 396 measured 2026-10-06 was already
                                                                -- grown), + a few px
    if vb and sy + mh > vb then sy = sy - bar_h() - mh end
    if vr and sx + mw > vr then sx = vr - mw end
    if vl and sx < vl then sx = vl end
  end
  local lx, ly = DPI.to_logical(sx, sy, sc)
  MENU.on, MENU.x, MENU.y, MENU.armed, MENU.closing, MENU.frames, MENU.gdown = true, lx, ly, false, false, 0, true
  MENU.dp = { px = sx, py = sy, lw = 310, lh = 374, used = sc }   -- placed again if its screen is scaled otherwise
  dbg("menu: open at " .. sx .. "," .. sy .. " (ImGui " .. math.floor(lx) .. "," .. math.floor(ly) .. ", scale " .. sc .. ")")
  return true
end
function MENU.close()
  MENU.on, MENU.ctx = false, nil              -- the context is dropped: ReaImGui frees one that gets no more frames
  MENU.shut_t = r.time_precise()              -- see the gear's click: the press that shut it does not open it again
  MENU.rows_pub = nil; r.SetExtState(EXT, "menu_rows", "", false)
end

-- ── the track icon picker: its own file ───────────────────────────────────────────────────────────
-- "ReaKit FX - Dock icon picker.lua" beside this script (2026-10-12; the user: "i absolutely want the icon picker to
-- be its own file"), loaded once here with what it takes from the dock by name. It returns PICK (its state and the
-- calls the dock makes: open / close / frame / scan / set / key / load_state / add_dir / save_fav / save_groups) and
-- sets the global TINT. ReaPack ships it as a source of the GainKit Plus package; it is not an action. A missing or
-- broken file stops the dock here, with the file's own error (never a half-working dock without its picker).
PICK = assert(loadfile(DIR .. "ReaKit FX - Dock icon picker.lua"))({
  r = r, EXT = EXT, MENU = MENU, opt = opt, opt_set = opt_set, ticon = ticon, bar_h = bar_h, dbg = dbg,
  shown_track = shown_track, track_color = track_color, track_name = track_name,
  sc = function() return sc end, dock = function() return dock end,   -- live: the display scale, the dock's window
})

-- One frame of the open menu (every tick while it is open). Three groups, each in its own hue (the user,
-- 2026-10-05: "everything in our menu is one color basically"): TRACK in the track's own colour, CHIPS in EON
-- orange (the chips' lit colour on the bar), BAR in Floatter's blue. A stripe in the track's colour along the top,
-- as the bar wears. A row: a dot (filled in the hue when on, a hollow ring when off), a small glyph, the label; a
-- hovered row glows in its hue. The colour row's pills preview themselves (a line for Stripe, a block for Band);
-- the names row shows a long and a short chip. A pick closes it, as does Escape or a click outside it.
local function menu_frame()
  local ImGui, ctx = MENU.ImGui, MENU.ctx
  if not (ImGui and ctx) then MENU.on = false; return end
  local has, cr, cg, cb = track_color(shown_track())
  local hue_t = has and MENU.rgba(cr, cg, cb) or MENU.c.muted          -- TRACK: the track's colour (its grey when none)
  local hue_c, hue_b = MENU.c.accent, MENU.blue                     -- CHIPS: EON orange; BAR: Floatter's blue
  ImGui.SetNextWindowPos(ctx, MENU.x, MENU.y)
  ImGui.SetNextWindowFocus(ctx)
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, MENU.c.bg)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, MENU.c.line)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, MENU.c.text)
  ImGui.PushStyleColor(ctx, ImGui.Col_Separator, 0x283644FF)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 5)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, 1)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 10, 9)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 6, 3)
  local flags = ImGui.WindowFlags_NoTitleBar | ImGui.WindowFlags_NoResize | ImGui.WindowFlags_NoMove
    | ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoDocking
    | ImGui.WindowFlags_NoSavedSettings | ImGui.WindowFlags_TopMost
  if MENU.font then ImGui.PushFont(ctx, MENU.font, 13) end
  local visible = ImGui.Begin(ctx, "##rkdock_menu", nil, flags)
  local picked = false
  if visible then
    if MENU.dp and DPI.settle(MENU.dp, ImGui, ctx) then MENU.x, MENU.y = MENU.dp.x, MENU.dp.y end
    local dl = ImGui.GetWindowDrawList(ctx)
    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww = ImGui.GetWindowSize(ctx)
    ImGui.DrawList_AddRectFilled(dl, wx, wy, wx + ww, wy + 3, hue_t, 5, ImGui.DrawFlags_RoundCornersTop)   -- the stripe
    local ROW_W, lh = 272, ImGui.GetTextLineHeight(ctx)
    -- a cross in the top-right corner closes it. Drawn and hit-tested by hand, NOT an ImGui item: the window sizes
    -- itself to its items (AlwaysAutoResize), and an item placed from the window's own width pushed that width out
    -- by 4 px every frame, for ever (the user, 2026-10-07: "the gear menu opens in this slow weird way and always
    -- opens too wide"; menu_width_run.py measured 334 px wide at 10 frames, 774 at 120)
    do
      local cx, cy = wx + ww - 18, wy + 8
      local hot = ImGui.IsMouseHoveringRect(ctx, cx - 4, cy - 2, cx + 12, cy + 12)
      local col = hot and MENU.c.text or MENU.c.dim
      ImGui.DrawList_AddLine(dl, cx, cy, cx + 8, cy + 8, col, 1.5); ImGui.DrawList_AddLine(dl, cx, cy + 8, cx + 8, cy, col, 1.5)
      if hot and ImGui.IsMouseClicked(ctx, 0) then MENU.closing = true end
    end
    local function heading(t, hue)
      if MENU.font_b then ImGui.PushFont(ctx, MENU.font_b, 11) end
      ImGui.TextColored(ctx, hue, t)
      if MENU.font_b then ImGui.PopFont(ctx) end
    end
    -- the small glyphs, drawn with lines at (gx, gy): the row's left, its middle line
    local function glyph(kind, gx, gy)
      local c = MENU.c.muted
      if kind == "number" then ImGui.DrawList_AddText(dl, gx + 2, gy - lh * 0.5, c, "#")
      elseif kind == "icon" then
        ImGui.DrawList_AddRect(dl, gx, gy - 5, gx + 12, gy + 5, c, 1, 0, 1)
        ImGui.DrawList_AddCircleFilled(dl, gx + 4, gy - 1, 1.5, c)
        ImGui.DrawList_AddLine(dl, gx + 2, gy + 4, gx + 6, gy, c, 1); ImGui.DrawList_AddLine(dl, gx + 6, gy, gx + 10, gy + 4, c, 1)
      elseif kind == "names" then ImGui.DrawList_AddText(dl, gx, gy - lh * 0.5, c, "Aa")
      elseif kind == "pop" then
        ImGui.DrawList_AddRect(dl, gx, gy - 3, gx + 9, gy + 6, c, 1, 0, 1)
        ImGui.DrawList_AddLine(dl, gx + 5, gy + 1, gx + 12, gy - 6, c, 1.5)
        ImGui.DrawList_AddLine(dl, gx + 8, gy - 6, gx + 12, gy - 6, c, 1.5); ImGui.DrawList_AddLine(dl, gx + 12, gy - 6, gx + 12, gy - 2, c, 1.5)
      elseif kind == "fold" then
        ImGui.DrawList_AddLine(dl, gx + 1, gy + 3, gx + 6, gy - 2, c, 1.5); ImGui.DrawList_AddLine(dl, gx + 6, gy - 2, gx + 11, gy + 3, c, 1.5)
      elseif kind == "handle" then ImGui.DrawList_AddRectFilled(dl, gx, gy - 1, gx + 12, gy + 2, c, 1)
      elseif kind == "stay" then
        ImGui.DrawList_AddRect(dl, gx, gy - 5, gx + 12, gy + 5, c, 1, 0, 1)
        ImGui.DrawList_AddLine(dl, gx + 3, gy - 1, gx + 9, gy - 1, c, 1); ImGui.DrawList_AddLine(dl, gx + 3, gy + 2, gx + 9, gy + 2, c, 1)
      elseif kind == "tips" then                                   -- a speech bubble: the tooltips
        ImGui.DrawList_AddRect(dl, gx, gy - 5, gx + 12, gy + 3, c, 2, 0, 1)
        ImGui.DrawList_AddLine(dl, gx + 3, gy + 3, gx + 2, gy + 6, c, 1); ImGui.DrawList_AddLine(dl, gx + 2, gy + 6, gx + 6, gy + 3, c, 1)
      elseif kind == "pick" then                                   -- a small grid: the picker
        for i = 0, 1 do for j = 0, 1 do ImGui.DrawList_AddRectFilled(dl, gx + i * 7, gy - 5 + j * 7, gx + i * 7 + 5, gy + j * 7, c, 1) end end
      end
    end
    local rows_pub = {}                                  -- for tests: each row's screen box (ExtState menu_rows)
    local function row(label, on, act, hue, kind, extra)
      local x, y = ImGui.GetCursorScreenPos(ctx)
      rows_pub[#rows_pub + 1] = string.format("%s:%d,%d,%d,%d", label, math.floor(x), math.floor(y), ROW_W, math.floor(lh))
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, MENU.alpha(hue, 0x2A))
      ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, MENU.alpha(hue, 0x40))
      if ImGui.Selectable(ctx, "##" .. label, false, ImGui.SelectableFlags_None, ROW_W, 0) then act(); picked = true end
      ImGui.PopStyleColor(ctx, 2)
      ImGui.DrawList_AddText(dl, x + 42, y, MENU.c.text, label)   -- the label past the dot and the glyph
      local cy = y + lh * 0.5
      if on then
        ImGui.DrawList_AddCircleFilled(dl, x + 8, cy, 4, hue)
        ImGui.DrawList_AddCircle(dl, x + 8, cy, 6.5, hue, 0, 1)
      elseif on == false then
        ImGui.DrawList_AddCircle(dl, x + 8, cy, 4.5, MENU.c.dim, 0, 1.5)
      else                                                        -- nil: an action, not a switch
        ImGui.DrawList_AddText(dl, x + 5, y, MENU.c.dim, "\u{203A}")
      end
      glyph(kind, x + 22, cy)
      if extra then extra(x, y) end
    end
    local function chip_preview(x, y)                     -- the names row: a long chip and a short one
      local cy = y + lh * 0.5
      local function chip(cx, text, w)
        ImGui.DrawList_AddRectFilled(dl, cx, cy - 7, cx + w, cy + 7, hue_c, 2)
        if MENU.font_b then ImGui.DrawList_AddTextEx(dl, MENU.font_b, 9, cx + 4, cy - 5.5, 0x141415FF, text)
        else ImGui.DrawList_AddText(dl, cx + 4, cy - 6, 0x141415FF, text) end
      end
      chip(x + ROW_W - 78, "GAINKIT", 46)
      ImGui.DrawList_AddText(dl, x + ROW_W - 29, cy - lh * 0.5, MENU.c.dim, "vs")
      chip(x + ROW_W - 14, "GK", 20)
    end
    -- the colour pills: drawn by hand so each previews its own look
    local function pill(id, text, cur_on, w, draw_preview)
      local x, y = ImGui.GetCursorScreenPos(ctx)
      local h = lh + 4
      rows_pub[#rows_pub + 1] = string.format("colour %s:%d,%d,%d,%d", text, math.floor(x), math.floor(y), w, math.floor(h))
      ImGui.InvisibleButton(ctx, id, w, h)
      local hov = ImGui.IsItemHovered(ctx)
      local bg = cur_on and hue_t or (hov and 0x34465AFF or 0x283644FF)
      local fg = cur_on and 0x14191EFF or (text == "Off" and MENU.c.muted or MENU.c.text)
      ImGui.DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, h * 0.5)
      local tx = x + 9
      if draw_preview then tx = tx + draw_preview(x + 9, y + h * 0.5, cur_on) + 5 end
      ImGui.DrawList_AddText(dl, tx, y + 2, fg, text)
      if ImGui.IsItemClicked(ctx, 0) then return true end
      return false
    end
    local function prev_stripe(px, py, lit)
      ImGui.DrawList_AddRectFilled(dl, px, py - 1.5, px + 16, py + 1.5, lit and 0x14191EFF or hue_t); return 16
    end
    local function prev_band(px, py, lit)
      ImGui.DrawList_AddRectFilled(dl, px, py - 4.5, px + 16, py + 4.5, lit and 0x14191EFF or hue_t, 2); return 16
    end

    heading("TRACK", hue_t)
    row("Track number", opt.trackno == "1", function() opt_set("trackno", opt.trackno == "1" and "0" or "1") end, hue_t, "number")
    row("Track icon", opt.icon == "1", function() opt_set("icon", opt.icon == "1" and "0" or "1") end, hue_t, "icon")
    row("Pick a track icon...", nil, function() PICK.open(); MENU.closing = true end, hue_t, "pick")
    row("Icons follow the track colour", opt.tint == "1", function() opt_set("tint", opt.tint == "1" and "0" or "1"); TINT.pass(true) end, hue_t, "tint")
    ImGui.Dummy(ctx, 0, 1)
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextColored(ctx, MENU.c.muted, "    Track colour"); ImGui.SameLine(ctx, 0, 8)
    if pill("##col_off", "Off", opt.color == "0", 38, nil) then opt_set("color", "0"); picked = true end
    ImGui.SameLine(ctx, 0, 4)
    if pill("##col_stripe", "Stripe", opt.color == "stripe", 76, prev_stripe) then opt_set("color", "stripe"); picked = true end
    ImGui.SameLine(ctx, 0, 4)
    if pill("##col_band", "Band", opt.color == "band", 68, prev_band) then opt_set("color", "band"); picked = true end
    -- (the icon colour's strength slider lives in the track icon picker: PICK's Colour slider)
    ImGui.Dummy(ctx, 0, 2)
    ImGui.Separator(ctx)
    ImGui.Dummy(ctx, 0, 1)
    heading("CHIPS", hue_c)
    row("Full effect names", opt.labels == "long", function() opt_set("labels", opt.labels == "long" and "short" or "long") end, hue_c, "names", chip_preview)
    row("Double-click pops an effect out", opt.dblclick == "1", function() opt_set("dblclick", opt.dblclick == "1" and "0" or "1") end, hue_c, "pop")
    ImGui.Dummy(ctx, 0, 2)
    ImGui.Separator(ctx)
    ImGui.Dummy(ctx, 0, 1)
    heading("BAR", hue_b)
    ImGui.AlignTextToFramePadding(ctx)                       -- the effects' layout: auto (a window taller than wide
    ImGui.TextColored(ctx, MENU.c.muted, "    Layout"); ImGui.SameLine(ctx, 0, 30)   -- stacks them), across, down
    if pill("##lay_auto", "Auto", opt.layout == "auto", 48, nil) then opt_set("layout", "auto"); picked = true end
    ImGui.SameLine(ctx, 0, 4)
    if pill("##lay_across", "Across", opt.layout == "across", 62, nil) then opt_set("layout", "across"); picked = true end
    ImGui.SameLine(ctx, 0, 4)
    if pill("##lay_down", "Down", opt.layout == "down", 54, nil) then opt_set("layout", "down"); picked = true end
    ImGui.Dummy(ctx, 0, 2)
    row("Fold the bar to a handle", opt.fold == "1", function() opt_set("fold", opt.fold == "1" and "0" or "1"); fold_open = true end, hue_b, "fold")
    row("Track colour on the folded handle", opt.fold_color == "1", function() opt_set("fold_color", opt.fold_color == "1" and "0" or "1") end, hue_b, "handle")
    row("Menu stays open until closed", opt.menu_stay == "1", function() opt_set("menu_stay", opt.menu_stay == "1" and "0" or "1") end, hue_b, "stay")
    row("Tooltips", opt.tips ~= "0", function() opt_set("tips", opt.tips == "0" and "1" or "0") end, hue_b, "tips")
    local rp = table.concat(rows_pub, ";")
    if rp ~= MENU.rows_pub then MENU.rows_pub = rp; r.SetExtState(EXT, "menu_rows", rp, false) end
    -- a click anywhere else, or Escape, closes it (the first frame is skipped: the opening click is still down)
    -- a pick closes it unless the menu stays open; a click anywhere else, Escape or the cross always close it (the
    -- first frame is skipped: the opening click is still down)
    -- "outside" by the window's own rectangle, not by ImGui's hover (which reads false while REAPER is not the
    -- foreground window: the first click then closed the menu and picked nothing; measured 2026-10-05)
    local mxs, mys = ImGui.GetMousePos(ctx)
    local wh = select(2, ImGui.GetWindowSize(ctx))
    MENU.frames = (MENU.frames or 0) + 1
    if MENU.frames == 3 then dbg(string.format("menu frame 3: ImGui pos %d,%d size %dx%d, dpi scale %s", wx, wy, ww, wh, tostring(ImGui.GetWindowDpiScale and ImGui.GetWindowDpiScale(ctx)))) end
    local inside = mxs >= wx and mxs < wx + ww and mys >= wy and mys < wy + wh
    if MENU.armed and ImGui.IsMouseClicked(ctx, 0) and not inside then MENU.closing = true end
    if DPI.outside_press(MENU, ImGui, ctx) then MENU.closing = true end   -- a click on REAPER's own windows too
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then MENU.closing = true end
    if not ImGui.IsMouseDown(ctx, 0) then MENU.armed = true end
    ImGui.End(ctx)                                       -- only after a true Begin (ReaImGui ends a hidden window itself)
  end
  if MENU.font then ImGui.PopFont(ctx) end
  ImGui.PopStyleVar(ctx, 4)
  ImGui.PopStyleColor(ctx, 4)
  if picked then has_key = "" end
  if MENU.closing or (picked and opt.menu_stay ~= "1") then MENU.closing = false; MENU.close() end
end
local function gear_menu(mx, my)
  -- the gear's row, in screen coordinates: the menu hangs under the bar at the gear's x
  local sx, sy = r.JS_Window_ClientToScreen(dock, mx - math.floor(60 * sc), bar_h())
  if MENU.open(sx, sy) then return end
  -- no ReaImGui: REAPER's own menu, flat
  local function on(b) return b and "!" or "" end
  local m = on(opt.trackno == "1") .. "Track number|"
    .. on(opt.color == "0") .. "Track colour: off|"
    .. on(opt.color == "stripe") .. "Track colour: a stripe along the top|"
    .. on(opt.color == "band") .. "Track colour: a band across the bar|"
    .. on(opt.icon == "1") .. "Track icon|"
    .. on(opt.labels == "long") .. "Full effect names|"
    .. on(opt.dblclick == "1") .. "Double-click pops an effect out|"
    .. on(opt.fold == "1") .. "Fold the bar to a handle|"
    .. on(opt.fold_color == "1") .. "Track colour on the folded handle|"
    .. "Pick a track icon...|"
    .. on(opt.tint == "1") .. "Icons follow the track colour|"
    .. on(TINT.pct() == 30) .. "Icon colour: light (30 %)|"             -- no slider in REAPER's menu: three of its values
    .. on(TINT.pct() == 50) .. "Icon colour: medium (50 %)|"
    .. on(TINT.pct() == 100) .. "Icon colour: full (100 %)|"
    .. on(opt.layout == "auto") .. "Layout: automatic (down when taller than wide)|"
    .. on(opt.layout == "across") .. "Layout: effects side by side|"
    .. on(opt.layout == "down") .. "Layout: effects stacked down|"
    .. on(opt.tips ~= "0") .. "Tooltips"
  gfx.x, gfx.y = mx, my
  local pick = gfx.showmenu(m)
  if pick and pick > 0 then gear_pick(pick) end
end

-- ── The track colour palette and the bar's right-click menus (the user, 2026-10-06: "a way to recolor the track
-- quickly, and we dont have any right click menu options") ─────────────────────────────────────────────────────
-- COLP and RMENU are GLOBAL tables on purpose: the main chunk sits at Lua's 200-local limit (see TINT).
-- The palette: a click on the track number (drawn as a small swatch in the track's colour) or "Track colour..." in
-- the track's right-click menu opens 16 colours, None and "More..." (REAPER's colour dialog). It colours the shown
-- track, or every selected track when the shown one is among them (REAPER's own rule), in one undo step; the icon
-- colour follow repaints from there. A click outside or Escape closes it. Tests: colp_req = "open" | "close" |
-- "<n>" (1..16) | "none"; published colp ("1" open).
COLP = { on = false, ctx = nil, x = 0, y = 0, armed = false, closing = false, ask = false,
  cols = { { 220, 60, 50 }, { 235, 135, 40 }, { 240, 190, 50 }, { 225, 220, 70 }, { 150, 210, 60 }, { 70, 180, 90 },
           { 40, 170, 150 }, { 50, 180, 220 }, { 60, 120, 230 }, { 95, 95, 215 }, { 150, 90, 220 }, { 210, 80, 200 },
           { 235, 120, 160 }, { 150, 100, 60 }, { 130, 135, 140 }, { 215, 215, 215 } } }
function COLP.targets()
  local tr = shown_track()
  if not tr then return {} end
  if r.IsTrackSelected(tr) and r.CountSelectedTracks2(0, false) > 1 then
    local t = {}
    for i = 0, r.CountSelectedTracks2(0, false) - 1 do t[#t + 1] = r.GetSelectedTrack2(0, i, false) end
    return t
  end
  return { tr }
end
function COLP.set(native)                                         -- native = REAPER's colour | 0x1000000, or 0 = none
  local trs = COLP.targets()
  if #trs == 0 then return end
  r.Undo_BeginBlock()
  for _, tr in ipairs(trs) do r.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", native) end
  r.Undo_EndBlock(native == 0 and "ReaKit FX dock: track colour removed" or "ReaKit FX dock: track colour", -1)
  r.TrackList_AdjustWindows(false); r.UpdateArrange()
  tcol.t = 0                                                      -- the bar reads the colour again at once
  if opt.tint == "1" then TINT.pass(true) end
  dbg("colour " .. string.format("%x", native) .. " on " .. #trs .. " track(s)")
end
function COLP.open(sx, sy)
  local ImGui = MENU.imgui()
  if not ImGui then COLP.ask = true; return end                   -- no ReaImGui: REAPER's colour dialog straight away
  COLP.ctx = ImGui.CreateContext("ReaKit FX Dock colours")
  if r.JS_Window_GetViewportFromRect then                         -- kept on the screen (about 230 x 110)
    local vl, vt, vr, vb = r.JS_Window_GetViewportFromRect(sx, sy, sx + 1, sy + 1, true)
    if vr and sx + 230 * sc > vr then sx = vr - math.floor(230 * sc) end
    if vb and sy + 110 * sc > vb then sy = sy - bar_h() - math.floor(110 * sc) end
    if vl and sx < vl then sx = vl end
  end
  local lx, ly = DPI.to_logical(sx, sy, sc)
  COLP.on, COLP.x, COLP.y, COLP.armed, COLP.closing, COLP.gdown = true, lx, ly, false, false, true
  COLP.dp = { px = sx, py = sy, lw = 230, lh = 110, used = sc }   -- placed again if its screen is scaled otherwise
  local tr = shown_track()                                        -- the track it was opened for: when the dock
  COLP.for_guid = tr and r.GetTrackGUID(tr) or ""                -- follows another one, the palette closes (outside
end                                                               -- audit 2026-10-07: a swatch coloured the new track)
function COLP.close() COLP.on, COLP.ctx, COLP.shut_t = false, nil, r.time_precise() end   -- shut_t: see the swatch's click
function COLP.frame()
  local ImGui, ctx = MENU.ImGui, COLP.ctx
  if not (ImGui and ctx) then COLP.on = false; return end
  local now_tr = shown_track()                                    -- the dock moved on to another track: closed
  if (now_tr and r.GetTrackGUID(now_tr) or "") ~= (COLP.for_guid or "") then COLP.close(); return end
  ImGui.SetNextWindowPos(ctx, COLP.x, COLP.y)
  ImGui.SetNextWindowFocus(ctx)
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, MENU.c.bg)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, MENU.c.line)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, MENU.c.text)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x283644FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x34465AFF)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 5)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 8, 8)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 4, 4)
  local flags = ImGui.WindowFlags_NoTitleBar | ImGui.WindowFlags_NoResize | ImGui.WindowFlags_NoMove
    | ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoDocking
    | ImGui.WindowFlags_NoSavedSettings | ImGui.WindowFlags_TopMost
  local visible = ImGui.Begin(ctx, "##rkdock_colours", nil, flags)
  local picked = false
  if visible then
    if COLP.dp and DPI.settle(COLP.dp, ImGui, ctx) then COLP.x, COLP.y = COLP.dp.x, COLP.dp.y end
    local has, cr, cg, cb = track_color(shown_track())
    local cur = has and string.format("%d,%d,%d", math.floor(cr * 255 + 0.5), math.floor(cg * 255 + 0.5), math.floor(cb * 255 + 0.5)) or ""
    local dl = ImGui.GetWindowDrawList(ctx)
    local sw = 22                                                   -- logical: ReaImGui scales it
    for i, c in ipairs(COLP.cols) do
      if (i - 1) % 8 ~= 0 then ImGui.SameLine(ctx) end
      local x0, y0 = ImGui.GetCursorScreenPos(ctx)
      if ImGui.InvisibleButton(ctx, "##c" .. i, sw, sw) then COLP.set(r.ColorToNative(c[1], c[2], c[3]) | 0x1000000); picked = true end
      local hov = ImGui.IsItemHovered(ctx)
      local rgba = (c[1] << 24) | (c[2] << 16) | (c[3] << 8) | 0xFF
      ImGui.DrawList_AddRectFilled(dl, x0, y0, x0 + sw, y0 + sw, rgba, 4)
      if hov or cur == string.format("%d,%d,%d", c[1], c[2], c[3]) then
        ImGui.DrawList_AddRect(dl, x0 - 1, y0 - 1, x0 + sw + 1, y0 + sw + 1, 0xF0F2F5FF, 4, 0, hov and 2 or 1.5)
      end
    end
    if ImGui.Button(ctx, "None") then COLP.set(0); picked = true end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, "More...") then COLP.ask = true; picked = true end
    local n = #COLP.targets()
    if n > 1 then ImGui.SameLine(ctx); ImGui.TextColored(ctx, MENU.c.muted, n .. " selected tracks") end
    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    local mxs, mys = ImGui.GetMousePos(ctx)
    local inside = mxs >= wx and mxs < wx + ww and mys >= wy and mys < wy + wh   -- by the rectangle (see the menu)
    if COLP.armed and ImGui.IsMouseClicked(ctx, 0) and not inside then COLP.closing = true end
    if DPI.outside_press(COLP, ImGui, ctx) then COLP.closing = true end   -- a click on REAPER's own windows too
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then COLP.closing = true end
    if not ImGui.IsMouseDown(ctx, 0) then COLP.armed = true end
    ImGui.End(ctx)
  end
  ImGui.PopStyleVar(ctx, 3)
  ImGui.PopStyleColor(ctx, 5)
  if picked or COLP.closing then COLP.close() end
end
function COLP.after()                                             -- REAPER's colour dialog, outside any ImGui frame
  if not COLP.ask then return end
  COLP.ask = false
  local tr = shown_track()
  if not tr then return end
  local ok, c = r.GR_SelectColor(r.GetMainHwnd())                -- (the dialog takes no starting colour)
  if ok == 1 and c then COLP.set((c & 0xFFFFFF) | 0x1000000) end
end

-- The right-click menus (REAPER's own menus, flat: no separators, so a pick's number is its row; see gear_pick).
RMENU = {}
function RMENU.track(mx, my, forced)       -- forced: the pick's number (tests), no menu shown
  local tr = shown_track()
  if not tr then return end
  local master = tr == r.GetMasterTrack(0)
  local _, icon = r.GetSetMediaTrackInfo_String(tr, "P_ICON", "", false)
  local function on(b) return b and "!" or "" end
  local function grey(b) return b and "" or "#" end
  local m = grey(not master) .. "Rename the track|"
    .. grey(not master) .. "Track colour...|"
    .. grey(not master and r.GetTrackColor(tr) ~= 0) .. "Remove the track colour|"
    .. grey(not master) .. "Pick a track icon...|"
    .. grey(not master and icon ~= "") .. "Remove the track icon|"
    .. on(opt.tint == "1") .. "Icons follow the track colour|"
    .. "Close this track's effect windows|"
    .. "Close every track's effect windows|"
    .. on(pin ~= "") .. "Keep the dock on this track (pin)"
  gfx.x, gfx.y = mx, my
  local pick = forced or gfx.showmenu(m)
  if pick == 1 then                                               -- the keyboard must be on the dock, or the field closes at once
    if r.JS_Window_SetFocus then r.JS_Window_SetFocus(dock) end
    name_edit_start(tr)
  elseif pick == 2 then local sx, sy = r.JS_Window_ClientToScreen(dock, mx, bar_h()); COLP.open(sx, sy)
  elseif pick == 3 then COLP.set(0)
  elseif pick == 4 then local ok, err = pcall(PICK.open); if not ok then dbg("picker open error: " .. tostring(err)); PICK.close() end
  elseif pick == 5 then
    r.Undo_BeginBlock(); r.GetSetMediaTrackInfo_String(tr, "P_ICON", "", true)
    if opt.tint == "1" then r.GetSetMediaTrackInfo_String(tr, TINT.key, "", true) end
    r.Undo_EndBlock("ReaKit FX dock: track icon removed", -1); ticon.t = 0; r.TrackList_AdjustWindows(false)
  elseif pick == 6 then opt_set("tint", opt.tint == "1" and "0" or "1"); TINT.pass(true)
  elseif pick == 7 then close_floats("track")
  elseif pick == 8 then close_floats("all")
  elseif pick == 9 then set_pin(pin == "") end
end
function RMENU.chip(c, mx, my, forced)
  local tr = shown_track()
  local fx = tr and c.fg and fx_by_guid(tr, c.fg)
  if not fx then return end
  local name = KINDS[c.kind].name
  local on = r.TrackFX_GetEnabled(tr, fx)
  local held
  for _, s in ipairs(slots) do if s.fg == c.fg then held = s end end
  local m = "Show " .. name .. " in the dock|"
    .. "Open " .. name .. " in its own window|"
    .. (on and "" or "!") .. "Bypass " .. name .. "|"
    .. (fx == 0 and "#" or "") .. "Move to the start of the chain|"
    .. (fx == r.TrackFX_GetCount(tr) - 1 and "#" or "") .. "Move to the end of the chain|"
    .. "Remove " .. name .. " from the track"
  gfx.x, gfx.y = mx, my
  local pick = forced or gfx.showmenu(m)
  if pick == 1 then show_copy(c.fg, c.kind)
  elseif pick == 2 then if held and held.canvas then pop_out(held) else r.TrackFX_Show(tr, fx, 3) end
  elseif pick == 3 then
    r.Undo_BeginBlock(); r.TrackFX_SetEnabled(tr, fx, not on)
    r.Undo_EndBlock("ReaKit FX dock: " .. (on and "bypass " or "enable ") .. name .. " on " .. track_name(tr), -1)
  elseif pick == 4 then move_fx(c.fg, r.TrackFX_GetFXGUID(tr, 0))
  elseif pick == 5 then move_fx(c.fg, nil)
  elseif pick == 6 then
    -- the undo step opens BEFORE its surface goes home: letting the float go adds REAPER's own "Close FX config"
    -- point, which then joins this step (as move_fx does; outside audit 2026-10-07: two undo points)
    r.Undo_BeginBlock()
    local cv = held and held.canvas
    if cv then
      release(held)                                               -- its surface home first, then the plugin goes
      -- a hand-back that could not happen (its window gone and not rebuilt) leaves the surface parented here;
      -- hidden, so a dead plugin's picture never stays in the dock
      if r.JS_Window_IsWindow(cv) and r.JS_Window_GetParent(cv) == dock then r.JS_Window_Show(cv, "HIDE") end
    end
    r.TrackFX_Delete(tr, fx)
    r.Undo_EndBlock("ReaKit FX dock: remove " .. name .. " from " .. track_name(tr), -1)
    dbg("removed " .. name .. " from " .. track_name(tr))
  end
end

local function bar_mouse()
  local cap = gfx.mouse_cap
  local down = (cap & 1) == 1 and (last_cap & 1) == 0
  local rdown = (cap & 2) == 2 and (last_cap & 2) == 0
  last_cap = cap
  local wheel = gfx.mouse_wheel
  gfx.mouse_wheel = 0
  local mx, my = gfx.mouse_x, gfx.mouse_y
  local in_bar = mx >= 0 and mx < gfx.w and my >= 0 and my < bar_h()
  local now = r.time_precise()
  -- what the pointer rests on (the tooltip, the hover light)
  local under = nil
  if in_bar then
    for _, h in ipairs(hits) do
      if mx >= h[1] and mx < h[2] and my >= h[3] and my < h[4] then under = h[5]; break end
    end
  end
  if under ~= hover_act then hover_act, hover_t = under, now end
  if drag then
    local c = bar_chips[drag.i]
    if not c or c.fg ~= drag.fg or c.kind ~= drag.kind then drag = nil; return end   -- the bar changed under it
    -- where the pointer is NOW, before a let-go acts: a flick out of the bar between two frames is let go off the
    -- bar, and a last move lands where it ends (it acted on the frame before's; Codex delta audit, 2026-10-05)
    if not drag.moved and (math.abs(mx - drag.x0) > 4 * sc or math.abs(my - drag.y0) > 4 * sc) then drag.moved = true end
    if drag.moved then
      drag.inside = mx >= 0 and mx < gfx.w and my >= -12 * sc and my < bar_h() + 12 * sc
      drag.before, drag.mark, drag.noop, drag.mrow = drop_at(mx, my)
    end
    if (cap & 1) == 0 then                               -- let go
      local d = drag
      drag = nil
      if not d.moved then
        if d.fg then show_copy(d.fg, d.kind) else set_kind(d.kind) end
      elseif d.inside and not d.noop and d.before ~= nil then
        if d.fg then move_fx(d.fg, d.before) else add_kind(d.kind, d.before) end
      end
      return
    end
    return
  end
  if wheel ~= 0 and in_bar then                          -- the wheel over SLOT steps the slot; elsewhere the strip's view
    if under == "slot" then
      local ok, err = pcall(SLOT.step, wheel > 0 and -1 or 1)
      if not ok then dbg("slot step error: " .. tostring(err)) end
    else scroll(wheel > 0 and -1 or 1) end
  end
  if not (down or rdown) or not in_bar then return end
  if NAME.on and under ~= "name" then name_edit_end(true) end     -- a click elsewhere on the bar sets the name
  if rdown and not under then RMENU.track(mx, my); return end   -- the bar's empty space: the track's menu
  for _, h in ipairs(hits) do
    if mx >= h[1] and mx < h[2] and my >= h[3] and my < h[4] then
      local a = h[5]
      local ci = a:sub(1, 4) == "chip" and tonumber(a:sub(5))
      local c = ci and bar_chips[ci]
      if c and c.other then return end                    -- a marker: only ever dropped beside
      if rdown then
        if c and not c.fg then add_kind(c.kind)          -- a dim one: GainKit first, the others at the end
        elseif c then RMENU.chip(c, mx, my)              -- a lit one: its menu
        elseif a == "name" or a == "ticon" or a == "num" then RMENU.track(mx, my)
        elseif a == "slot" then local ok, err = pcall(SLOT.menu, mx, my); if not ok then dbg("slot menu error: " .. tostring(err)) end end
      elseif c then
        drag = { i = ci, kind = c.kind, fg = c.fg, x0 = mx, y0 = my, dx = mx - c.x0 }
      elseif a == "closetrack" then close_floats("track")
      elseif a == "closeall" then close_floats("all")
      elseif a == "num" then                              -- a toggle: a click on the swatch while the palette is up
        if COLP.on or r.time_precise() - (COLP.shut_t or 0) < 0.3 then   -- (or that press just shut it) closes it
          COLP.close()
        else
          local sx, sy = r.JS_Window_ClientToScreen(dock, h[1], bar_h())
          COLP.open(sx, sy)
        end
      elseif a == "ticon" then
        local ok, err = pcall(PICK.open)
        if not ok then dbg("picker open error: " .. tostring(err)); PICK.close() end
      elseif a == "name" then
        if NAME.on then                                       -- a click in the field puts the caret there
          local fx0 = h[1] + math.floor(3 * sc)
          local best, bd = #NAME.text, math.huge
          for i = 0, #NAME.text do
            if i == 0 or utf8.offset(NAME.text, 0, i) == i then   -- at character boundaries only
              local d = math.abs(fx0 + gfx.measurestr(NAME.text:sub(1, i)) - mx)
              if d < bd then best, bd = i, d end
            end
          end
          NAME.cur = best
        else name_edit_start(shown_track()) end
      elseif a == "gear" then                            -- a toggle, as the swatch
        if MENU.on or r.time_precise() - (MENU.shut_t or 0) < 0.3 then MENU.close() else
          local ok, err = pcall(gear_menu, mx, my)       -- never the dock's end
          if not ok then dbg("menu open error: " .. tostring(err)); MENU.close() end
        end
      elseif a == "fold" then fold_open = false
      elseif a == "close" then want_close = true
      elseif a == "handle" then fold_open = true
      elseif a == "pin" then set_pin(pin == "")
      elseif a == "tabs" then set_tabs_hidden(not tabs_hidden())
      elseif a == "strip" then set_strip(not strip)
      elseif a == "slot" then                             -- never the dock's end: the mixer's windows are REAPER's
        local ok, err = pcall(SLOT.menu, mx, my)
        if not ok then dbg("slot menu error: " .. tostring(err)) end
      elseif a == "left" then scroll(-1)
      elseif a == "right" then scroll(1) end
      return
    end
  end
end

-- lines of text centred in a box, the first brighter; the short set when the long one will not fit
local function text_in(x, y, w, h, long, short)
  local fs = math.floor(15 * sc + 0.5)
  gfx.setfont(1, "Arial", fs)
  local room = w - 16 * sc
  local function widest(t)
    local m = 0
    for _, s in ipairs(t) do m = math.max(m, gfx.measurestr(s)) end
    return m
  end
  local lines = long
  if short and widest(long) > room then lines = short end
  while fs > 9 and widest(lines) > room do fs = fs - 1; gfx.setfont(1, "Arial", fs) end
  local lh, sp = gfx.texth, math.floor(6 * sc)
  local ty = y + (h - (#lines * lh + (#lines - 1) * sp)) / 2
  for i, s in ipairs(lines) do
    if i == 1 then gfx.set(0.85, 0.87, 0.90, 1) else gfx.set(0.60, 0.63, 0.68, 1) end
    gfx.x, gfx.y = x + math.max(8 * sc, (w - gfx.measurestr(s)) / 2), ty
    gfx.drawstr(s, 0, x + w, y + h)                     -- clipped to its box
    ty = ty + lh + sp
  end
end

-- the dock's own face under the bar: the lines between effects, and the words where one is not on view
local function draw_body()
  local b = bar_h()
  gfx.set(0.09, 0.09, 0.10, 1); gfx.rect(0, b, gfx.w, gfx.h - b, 1)   -- a held surface covers its own place
  if #slots == 0 then
    gfx.set(0.16, 0.17, 0.19, 1); gfx.rect(0, b, gfx.w, gfx.h - b, 1)
    local what = strip and "ReaKit FX" or KINDS[kind].name
    local l1, l2
    if note then
      l1 = note
      l2 = strip and "Right-click an effect above to add it here." or "Right-click its button above to add it here."
      if pin ~= "" then l2 = l2 .. " Or unpin." else l2 = l2 .. " Or select another track." end
    elseif not cur then
      l1, l2 = "Select a track with " .. what .. " on it.", "The dock shows " .. (strip and "them" or "it") .. ", and follows your selection."
    end
    if l1 then text_in(0, b, gfx.w, gfx.h - b, { l1, l2 }) end
    return
  end
  for _, s in ipairs(slots) do
    if not s.canvas then
      gfx.set(0.16, 0.17, 0.19, 1); gfx.rect(s.x, s.y, s.w, s.h, 1)
      if s.away then
        local nm = KINDS[s.kind].name
        text_in(s.x, s.y, s.w, s.h, { s.name .. ": " .. nm .. " is open in its own window.", "Close that window to bring it back here." },
                { nm .. " is open", "in its own window.", "Close it to bring", "it back here." })
      end
    end
  end
end

-- For the plugins: what the dock holds, in gmem band EON_RKFX_DRAWER (.refs/gmem_regions_supplement.tsv, the
-- bundle). A plugin with a drawer (Saturation's CURVE, rk_drawer.jsfx-inc) finds itself there and shows its own
-- pop-over at once, instead of asking EON Floatter for room a docked surface cannot get. +8 the heartbeat
-- (os.time, the clock a JSFX time() reads; 0 = closed), +9 how many, +16.. (track: 0-based, -1 = the master;
-- chain position) pairs, 64 at most, the count written last.
r.gmem_attach("Swing_Media_Transfer")
-- Several docks can be open (the full one and one-plugin tabs): each keeps its own pairs in its ExtState "drwl" and
-- writes the UNION of every open dock's into the band (the Codex review, 2026-11-04: each overwrote the others').
-- closing: this dock's own pairs are left out, and the heartbeat stops only when no other dock is open.
local function publish_drawer(closing)
  local t = {}
  for _, s in ipairs(closing and {} or slots) do
    if s.canvas and s.tr and s.fx and #t < C.DRW_MAX * 2 and r.ValidatePtr2(0, s.tr, "MediaTrack*") then
      local n = r.GetMediaTrackInfo_Value(s.tr, "IP_TRACKNUMBER")   -- 1-based, -1 = the master, 0 = not found
      if n ~= 0 then t[#t + 1] = n < 0 and -1 or n - 1; t[#t + 1] = s.fx end
    end
  end
  local own = table.concat(t, " ")
  if own ~= pub.own then pub.own = own; r.SetExtState(EXT, "drwl", own, false) end
  local now_p, any = r.time_precise(), not closing
  local function add(x)
    if x == EXT or now_p - (tonumber(r.GetExtState(x, "alive")) or 0) > 1.0 then return end
    any = true
    for a, b in r.GetExtState(x, "drwl"):gmatch("(%-?%d+) (%-?%d+)") do
      if #t < C.DRW_MAX * 2 then t[#t + 1] = tonumber(a); t[#t + 1] = tonumber(b) end
    end
  end
  add("EON_ReaKitDock")
  for _, k in ipairs(KINDS) do add("EON_ReaKitDock_" .. k.key) end
  local v = table.concat(t, " ")
  if v ~= pub.drw then
    pub.drw = v
    for i, x in ipairs(t) do r.gmem_write(C.DRW + 16 + i - 1, x) end
    r.gmem_write(C.DRW + 9, #t // 2)
  end
  local now = any and os.time() or 0
  if now ~= pub.beat then pub.beat = now; r.gmem_write(C.DRW + 8, now) end
end

-- for tests: what the dock holds, left to right ("track GUID|FX GUID", comma between), and the strip's view
local function publish()
  local t = {}
  for _, s in ipairs(slots) do if s.canvas then t[#t + 1] = s.tg .. "|" .. s.fg end end
  local v = table.concat(t, ",")
  if v ~= pub.held then pub.held = v; r.SetExtState(EXT, "held", v, false) end
  v = string.format("%d %d %d", first, #slots, cur and #cur.list or 0)   -- first on view, on view, on the track
  if v ~= pub.view then pub.view = v; r.SetExtState(EXT, "view", v, false) end
  local sl = {}                                                              -- the slots' places, for tests (layout)
  for _, s in ipairs(slots) do sl[#sl + 1] = string.format("%s:%d,%d,%d,%d", KINDS[s.kind].key, s.x or 0, s.y or 0, s.w or 0, s.h or 0) end
  v = (lay_down and "down " or "across ") .. table.concat(sl, ";")
  if v ~= pub_slots then pub_slots = v; r.SetExtState(EXT, "slots", v, false) end   -- (pub_slots a global: the 200-local limit)
  v = string.format("%d %d %d", bar_h(), folded() and 1 or 0, bar_rows)    -- the bar: height, folded, rows
  if v ~= pub.bar then pub.bar = v; r.SetExtState(EXT, "bar", v, false) end
  v = hover_act or ""                                                        -- what the pointer rests on
  if v ~= pub.hover then pub.hover = v; r.SetExtState(EXT, "hover", v, false) end
  v = MENU.on and "1" or "0"                                                 -- the gear's menu open
  if v ~= pub.menu then pub.menu = v; r.SetExtState(EXT, "menu", v, false) end
  v = PICK.on and "1" or "0"                                                 -- the icon picker open
  if v ~= pub.pick then pub.pick = v; r.SetExtState(EXT, "picker", v, false) end
  v = NAME.on and ("1 " .. NAME.text) or "0"                                 -- the name field
  if v ~= pub.name then pub.name = v; r.SetExtState(EXT, "name_edit", v, false) end
  if pub_name_hit ~= pub.name_hit then pub.name_hit = pub_name_hit; r.SetExtState(EXT, "name_hit", pub_name_hit, false) end
  if pub_ticon_hit ~= pub.ticon_hit then pub.ticon_hit = pub_ticon_hit; r.SetExtState(EXT, "ticon_hit", pub_ticon_hit, false) end
  if SLOT.last ~= SLOT.pub then SLOT.pub = SLOT.last; r.SetExtState(EXT, "slot", SLOT.last, false) end   -- the last SLOT run's report
  if (SLOT.hit or "") ~= SLOT.hit_pub then SLOT.hit_pub = SLOT.hit or ""; r.SetExtState(EXT, "slot_hit", SLOT.hit_pub, false) end   -- the button's box
  if (SLOT.msg or "") ~= SLOT.msg_pub then SLOT.msg_pub = SLOT.msg or ""; r.SetExtState(EXT, "slot_msg", SLOT.msg_pub, false) end   -- its word, "" when none
  publish_drawer()
end

-- ── open with REAPER again ────────────────────────────────────────────────────────────────────────
-- Every few seconds the dock stamps the wall clock (saved with REAPER's settings); GainKit Plus, starting with
-- REAPER, compares it with its own stamp and opens the dock again when both were alive at the end. A close by
-- the user (the tab's X) clears the stamp at once.
local wall_t = 0
local function stamp_wall()
  local now = os.time()
  if now - wall_t >= 5 then wall_t = now; r.SetExtState(EXT, "wall", tostring(now), true) end
end

local saved = false
local function save_dock()
  if saved then return end
  saved = true
  r.SetExtState(EXT, "dockstate", tostring(gfx.dock(-1)), true)   -- after gfx.quit the query is garbage
end

local function quit()
  pcall(save_dock)
  -- the docker tabs come back when the dock goes (the user, 2026-10-07: "can the tabs come back to all docks when
  -- gainkit is closed?"): HIDE TABS is REAPER-wide and outlived the dock; now a dock that closes with the tabs hidden
  -- shows them again and remembers to hide them at its next start (tabs_rehide)
  if not quit_tabs_done then                                       -- once: quit runs again from atexit, after the
    quit_tabs_done = true                                          -- tabs are back (a global: the 200-local limit)
    if tabs_hidden() then r.SetExtState(EXT, "tabs_rehide", "1", true); pcall(set_tabs_hidden, false)
    else r.SetExtState(EXT, "tabs_rehide", "0", true) end
  end
  release_all()
  pcall(KEEP.tick, true)                                           -- no kept float outlives the dock
  r.SetExtState(EXT, "held", "", false)
  r.SetExtState(EXT, "view", "", false)
  r.SetExtState(EXT, "bar", "", false)
  r.SetExtState(EXT, "alive", "", false)
  MENU.on, MENU.ctx = false, nil
  PICK.on, PICK.ctx = false, nil
  NAME.on = false
  for _, k in ipairs({ "menu", "menu_rows", "picker", "picker_cells", "picker_cats", "picker_sel", "colp", "hover", "tip", "name_edit", "name_hit", "ticon_hit" }) do r.SetExtState(EXT, k, "", false) end
  r.SetExtState(EXT, "drwl", "", false)                             -- holds nothing now: the band keeps the other docks'
  pub.own = nil; publish_drawer(true)
  pcall(function() r.set_action_options(8) end)                    -- the toolbar button goes dark
end
local function closed_by_user()
  r.SetExtState(EXT, "wall", "0", true)                            -- not open again with REAPER
end

local function loop()
  r.SetExtState(EXT, "alive", tostring(r.time_precise()), false)   -- for GainKit Plus: the dock is up now
  stamp_wall()
  -- WS_CLIPCHILDREN (set at start, below) is DROPPED by REAPER when the window moves to another docker
  -- (measured 2026-10-06, dockmove_side_probe.lua: 0x56000000 at the bottom, 0x50000000 after a move to a side
  -- docker); without it this window's every-frame blit covers the plugins it holds and they blink until they draw
  -- again (the user: "blinking a lot", stopped only by a restart). Checked every frame, put back when missing.
  local st = dock and r.JS_Window_GetLong(dock, "STYLE")
  if st and (math.floor(st) & 0x02000000) == 0 then
    r.JS_Window_SetLong(dock, "STYLE", math.floor(st) | 0x02000000)
    dbg("clip-children put back (the window was moved to another docker)")
  end
  sc = math.max(1, gfx.ext_retina or 1)
  -- another project tab: let go properly (the floats closed, in THEIR project) and follow this one's selection
  local here = r.EnumProjects(-1)
  if cur and cur.proj ~= here then
    dbg("project changed")
    local held = {}
    for _, s in ipairs(slots) do
      if s.canvas then held[#held + 1] = { tg = s.tg, fg = s.fg, kind = s.kind, name = s.name } end
    end
    tabs_left[cur.proj] = #held > 0 and { cur = cur, first = first, held = held } or nil
    for p in pairs(tabs_left) do                                    -- tabs closed since: forget them
      if not r.ValidatePtr(p, "ReaProject*") then tabs_left[p] = nil end
    end
    release_all(); cur = nil; note = nil; last_sel_g = false
    KEEP.tick(true)                                                -- the kept floats close in THEIR project too
  end
  -- back on a tab it went away from: REAPER shows that project's windows again, the ones the dock closed too
  -- (measured 2026-10-03), so the dock takes them straight back rather than leave them open
  local t = tabs_left[here]
  if t and #slots == 0 then
    tabs_left[here] = nil
    dbg("back on the tab: " .. #t.held)
    cur, first = t.cur, t.first
    for _, h in ipairs(t.held) do
      local rec = { proj = here, tg = h.tg, fg = h.fg, kind = h.kind, name = h.name }
      take(rec, true)
      if not rec.gone then slots[#slots + 1] = rec end
    end
  end
  -- requests from other scripts and from the tests (the bar's buttons do the same)
  if r.GetExtState(EXT, "close") == "1" then
    r.SetExtState(EXT, "close", "", false)
    closed_by_user(); quit(); gfx.quit(); return
  end
  local req = r.GetExtState(EXT, "kind_req")
  if req ~= "" then
    r.SetExtState(EXT, "kind_req", "", false)
    for k, v in ipairs(KINDS) do if v.key == req then set_kind(k) end end
  end
  req = r.GetExtState(EXT, "pin_req")
  if req ~= "" then r.SetExtState(EXT, "pin_req", "", false); set_pin(req == "1") end
  req = r.GetExtState(EXT, "tabs_req")
  if req ~= "" then r.SetExtState(EXT, "tabs_req", "", false); set_tabs_hidden(req == "1") end
  req = r.GetExtState(EXT, "strip_req")
  if req ~= "" then r.SetExtState(EXT, "strip_req", "", false); set_strip(req == "1") end
  req = r.GetExtState(EXT, "scroll_req")
  if req ~= "" then r.SetExtState(EXT, "scroll_req", "", false); scroll(tonumber(req) or 0) end
  req = r.GetExtState(EXT, "add_req")                              -- tests: the right-click on an effect button
  if req ~= "" then
    r.SetExtState(EXT, "add_req", "", false)
    for k, v in ipairs(KINDS) do if v.key == req then add_kind(k) end end
  end
  -- tests: a chip dragged and let go: "FX GUID|FX GUID it lands before" or "...|END" (after the last of the seven);
  -- a dim chip dragged in: "kind key|FX GUID" or "kind key|END"
  req = r.GetExtState(EXT, "move_req")
  if req ~= "" then
    r.SetExtState(EXT, "move_req", "", false)
    local fg, to = req:match("^([^|]+)|(.+)$")
    if fg then move_fx(fg, to ~= "END" and to) end
  end
  req = r.GetExtState(EXT, "addat_req")
  if req ~= "" then
    r.SetExtState(EXT, "addat_req", "", false)
    local key, to = req:match("^([^|]+)|(.+)$")
    for k, v in ipairs(KINDS) do if v.key == key then add_kind(k, to ~= "END" and to) end end
  end
  req = r.GetExtState(EXT, "show_req")                             -- GainKit Plus: a double-click on a name
  if req ~= "" then r.SetExtState(EXT, "show_req", "", false); show_req(req) end
  req = r.GetExtState(EXT, "closefx_req")                          -- tests: the two close buttons, "track" or "all"
  if req ~= "" then r.SetExtState(EXT, "closefx_req", "", false); close_floats(req) end
  req = r.GetExtState(EXT, "opt_req")                              -- tests: an option, "key=value"
  if req ~= "" then
    r.SetExtState(EXT, "opt_req", "", false)
    local k, v = req:match("^(%w+)=(.*)$")
    if k and OPT_DEF[k] then opt_set(k, v); if k == "fold" then fold_open = true end; if k == "tint" or k == "tintk" then TINT.pass(true) end; has_key = "" end
  end
  if r.GetExtState(EXT, "tint_req") == "1" then r.SetExtState(EXT, "tint_req", "", false); TINT.pass(true) end
  req = r.GetExtState(EXT, "gear_req")                             -- tests: the gear's menu, picked by number
  if req ~= "" then r.SetExtState(EXT, "gear_req", "", false); gear_pick(tonumber(req) or 0) end
  req = r.GetExtState(EXT, "gfxdock_req")                          -- tests: move this window to a docker, a gfx.dock state
  if req ~= "" then                                                -- ("769" = docker 3 docked), as a drag between dockers does
    r.SetExtState(EXT, "gfxdock_req", "", false)
    gfx.dock(tonumber(req) or 0)
    dbg("gfxdock_req " .. req .. " -> " .. tostring(gfx.dock(-1)) .. ", the window held " .. tostring(dock) .. " still a window " .. tostring(dock and r.JS_Window_IsWindow(dock)))
  end
  req = r.GetExtState(EXT, "colp_req")                             -- tests: the palette, "open" | "close" | "1".."16" | "none" | "more"
  if req ~= "" then
    r.SetExtState(EXT, "colp_req", "", false)
    if req == "open" then local sx, sy = r.JS_Window_ClientToScreen(dock, 20, bar_h()); COLP.open(sx, sy)
    elseif req == "close" then COLP.close()
    elseif req == "none" then COLP.set(0)
    elseif req == "more" then COLP.ask = true
    elseif tonumber(req) and COLP.cols[tonumber(req)] then local c = COLP.cols[tonumber(req)]; COLP.set(r.ColorToNative(c[1], c[2], c[3]) | 0x1000000) end
  end
  req = r.GetExtState(EXT, "rmenu_req")                            -- tests: a right-click menu's row, "track:N" | "chip:<i>:N"
  if req ~= "" then                                                -- (i = the bar's chip number), the menu not shown
    r.SetExtState(EXT, "rmenu_req", "", false)
    local kindr, a1, a2 = req:match("^(%a+):(%d+):?(%d*)$")
    if kindr == "track" then RMENU.track(0, 0, tonumber(a1))
    elseif kindr == "chip" and bar_chips[tonumber(a1)] then RMENU.chip(bar_chips[tonumber(a1)], 0, 0, tonumber(a2)) end
  end
  req = r.GetExtState(EXT, "menu_req")                             -- tests: the gear's menu, "open" at the bar's middle | "close"
  if req ~= "" then
    r.SetExtState(EXT, "menu_req", "", false)
    if req == "open" then
      local sx, sy = r.JS_Window_ClientToScreen(dock, math.floor(gfx.w / 2), bar_h())
      local ok, res = pcall(MENU.open, sx, sy)
      if not ok then dbg("menu_req error: " .. tostring(res)); MENU.close() elseif not res then dbg("menu_req: no ReaImGui") end
    else MENU.close() end
  end
  req = r.GetExtState(EXT, "pick_req")                             -- tests: the icon picker, "open" | "close" | "none" | an icon's name
  if req ~= "" then
    r.SetExtState(EXT, "pick_req", "", false)
    if req == "open" then
      local ok, res = pcall(PICK.open)
      if not ok then dbg("pick_req error: " .. tostring(res)); PICK.close() end
    elseif req == "close" then PICK.close()
    elseif req == "none" then PICK.set(nil)
    elseif req:sub(1, 4) == "dir:" then if #PICK.list == 0 then PICK.load_state() end; PICK.add_dir(req:sub(5))
    elseif req:sub(1, 4) == "cat:" then PICK.cat = req:sub(5)
    elseif req:sub(1, 2) == "q:" then PICK.q = req:sub(3)
    elseif req:sub(1, 5) == "size:" then PICK.size = PICK.norm_size(req:sub(6)); PICK.lbl = {}; r.SetExtState(EXT, "pick_size", tostring(PICK.size), true)
    elseif req:sub(1, 5) == "side:" then PICK.side = req:sub(6) == "1"; r.SetExtState(EXT, "pick_side", req:sub(6), true)
    elseif req:sub(1, 11) == "closeafter:" then PICK.close_after = req:sub(12) == "1"; r.SetExtState(EXT, "pick_close", req:sub(12), true)
    elseif req:sub(1, 4) == "key:" then PICK.key_req = req:sub(5)
    elseif req:sub(1, 4) == "all:" then r.SetExtState(EXT, "pick_all", req:sub(5), true)
    elseif req:sub(1, 4) == "fav:" then
      if #PICK.list == 0 then PICK.load_state(); PICK.scan() end
      for _, e in ipairs(PICK.list) do if e.name == req:sub(5) then local k = PICK.key(e); if PICK.fav[k] then PICK.fav[k] = nil else PICK.fav[k] = true end; PICK.save_fav(); break end end
    elseif req:sub(1, 9) == "newgroup:" then
      if #PICK.list == 0 then PICK.load_state(); PICK.scan() end
      PICK.g_new(nil, req:sub(10))
    elseif req:sub(1, 7) == "newsub:" then                          -- newsub:<parent path>:<name>
      if #PICK.list == 0 then PICK.load_state(); PICK.scan() end
      local par, nm = req:match("^newsub:(.+):([^:]+)$"); if par then PICK.g_new(par, nm) end
    elseif req:sub(1, 9) == "rengroup:" then                        -- rengroup:<path>:<new last step>
      if #PICK.list == 0 then PICK.load_state(); PICK.scan() end
      local g, nn = req:match("^rengroup:(.+):([^:]+)$"); if g then PICK.g_rename(g, nn) end
    elseif req:sub(1, 9) == "delgroup:" then                        -- delgroup:<path>
      if #PICK.list == 0 then PICK.load_state(); PICK.scan() end
      PICK.g_delete(req:sub(10))
    elseif req:sub(1, 6) == "group:" then
      if #PICK.list == 0 then PICK.load_state(); PICK.scan() end
      local g, nm = req:match("^group:([^:]+):(.+)$")
      if g and PICK.groups[g] then for _, e in ipairs(PICK.list) do if e.name == nm then PICK.groups[g][PICK.key(e)] = true; PICK.save_groups(); break end end end
    else
      if #PICK.list == 0 then PICK.load_state(); PICK.scan() end
      for _, e in ipairs(PICK.list) do if e.name == req then PICK.set(e); break end end
    end
  end
  req = r.GetExtState(EXT, "name_req")                             -- tests: the name field, "start" | "commit" | "cancel" | "type:<text>"
  if req ~= "" then
    r.SetExtState(EXT, "name_req", "", false)
    if req == "start" then name_edit_start(shown_track())
    elseif req == "commit" then name_edit_end(true)
    elseif req == "cancel" then name_edit_end(false)
    elseif req:sub(1, 5) == "type:" and NAME.on then name_insert(req:sub(6)) end
  end
  req = r.GetExtState(EXT, "fold_req")                             -- tests: "open" drops the folded bar, "close" folds it
  if req ~= "" then
    r.SetExtState(EXT, "fold_req", "", false)
    fold_open = req == "open"
  end
  if fold_open ~= C.fold_saved then                                  -- the bar opened or folded: kept for the next start
    C.fold_saved = fold_open; r.SetExtState(EXT, "fold_open", fold_open and "1" or "0", true)
  end
  req = r.GetExtState(EXT, "slot_req")                             -- tests: the SLOT button, "<n>" | "step:<d>" | "menu:<pick>"
  if req ~= "" then
    r.SetExtState(EXT, "slot_req", "", false)
    local ok, err = pcall(function()
      if req:sub(1, 5) == "step:" then SLOT.step(tonumber(req:sub(6)) or 0)
      elseif req:sub(1, 5) == "menu:" then SLOT.menu(0, 0, tonumber(req:sub(6)))
      elseif req:sub(1, 4) == "move" then                          -- "move:<track>:<n>" / "movenr:<track>:<n>" (no second scan)
        local how, nm, nn = req:match("^(move%a*):(.+):(%d+)$")
        if nm then SLOT.test_move, SLOT.test_norescan = nm, how == "movenr"; SLOT.go(tonumber(nn)) end
      else SLOT.go(tonumber(req) or 1) end
    end)
    if not ok then dbg("slot_req error: " .. tostring(err)) end
  end
  do local ok, err = pcall(SLOT.tick); if not ok then dbg("slot tick error: " .. tostring(err)) end end   -- the wheel's notches, one run

  for _, s in ipairs(slots) do watch(s) end
  sweep()
  KEEP.tick(false)
  follow(false)
  check_chain()
  if NAME.on then
    local f = r.JS_Window_GetFocus and r.JS_Window_GetFocus()
    if f and f ~= dock and not r.JS_Window_IsChild(dock, f) then name_edit_end(true) end   -- the keyboard went elsewhere
  end
  if NAME.on and not name_keys() then closed_by_user(); quit(); return end
  draw_bar()
  -- a new track this tick: the bar (its name and colour) is put on screen now, before the effects' floats are
  -- opened below (REAPER stalls while it opens them), so the dock answers the click at once
  if cur and cur.tg ~= KEEP.bar_tg then KEEP.bar_tg = cur.tg; gfx.update() end
  if COLP.on then
    local ok, err = pcall(COLP.frame)                    -- nor one in the palette
    if not ok then dbg("palette error: " .. tostring(err)); COLP.close() end
    last_cap = gfx.mouse_cap                             -- the bar sees no edge from a click that closed it
  elseif MENU.on then
    local ok, err = pcall(menu_frame)                    -- an error in the menu never takes the dock down
    if not ok then dbg("menu error: " .. tostring(err)); MENU.close() end
    last_cap = gfx.mouse_cap
  else
    bar_mouse()
  end
  if PICK.on then
    local ok, err = pcall(PICK.frame)                  -- nor one in the picker
    if not ok then dbg("picker error: " .. tostring(err)); PICK.close() end
  end
  COLP.after()                                           -- REAPER's colour dialog, between frames
  if (COLP.on and "1" or "0") ~= COLP.pub then COLP.pub = COLP.on and "1" or "0"; r.SetExtState(EXT, "colp", COLP.pub, false) end
  if want_close then closed_by_user(); quit(); gfx.quit(); return end   -- the bar's X
  if opt.tint == "1" then TINT.pass(false) end                    -- the icons follow the track colours
  layout()
  sweep()
  draw_body()
  publish()
  gfx.update()
  if gfx.getchar() >= 0 then r.defer(loop) else closed_by_user(); quit() end
end

-- This script's own window: one titled TITLE inside THIS REAPER (docked: under its main window; floating: owned
-- by it). A search of every window by its title alone can find another REAPER's dock (two REAPERs running, a main
-- and a portable: the audit, 2026-10-03), and this one would then move plugins into that window.
local MAIN = r.GetMainHwnd()
local function in_this_reaper(h)
  local p = h
  for _ = 1, 32 do
    if p == MAIN then return true end
    local up = r.JS_Window_GetParent(p)                -- a child's parent; a top-level popup's owner
    if not up then break end
    p = up
  end
  return p == MAIN or r.JS_Window_GetRelated(p, "OWNER") == MAIN
end
local function find_own_window()
  local _, list = r.JS_Window_ListFind(TITLE, true)
  local all = {}
  for a in (list or ""):gmatch("[^,]+") do
    local h = r.JS_Window_HandleFromAddress(tonumber(a))
    if h then
      if in_this_reaper(h) then dbg("own window " .. tostring(h) .. ": this REAPER's"); return h end
      all[#all + 1] = h
    end
  end
  dbg("own window: " .. #all .. " titled so, none under this REAPER")
  if #all == 1 then return all[1] end                  -- one alone (a floating window with no owner): no doubt
end

-- ── SLOT: the same effect row on every mixer strip (the user, 2026-10-07: "can we scroll our mixer by fx slot how
-- users can scroll in reason's daw") ──────────────────────────────────────────────────────────────────────────────
-- REAPER has no call that scrolls a strip's FX list. What it has (measured 2026-10-06..08, slotresearch*_probe.lua;
-- the handoff's "Scroll by FX slot" sections): the list scrolls one effect per WM_MOUSEWHEEL message to the strips'
-- window (REAPERMCPDisplay) while the REAL pointer is over that strip's FX area (the message's own coordinates are
-- ignored), the delta in wParam's HIGH word; GetThingFromPoint over an embedded face answers "mcp.fxembed N" with
-- N = the FX index, so a strip's scroll reads back. SLOT.go(n): for every strip on screen, the pointer is parked at
-- the top-left corner of its FX area (a spot that moves no parameter), <its FX count> "up" messages then n - 1
-- "down" ones are SENT (synchronous: the next strip follows in the same tick), and the pointer goes back where it
-- was. Strips and rows come from REAPER's own hit-tests (GetTrackFromPoint along x, GetThingFromPoint down each
-- strip), never from a theme's numbers; a list of plain (not embedded) rows scrolls the same way but reads back
-- as "?". Strips the mixer has scrolled away are PAGED to (SetMixerScroll, a forced repaint so the page is laid
-- out at once, the view put back at the end): every track the mixer shows gets the row, not only the visible ones.
-- The bar's SLOT button: a click lists the slots (as many as the longest chain in the mixer has), the wheel over
-- it steps. SLOT is a global on purpose (the 200-local limit, see TINT).
-- Tests: slot_req = "<n>" | "step:<d>" | "menu:<pick>"; published slot = the last run's report.
SLOT = { n = 1, max = 2, last = "", pub = nil }
function SLOT.displays()                                          -- the mixer's strip windows (the tracks', the master's)
  if not (r.JS_WindowMessage_Send and r.JS_Mouse_SetPosition and r.GetThingFromPoint and r.JS_Window_ListAllTop) then
    return nil, "needs js_ReaScriptAPI and a newer REAPER"
  end
  if r.GetToggleCommandState(40078) ~= 1 then return nil, "the mixer is not open" end
  -- by CLASS, not by the window's title (a localized REAPER names the mixer otherwise): the strip windows under the
  -- main window (a docked mixer) and under every top-level window the main window owns (a floating one)
  local roots = { MAIN }
  local _, tops = r.JS_Window_ListAllTop()
  for a in (tops or ""):gmatch("[^,]+") do
    local h = r.JS_Window_HandleFromAddress(tonumber(a))
    if h and h ~= MAIN and r.JS_Window_IsVisible(h) and r.JS_Window_GetRelated(h, "OWNER") == MAIN then roots[#roots + 1] = h end
  end
  local out = {}
  for _, root in ipairs(roots) do
    local arr = r.new_array({}, 512)
    local got = r.JS_Window_ArrayAllChild(root, arr)             -- too small: a NEGATIVE count and nothing filled
    if got and got < 0 then arr = r.new_array({}, -got + 16); r.JS_Window_ArrayAllChild(root, arr) end   -- (measured 2026-10-08)
    for _, ad in ipairs(arr.table()) do
      local c = ad ~= 0 and r.JS_Window_HandleFromAddress(ad)
      if c and r.JS_Window_GetClassName(c) == "REAPERMCPDisplay" and r.JS_Window_IsVisible(c) then
        local _, L, T, R, B = r.JS_Window_GetRect(c)
        if R - L > 40 and B - T > 80 then out[#out + 1] = { h = c, L = L, T = T, R = R, B = B } end
      end
    end
  end
  if #out > 0 then return out end
  return nil, "no mixer strips on screen"
end
function SLOT.strips(d)                                           -- one window's strips, left to right: track, edges
  local step = math.max(4, math.floor(6 * sc))                    -- a strip is 50+ px wide; its edges +-6 px are fine
  for _, f in ipairs({ 0.72, 0.5, 0.9 }) do                       -- a row every strip answers on (the fader's); three tries
    local out, prev, ptr, start = {}, nil, nil, 0
    local y = d.T + math.floor((d.B - d.T) * f)
    for x = d.L + 1, d.R - 1, step do
      local tr = r.GetTrackFromPoint(x, y)
      local key = tr and r.GetTrackGUID(tr) or ""
      if key ~= prev then
        if prev and prev ~= "" then out[#out + 1] = { tr = ptr, x0 = start, x1 = x - 1 } end
        prev, ptr, start = key, tr, x
      end
    end
    if prev and prev ~= "" then out[#out + 1] = { tr = ptr, x0 = start, x1 = d.R - 1 } end
    if #out > 0 then return out end
  end
  return {}
end
function SLOT.fxrow(x, y, want_tr)                                -- an FX LIST row at a point (of want_tr when given), or nil
  -- "mcp.fxembed N" (an embedded face) and "mcp.fxlist N fx:M" (a plain row) are the list; "mcp.fx" alone is the
  -- FX BUTTON of a layout with no list (I Logic V2 at this size, 2026-10-08: a wheel burst there scrolled the whole
  -- mixer sideways), "mcp.fxparm" the parameter knobs: neither scrolls a list. The row must belong to the strip being
  -- done: a mixer showing tracks in several rows puts another track's strip in the same column (self-audit 2026-10-08)
  local tr, info = r.GetThingFromPoint(x, y)
  if tr and info and (not want_tr or tr == want_tr) and (info:find("^mcp%.fxembed") or info:find("^mcp%.fxlist")) then return info end
end
function SLOT.fxtop(d, s)                                         -- the top of a strip's FX area: its y and the row's name
  local x = math.floor((s.x0 + s.x1) / 2)
  local step = math.max(4, math.floor(8 * sc))                    -- a plain FX row is 16+ px tall: 8 px cannot skip one; the
                                                                  -- walk-up below finds the first pixel (the scan was the cost)
  for y = d.T + 2, d.B - 2, step do
    local info = SLOT.fxrow(x, y, s.tr)
    if info then
      local y0 = y
      while y0 > d.T + 1 and SLOT.fxrow(x, y0 - 1, s.tr) do y0 = y0 - 1 end   -- up to the area's first pixel
      return y0, info
    end
  end
end
function SLOT.cover(d, s, top)                                    -- a window over the strip right above its FX area's found top
  -- (the user's run, 2026-10-08: four strips whose FX area read 232 px lower, a window over their upper part; the
  -- scroll under it works, but the read-back at the lower spot reads a lower face). nil = nothing over it
  if not (r.JS_Window_FromPoint and top) then return nil end
  local y = top - math.max(2, math.floor(2 * sc))
  if y <= d.T then return nil end
  local wnd = r.JS_Window_FromPoint(math.floor((s.x0 + s.x1) / 2), y)
  if not wnd or wnd == d.h or r.JS_Window_IsChild(d.h, wnd) then return nil end
  return wnd
end
function SLOT.cover_any(d, s)                                     -- a window over ANY part of the strip (its whole FX area may be
  -- under it: no FX row visible at all; Codex delta review 2026-10-08), down its middle, coarse steps; nil = none
  if not r.JS_Window_FromPoint then return nil end
  local cx, step = math.floor((s.x0 + s.x1) / 2), math.max(6, math.floor(10 * sc))
  for y = d.T + 2, d.B - 2, step do
    local wnd = r.JS_Window_FromPoint(cx, y)
    if wnd and wnd ~= d.h and not r.JS_Window_IsChild(d.h, wnd) then return wnd end
  end
  return nil
end
function SLOT.cover_name(wnd)                                     -- for the report: a REAPER window by its title, others by class
  local root = wnd                                                -- up to its top-level window (WS_CHILD off); the extension
  for _ = 1, 32 do                                                -- has no GetRoot
    local st = r.JS_Window_GetLong(root, "STYLE")
    if not st or (math.floor(st) & 0x40000000) == 0 then break end
    local p = r.JS_Window_GetParent(root)
    if not p then break end
    root = p
  end
  local cls = r.JS_Window_GetClassName(root) or "?"
  local mine = root == MAIN or in_this_reaper(root)
  return mine and ("REAPER's '" .. (r.JS_Window_GetTitle(root) or "") .. "'") or ("another program's window (" .. cls .. ")")
end
function SLOT.scroll(d, s, n, top, once)                          -- one strip: to the top, then n - 1 down; the top row read back
                                                                  -- once: one round, nothing judged (a strip under a window)
  local py = top + math.floor(3 * sc)
  local cx = math.floor((s.x0 + s.x1) / 2)                        -- read back mid-strip: the corner misread once in five
  -- the parking spot must BE a list row (a wheel anywhere else is the mixer's own: sideways scroll): the corner,
  -- else mid-strip, else this strip is left alone
  local px = s.x0 + math.floor(4 * sc)
  if not SLOT.fxrow(px, py, s.tr) then px = cx end
  if not SLOT.fxrow(px, py, s.tr) then
    local t = r.GetThingFromPoint(cx, py)                         -- another strip there: the page moved since the scan
    if t and t ~= s.tr then return nil, "another strip at the spot", false, false, false, true end
    return nil, "no list row at the spot", false, true
  end
  local lx, ly = px & 0xFFFF, py & 0xFFFF
  local count = r.TrackFX_GetCount(s.tr)
  local want = math.min(n, count) - 1
  local k, info, atend, valid, moved
  local function read()                                           -- the top row mid-strip: its index (embedded), its name, and
    local tr, inf = r.GetThingFromPoint(cx, py)                   -- whether a LIST row OF THIS STRIP was read at all (a window
    local ok = tr == s.tr and inf and (inf:find("^mcp%.fxembed") or inf:find("^mcp%.fxlist")) and true or false   -- over it: no)
    -- ANOTHER track's strip under the spot now: the page moved while this strip was being done (a real-mouse run,
    -- 2026-10-08: Tom Lo's burst landed on Snare); the caller scans the page again and finds it in its new place
    moved = tr ~= nil and tr ~= s.tr
    return ok and tonumber(inf:match("^mcp%.fxembed (%d+)")) or nil, inf, ok
  end
  -- a mouse in motion pulls the pointer off its spot in the middle of a burst (the sandbox: one strip in ~30 did not
  -- move while 144 strip-scrolls with nobody at the mouse all did): read back, park and send again, three tries
  for _ = 1, 3 do
    r.JS_Mouse_SetPosition(px, py)
    for _ = 1, count do r.JS_WindowMessage_Send(d.h, "WM_MOUSEWHEEL", 0, 120, lx, ly) end
    for _ = 2, n do r.JS_WindowMessage_Send(d.h, "WM_MOUSEWHEEL", 0, -120, lx, ly) end
    k, info, valid = read()
    if once or moved then break end                                -- (moved: the burst went to another strip, which wants the
                                                                   -- same row: harmless; this one is done again by the caller)
    if valid and not k then break end                              -- a plain row on top: nothing to check
    if k == want then break end
    if k and k < want then
      -- short of it. Either the list stops because its end is in view (a tall mixer shows the rest of the chain
      -- below the top row; measured 2026-10-08: a 1040-tall mixer tops out at index 3 of 7), or the burst was
      -- broken: the mouse moved the pointer off the spot, or another window covers the strip there (REAPER's
      -- hit-test then names no track). The pointer still on the spot and REAPER naming this track there = the
      -- end, as far as that list goes; anything else = another round
      local qx, qy = r.GetMousePosition()
      if qx == px and qy == py and r.GetThingFromPoint(px, py) == s.tr then atend = true; break end
    end
  end
  return k, info, atend, false, valid, moved
end
function SLOT.shown()                                             -- the tracks the mixer shows, in order (the master apart)
  local t = {}
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if r.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER") == 1 then t[#t + 1] = tr end
  end
  return t
end
function SLOT.longest()                                           -- the longest chain among the mixer's tracks (+ the master)
  local m = r.TrackFX_GetCount(r.GetMasterTrack(0))
  for _, tr in ipairs(SLOT.shown()) do m = math.max(m, r.TrackFX_GetCount(tr)) end
  return m
end
function SLOT.run(disps, n)
  local t_start, t_scan, t_wheel, t_paint = r.time_precise(), 0, 0, 0
  local done, missed, norow, tops, strips, pages = 0, 0, 0, {}, 0, 1   -- done: as asked (or as far as the list goes);
  local seen, lines, bad = {}, {}, {}                             -- missed: a list that did not land or could not be
  local covered, hidden, deferred = 0, {}, {}                     -- covered: scrolled under a window, not checked
  local covered_g, edge_covered = {}, false                       -- edge_covered: a page's first strip was still under a
                                                                  -- window at the left edge: paging cannot help, no more waiting
  local left0 = r.GetMixerScroll()                                -- the view to put back; nil = the mixer cannot page
  local master = r.GetMasterTrack(0)
  local function page(final, only, last)                          -- read back; norow: a strip with FX but no list row.
                                                                  -- only: this track alone (the page's own first strip);
                                                                  -- last: the page's last scan (a strip whose page moves
                                                                  -- under it is then judged where it stands)
    local did, blank, relayout = 0, 0, false                      -- Every strip on screen not done yet. A strip with FX
    for _, d in ipairs(disps) do                                  -- but no rows yet (never painted) is left for a second
      local t0 = r.time_precise()                                 -- pass after the page's paint (blank counts them);
      local list = SLOT.strips(d)                                 -- final: counted as "no rows" instead
      t_scan = t_scan + r.time_precise() - t0
      for _, s in ipairs(list) do
        local g = r.GetTrackGUID(s.tr)
        if not seen[g] and (not only or g == only) then
          local count = r.TrackFX_GetCount(s.tr)
          t0 = r.time_precise()
          local top, row
          if count > 0 then top, row = SLOT.fxtop(d, s) end
          t_scan = t_scan + r.time_precise() - t0
          local cover = (count > 0 and top) and SLOT.cover(d, s, top) or nil
          if count > 0 and not top and final then cover = SLOT.cover_any(d, s) end   -- no row even after the paint: a window
          -- over the whole FX area? Or a strip cut off by the window's edge (only a sliver shows, no row in it: the big-
          -- project test, 2026-10-08, lost the cut-off strip of every page as "no rows")
          local cut = count > 0 and not top and final and (s.x0 <= d.L + 2 or s.x1 >= d.R - 2)
          if count > 0 and not top and not final then
            blank = blank + 1
          elseif cut and not cover and left0 and s.tr ~= master and g ~= only then
            deferred[g] = true                                    -- its own page shows it whole at the left edge
          elseif cover and left0 and s.tr ~= master and g ~= only and not edge_covered then
            -- a window over its upper part: left for its own page, which brings it to the left edge, out from under
            -- it (the paging below takes the first track not done, and does that one with `only` even if it is still
            -- covered there); the master never moves: done as it stands; no paging: done as it stands
            deferred[g] = true
          elseif count == 0 then
            seen[g] = true; did = did + 1; strips = strips + 1      -- no FX: nothing to scroll
          else
            local _, nm = r.GetSetMediaTrackInfo_String(s.tr, "P_NAME", "", false)
            if nm == "" then nm = s.tr == master and "MASTER" or "(unnamed)" end
            local mark, info, atend, kind = "-", nil, false, nil
            if not top and cover then kind = "w"                  -- its FX area under a window, nothing to park on: not moved
            elseif not top then kind = "norow"
            else
              if SLOT.test_move and nm == SLOT.test_move then     -- tests only (slot_req "move:"): the page shifted by one
                SLOT.test_move = nil                              -- strip right before this strip's burst, as a moving page
                local lt = r.GetMixerScroll()                     -- would (slotmove_probe.lua): one strip back, else on
                local ix = lt and math.floor(r.GetMediaTrackInfo_Value(lt, "IP_TRACKNUMBER"))
                local to = ix and (ix >= 2 and r.GetTrack(0, ix - 2) or r.GetTrack(0, ix))
                if to then r.SetMixerScroll(to) end
              end
              t0 = r.time_precise()
              local k, inf, ae, nospot, valid, mv = SLOT.scroll(d, s, n, top, cover ~= nil)
              t_wheel = t_wheel + r.time_precise() - t0
              info, atend = inf, ae
              if mv and not last then kind = "moved"              -- another strip under the spot now: scanned again below
              elseif nospot then kind = "norow"
              elseif cover then kind = "c"                         -- scrolled, its top out of sight
              elseif not valid then kind = "x"                     -- no list row of its own readable after the burst
              elseif k and k ~= math.min(n, count) - 1 and not atend then kind = "k"; mark = tostring(k)
              else kind = "done"; mark = (k and tostring(k) or "?") .. (atend and "e" or "") end   -- "3e": as far as that list goes
            end
            if kind == "moved" then
              relayout = true
              dbg("   slot: " .. nm .. ": the page moved under it; scanned again")
            else
              seen[g] = true; did = did + 1; strips = strips + 1
              if kind == "w" then missed = missed + 1; bad[#bad + 1] = nm; mark = "w"; covered_g[g] = true
              elseif kind == "norow" then norow = norow + 1; bad[#bad + 1] = nm
              elseif kind == "c" then covered = covered + 1; hidden[#hidden + 1] = nm; mark = "c"; covered_g[g] = true
              elseif kind == "x" then missed = missed + 1; bad[#bad + 1] = nm; mark = "x"
              elseif kind == "k" then missed = missed + 1; bad[#bad + 1] = nm
              else done = done + 1 end
              tops[#tops + 1] = mark
              lines[#lines + 1] = string.format("%s: x %d..%d, %d fx, area top y %s (%s) -> %s%s = %s%s", nm, s.x0, s.x1, count,
                                                tostring(top), tostring(row), tostring(info), atend and " (the end)" or "", mark,
                                                cover and ("; under " .. SLOT.cover_name(cover)) or "")
              dbg("   slot: " .. lines[#lines])
            end
          end
        end
      end
    end
    return did, blank, relayout
  end
  local dc                                                        -- the off-screen bitmap's DC (below), nil = none
  local function paint()                                          -- the page laid out into the bitmap, the screen untouched
    local t0 = r.time_precise()
    for _, d in ipairs(disps) do
      if dc then r.JS_WindowMessage_Send(d.h, "WM_PAINT", dc, 0, 0, 0)
      elseif r.JS_Window_InvalidateRect and r.JS_Window_Update then
        r.JS_Window_InvalidateRect(d.h, 0, 0, d.R - d.L, d.B - d.T, true); r.JS_Window_Update(d.h)
      end
    end
    t_paint = t_paint + r.time_precise() - t0
  end
  -- a strip the mixer never painted has no FX rows yet, and REAPER lays a page out only while painting it
  -- (slotpage_probe.lua: "[mcp]" right after SetMixerScroll). A forced repaint on screen lays it out but shows
  -- every page (the user, 2026-10-08: "it kinda jitters"), so a page that needs it is painted into a bitmap of our
  -- own instead: WM_PAINT sent with that bitmap's DC (slotpage2_probe.lua: the rows appear, the screen's pixels do
  -- not change). Without the LICE calls, the on-screen repaint stays as the fallback. Only a page with strips that
  -- have FX but no rows gets the paint (the user: every wheel notch stalled REAPER for ~100 ms).
  if r.JS_LICE_CreateBitmap and r.JS_LICE_GetDC and r.JS_Window_AddressFromHandle then
    local w, h = 1, 1
    for _, d in ipairs(disps) do w, h = math.max(w, d.R - d.L), math.max(h, d.B - d.T) end
    SLOT.bmp = r.JS_LICE_CreateBitmap(true, w, h)                  -- freed by SLOT.go, whatever happens below
    local hdc = SLOT.bmp and r.JS_LICE_GetDC(SLOT.bmp)
    dc = hdc and r.JS_Window_AddressFromHandle(hdc)
  end
  local function do_page()                                        -- the page now in the mixer: every strip not done yet,
    for attempt = 1, 4 do                                         -- painted off screen when it holds never-painted strips,
      local last = attempt == 4 or SLOT.test_norescan             -- and scanned again while it moves under the run (a
      local _, blank, mv = page(false, nil, last)                 -- self-audit run, 2026-10-08: the page moved by one
      if blank > 0 then                                           -- strip mid-run); the fourth scan judges strips where
        paint()                                                   -- they stand
        local _, _, mv2 = page(true, nil, last)
        mv = mv or mv2
      end
      if not mv then return end
    end
  end
  do_page()                                                       -- the page on screen first
  -- then the mixer turned page by page for the tracks it shows but has scrolled away (the user, 2026-10-08:
  -- "paging"): the first such track made the leftmost strip (SetMixerScroll), its page done, until none is left;
  -- the view put back (SLOT.go). Tracks the mixer hides stay out: nothing can show them. A strip left for later
  -- (a window over it) is such a track too: its page brings it to the left edge.
  if left0 then
    local shown = SLOT.shown()
    -- every turn below ends with its first track done (or named as never on screen), so the shown tracks bound it;
    -- a fixed cap of 64 left the rest of a big project quietly undone (Codex delta review 2026-10-08)
    for _ = 1, #shown + 1 do
      local nxt
      for _, tr in ipairs(shown) do if not seen[r.GetTrackGUID(tr)] then nxt = tr; break end end
      if not nxt then break end
      r.SetMixerScroll(nxt)
      pages = pages + 1
      local gn = r.GetTrackGUID(nxt)
      do_page()
      if not seen[gn] then page(true, gn, true) end               -- the page's first strip: at the left edge now; done as it
      if covered_g[gn] then edge_covered = true; page(true, nil, true) end   -- (still covered there: the rest as they stand)
      if not seen[gn] then                                        -- stands, under a window or not. Still not done: it never
        seen[gn] = true                                           -- came on screen (counted, named: never skipped quietly; the
        if r.TrackFX_GetCount(nxt) > 0 then                       -- self-test 2026-10-08 found one skipped); a track with no FX
          missed = missed + 1                                     -- has nothing to scroll: no word about it
          local _, nm = r.GetSetMediaTrackInfo_String(nxt, "P_NAME", "", false)
          bad[#bad + 1] = nm ~= "" and nm or "(unnamed)"; tops[#tops + 1] = "n"
          lines[#lines + 1] = (nm ~= "" and nm or "(unnamed)") .. ": never came on screen = n"
        end
      end
    end
    for _, tr in ipairs(shown) do                                 -- (none can be left; if one is, it is counted, not lost)
      local g = r.GetTrackGUID(tr)
      if not seen[g] then
        seen[g] = true
        if r.TrackFX_GetCount(tr) > 0 then
          missed = missed + 1
          local _, nm = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
          bad[#bad + 1] = nm ~= "" and nm or "(unnamed)"; tops[#tops + 1] = "n"
          lines[#lines + 1] = (nm ~= "" and nm or "(unnamed)") .. ": not reached = n"
        end
      end
    end
    if r.GetMixerScroll() ~= left0 then r.SetMixerScroll(left0) end
  end
  SLOT.n, SLOT.max = n, math.max(2, math.min(SLOT.longest(), 32))
  local ms = function(t) return math.floor(t * 1000 + 0.5) end
  SLOT.last = string.format("slot %d: %d strips on %d pages, %d scrolled, %d missed, %d no rows, %d behind a window, %d ms (scan %d, wheel %d, paint %d); tops %s",
                            n, strips, pages, done, missed, norow, covered, ms(r.time_precise() - t_start), ms(t_scan), ms(t_wheel), ms(t_paint), table.concat(tops, ","))
  dbg(SLOT.last)
  -- the word on the bar (draw_bar): quiet when every strip did as asked (Codex delta review 2026-10-08: the causes
  -- told apart, and a run that went well clears an older word: SLOT.go); the strips concerned are named
  local tried = done + missed + norow + covered
  local function names(t) return #t > 0 and (": " .. table.concat(t, ", ", 1, math.min(#t, 4)) .. (#t > 4 and " ..." or "")) or "" end
  if strips == 0 then SLOT.say("SLOT: no strips found in the mixer")
  elseif tried > 0 and done + covered == 0 and missed == 0 then SLOT.say("SLOT: nothing scrolled: the strips show no effect rows")
  elseif tried > 0 and done + covered == 0 then SLOT.say("SLOT: nothing scrolled: the lists did not move")
  elseif missed + norow > 0 then SLOT.say(string.format("SLOT: %d of %d strips did not move%s", missed + norow, tried, names(bad)))
  elseif covered > 0 and covered == tried then SLOT.say("SLOT: a window covers the mixer's effect rows: scrolled, not checked")
  elseif covered > 0 then SLOT.say(string.format("SLOT: %d behind a window, scrolled but not checked%s", covered, names(hidden))) end
  -- the run's report, a small file beside REAPER's data (<resource>/Data/ReaKit_FX_slot_report.txt): what every
  -- strip did, for a look when a strip is reported; a temp file first, then renamed (the house rule)
  SLOT.report(lines)
  return missed + norow == 0
end
function SLOT.report(lines)
  local p = r.GetResourcePath() .. "/Data/ReaKit_FX_slot_report.txt"
  local fh = io.open(p .. ".tmp", "w")
  if not fh then return end
  fh:write(os.date("%Y-%m-%d %H:%M:%S"), "  ", SLOT.last, "\n", table.concat(lines, "\n"), "\n")
  fh:close()
  os.remove(p); os.rename(p .. ".tmp", p)
end
function SLOT.say(msg) SLOT.msg, SLOT.msg_t = msg, r.time_precise(); dbg(msg) end
function SLOT.go(n)
  n = math.max(1, math.floor(tonumber(n) or 1))
  local disps, why = SLOT.displays()
  if not disps then SLOT.last = "slot " .. n .. ": " .. why; SLOT.say("SLOT: " .. why); return false end
  local mx, my = r.GetMousePosition()
  SLOT.msg = nil                                                  -- an older word goes; this run speaks for itself
  local left = r.GetMixerScroll()                                 -- the mixer's leftmost strip: a wheel that misses a list
  local ok, res = pcall(SLOT.run, disps, n)                       -- scrolls the mixer sideways; put back if so
  if SLOT.bmp then pcall(r.JS_LICE_DestroyBitmap, SLOT.bmp); SLOT.bmp = nil end   -- the paging's off-screen bitmap
  r.JS_Mouse_SetPosition(mx, my)                                  -- the pointer back where it was, whatever happened
  if left and r.GetMixerScroll() ~= left then r.SetMixerScroll(left); dbg("slot: the mixer had scrolled sideways; put back") end
  SLOT.test_move, SLOT.test_norescan = nil, nil                   -- the test switches last one run
  if not ok then SLOT.last = "slot " .. n .. ": error " .. tostring(res); SLOT.say("SLOT: something went wrong; see the trace"); dbg(SLOT.last); return false end
  return res
end
function SLOT.step(d) SLOT.pending = (SLOT.pending or 0) + d end   -- the wheel's notches add up; ONE run per tick (SLOT.tick)
function SLOT.tick()                                              -- from the loop: a flick of three notches = one run, not three
  local d = SLOT.pending or 0
  if d == 0 then return end
  SLOT.pending = 0
  SLOT.max = math.max(2, math.min(SLOT.longest(), 32))            -- fresh: before any run it was 2, so a first flick stopped
  SLOT.go(math.max(1, math.min(SLOT.max, SLOT.n + d)))            -- at slot 2 (self-audit 2026-10-08)
end
function SLOT.menu(mx, my, forced)                                -- forced: the pick's number (tests), no menu shown
  local disps, why = SLOT.displays()
  SLOT.max = math.max(2, math.min(SLOT.longest(), 32))            -- as many slots as the longest chain in the mixer has
  local m = {}
  if not disps then m[1] = "#" .. why:sub(1, 1):upper() .. why:sub(2)
  else for i = 1, SLOT.max do m[i] = (i == SLOT.n and "!" or "") .. (i == 1 and "Top of every strip" or "Slot " .. i) end end
  gfx.x, gfx.y = mx, my
  local pick = forced or gfx.showmenu(table.concat(m, "|"))
  if disps and pick and pick >= 1 then SLOT.go(pick) end
end

local dockstate = tonumber(r.GetExtState(EXT, "dockstate")) or 1    -- docked, in the first docker
if r.GetExtState(EXT, "tabs_rehide") == "1" and not tabs_hidden() then pcall(set_tabs_hidden, true) end   -- hidden when it last closed (quit)
gfx.ext_retina = 1                                                  -- sizes in real pixels; the scale comes back here
gfx.init(TITLE, C.W0, C.H0, dockstate)
gfx.update()
dock = find_own_window()
if not dock then
  r.MB("The ReaKit FX dock could not find its own window. Run the action again.", "ReaKit FX", 0)
  gfx.quit()
  return
end
-- The dock window never paints over the plugins it holds (WS_CLIPCHILDREN): it redraws every frame (cleared,
-- then the bar), and without this its blit covered a plugin until the plugin drew again (2026-10-03: a
-- docked GainKit came out black under a two-row bar while it was drawing ~38 frames a second).
local style = r.JS_Window_GetLong(dock, "STYLE")
if style then r.JS_Window_SetLong(dock, "STYLE", math.floor(style) | 0x02000000) end
pcall(function() r.set_action_options(1 | 4) end)                   -- run again = close it; the button lights
for _, k in ipairs({ "close", "kind_req", "pin_req", "tabs_req", "strip_req", "scroll_req", "add_req", "move_req", "addat_req",
                     "closefx_req", "opt_req", "gear_req", "fold_req", "menu_req", "pick_req", "name_req", "colp_req", "rmenu_req", "gfxdock_req", "slot_req" }) do
  r.SetExtState(EXT, k, "", false)                                  -- old requests must not reach this run
end
r.atexit(quit)
loop()
