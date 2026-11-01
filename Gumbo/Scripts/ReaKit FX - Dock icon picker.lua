-- ReaKit FX -- the dock's track icon picker, in its own file (2026-10-12; the user: "i absolutely want the icon
-- picker to be its own file"). Not an action: "ReaKit FX - Dock following the selected track.lua" loads it once
-- (loadfile, the file beside it) and hands it one table with what it takes from the dock by name; it returns PICK
-- (the picker's state, and the calls the dock makes) and sets the global TINT (the icons painted in the track's
-- colour; TINT.pass runs from the dock's loop). ReaPack ships it as a source of the GainKit Plus package.
-- EON Free Licence 1.0, EON Studios, 2026.
local D = ...                          -- from the dock: r, EXT, MENU, opt, opt_set, ticon, bar_h, dbg, shown_track,
                                       -- track_color, track_name; sc() and dock() live (they change after the load)
local r, EXT, MENU, opt, opt_set, ticon = D.r, D.EXT, D.MENU, D.opt, D.opt_set, D.ticon
local bar_h, dbg, shown_track, track_color, track_name = D.bar_h, D.dbg, D.shown_track, D.track_color, D.track_name

-- ── the track icon picker ─────────────────────────────────────────────────────────────────────────
-- Our own picker (built 2026-10-05, grown the same day): every icon folder in a grid with a search box. Sources:
-- REAPER's own folder (<resource>/Data/track_icons) and any folder the user adds (the + Folder button, a folder
-- browser; kept in ExtState pick_dirs). A folder is a folder: every subfolder is a category, nothing skipped (the
-- user, 2026-10-05). Category pills: All, Favourites, Recent, the built-in groups for REAPER's own set (by file
-- name, BUILTIN below) joined by our icon set's own groups (EON/groups.txt, shipped with the icons; 2026-10-06), the user's own groups (a text file, GROUPS_FILE: "[Group]" then one icon per line; a
-- right-click on a cell adds it to or removes it from a group; "+ Group" makes one; right-click a group's pill to
-- rename or delete it), then the folders. A click sets the shown track's icon (or every selected track's, with
-- "All selected") in one undo step; double-click sets and closes; Enter in the search box picks the first match;
-- "No icon" clears. Without ReaImGui the menu row runs REAPER's own dialog
-- (action 40899). A root icon of REAPER's folder is stored by bare name (REAPER writes the full path back); others
-- by full path (one under REAPER's folder by its folder-relative name); the bar reads both. The window remembers its place and size (pick_rect). Test hooks: pick_req =
-- open | close | none | <name> | dir:<path> | cat:<key> | fav:<name> | group:<group>:<name> | newgroup:<name> | newsub:<path>:<name> | rengroup:<path>:<name> | delgroup:<path> |
-- all:0|1 | q:<text> | size:<px> (1..3 = the old S M L) | side:0|1 | closeafter:0|1 | key:up|down|left|right|enter; published picker,
-- picker_cells, picker_cats, picker_sel (the highlighted icon's name).
local PICK = { on = false, ctx = nil, font = nil, font_b = nil, list = {}, cat = "", q = "", img = {},
               x = 0, y = 0, w = 0, h = 0, first = false, cells_pub = nil, cats_pub = nil, dirs = {}, groups = {},
               gorder = {}, fav = {}, recent = {}, enter = false, rect = nil, ask = nil,
               size = 44, side = false, close_after = false,           -- pick_size (px), pick_side, pick_close (saved)
               sel = 1, sig = "", qact = false, key_req = nil, sel_pub = nil, lbl = {},    -- the keyboard highlight
               eon = {}, border = {} }                                     -- our set's shipped groups, the pills' order
-- The icon size: a slider, 28..96 px (logical) in steps of 2 (the user, 2026-10-07: "make size in the track icons a
-- slider"); the names show under the icons from 64 up. A size saved by the S / M / L buttons (1..3) is read as 34 / 44 /
-- 72, as they were.
function PICK.norm_size(v)
  v = tonumber(v) or 44
  if v >= 1 and v <= 3 and v == math.floor(v) then v = ({ 34, 44, 72 })[v] end
  return math.max(28, math.min(96, math.floor(v / 2 + 0.5) * 2))
end
local function pick_norm(pth) return (pth:gsub("[\\]", "/")) end
local ICON_ROOT = pick_norm(r.GetResourcePath() .. "/Data/track_icons")
local GROUPS_FILE = pick_norm(r.GetResourcePath() .. "/Data/ReaKit_FX_icon_groups.txt")
-- The track colour on the icon (the gear: "Icons follow the track colour", opt tint, OFF to start; the user,
-- 2026-10-06). A coloured track wears a copy of its icon painted in its colour: <resource>/Data/ReaKit_FX_tinted_icons/
-- <rrggbb>_<icon>.png, ONE file per colour and icon for the whole machine (a second track in the same red with the
-- same icon points at the same file; a new colour makes a new file; a file is never repainted or removed, other
-- tracks and projects may wear it). The track's own icon (what the picker, REAPER's dialog or the project gave it)
-- is kept on the track as P_EXT:ReaKitFX_icon, saved with the project, by its REAPER-folder name when it sits there
-- ("EON/kick.png"), and comes back when the colour goes or the option goes off. The pass reads every track twice
-- a second (three reads a track) and touches only what differs, so a project that is already right is not marked
-- changed. Paint = js_ReaScriptAPI's LICE: the glyph's shape and
-- edges (alpha) kept, its grey scaled against its own brightest pixel so REAPER's dark drawings come out in the
-- full colour (tint_probe.lua, 2026-10-05: PutPixel COPY keeps alpha). Tests: the pass is forced by tint_req = "1".
-- TINT is a GLOBAL on purpose: the main chunk sits at Lua's 200-local limit (one more local fails to load,
-- 2026-10-06), and the gear's handler above needs it before the picker's names below exist.
TINT = { dir = pick_norm(r.GetResourcePath() .. "/Data/ReaKit_FX_tinted_icons"), key = "P_EXT:ReaKitFX_icon", t = 0 }
function TINT.in_dir(p)                                           -- a painted copy's path, from THIS machine or another
  return pick_norm(p):lower():find("/reakit_fx_tinted_icons/", 1, true) ~= nil   -- (a project that travels keeps the
end                                                               -- other machine's path: known by the folder's name)
function TINT.own_name(p)                                         -- a full path under REAPER's icon folder -> its folder name
  local n = pick_norm(p)
  if n:lower():sub(1, #ICON_ROOT + 1) == ICON_ROOT:lower() .. "/" then return n:sub(#ICON_ROOT + 2) end
  return n
end
function TINT.resolve(orig)                                       -- the own name's full path
  if orig:match("^%a:") or orig:sub(1, 1) == "/" then return orig end
  return ICON_ROOT .. "/" .. orig
end
-- The paint colour: the track colour taken part of the way from the icons' own light grey (200), so a strong track
-- colour (pure blue) can give a soft blue icon, not a saturated one (the user, 2026-10-07: "the recolor ... is pretty
-- strong can we kinda turn it down" ... "make it a slider"). The icon picker's Colour slider = opt.tintk, 10..100 % in
-- steps of 5; 50 % (halfway) to start, 100 % = the track colour itself (the look before). The copy is NAMED by the
-- colour it is painted in, so a change of strength makes new copies and never repaints an old one.
TINT.grey = 200
function TINT.pct()                                               -- the strength in %, 10..100, steps of 5
  local v = math.floor((tonumber(opt.tintk) or 50) / 5 + 0.5) * 5
  return math.max(10, math.min(100, v))
end
function TINT.soft(cr, cg, cb)
  local k = TINT.pct() / 100
  local function f(c) return math.floor(TINT.grey + (c - TINT.grey) * k + 0.5) end
  return f(cr), f(cg), f(cb)
end
function TINT.paint(src, cr, cg, cb, dst)                         -- the icon painted in the colour; false when it cannot be
  if not r.JS_LICE_LoadPNG then return false end
  local b = r.JS_LICE_LoadPNG(src); if not b then return false end
  local w, h = r.JS_LICE_GetWidth(b), r.JS_LICE_GetHeight(b)
  if w * h > 256 * 256 then r.JS_LICE_DestroyBitmap(b); return false end   -- a pixel is up to three API calls: 256 px
                                                                  -- paints in ~80 ms, 400 px froze REAPER ~180 ms (paint_time_probe.lua,
                                                                  -- outside audit 2026-10-06); a bigger picture keeps its plain icon
  local top, top_a = 0, 0                                         -- the brightest pixel among the most opaque ones: a
  for y = 0, h - 1 do for x = 0, w - 1 do                          -- resized PNG's faint edge pixels carry wild
    local v = math.floor(r.JS_LICE_GetPixel(b, x, y))             -- colours (rgb 255 at alpha 1, measured 2026-10-06,
    local a = (v >> 24) & 0xFF                                    -- lice_pixels_probe.lua) and would dim the paint
    if a >= 128 or (top_a < 128 and a > top_a) then
      local l = math.max((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
      if a >= 128 and top_a < 128 then top, top_a = l, a elseif l > top then top, top_a = l, a end
    end
  end end
  if top == 0 then top = 255 end
  for y = 0, h - 1 do for x = 0, w - 1 do
    local v = math.floor(r.JS_LICE_GetPixel(b, x, y))
    local a = (v >> 24) & 0xFF
    if a > 0 then
      -- clamped: a faint edge pixel can be brighter than top (top comes from the opaque ones) and an unclamped
      -- channel over 255 spills into its neighbour, the alpha included (outside audit 2026-10-06)
      -- the shade left out (the user, 2026-10-07: "we tint the whole thing. Can we leave the shade out"): the light
      -- body takes the colour, and the darker a pixel is the more it keeps its own grey, so the outline and the
      -- shading stay as drawn (the whole icon used to be the colour scaled by brightness: a dark-blue outline)
      local g = math.max((v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF)
      local l = math.min(1, g / top)
      local function mix(c) return math.floor(g * (1 - l) + c * l * l + 0.5) end
      local col = (a << 24) | (mix(cr) << 16) | (mix(cg) << 8) | mix(cb)
      r.JS_LICE_PutPixel(b, x, y, col, 1.0, "COPY")
    end
  end end
  r.RecursiveCreateDirectory(TINT.dir, 0)
  local ok = r.JS_LICE_WritePNG(dst, b, true)
  r.JS_LICE_DestroyBitmap(b)
  return ok and r.file_exists(dst)
end
TINT.stamps = {}                                                  -- source file -> { size, hash, checked at }
function TINT.stamp(src)                                          -- the icon FILE's own fingerprint: a copy is never repainted,
  local key, now = pick_norm(src):lower(), r.time_precise()       -- so a redrawn icon (an icon-package update) must get a
  local c = TINT.stamps[key]                                      -- new copy's NAME or coloured tracks keep the old drawing
  if c and now - c.t < 5 then return c.h end                      -- (2026-10-06). The size is re-read every 5 s per file;
  local fh = io.open(src, "rb")                                   -- the whole file is hashed (FNV-1a) when the size
  if not fh then TINT.stamps[key] = { s = -1, h = 0, t = now }; return 0 end   -- changes, on the first look and once a
  local size = fh:seek("end")                                     -- minute (a same-size redraw: outside review D, 2026-10-07)
  if not c or c.s ~= size or now - (c.f or 0) >= 60 then
    fh:seek("set"); local d, h = fh:read("*a") or "", 2166136261
    for i = 1, #d do h = ((h ~ d:byte(i)) * 16777619) & 0xFFFFFFFF end
    c = { s = size, h = h, f = now }
  end
  fh:close(); c.t = now; TINT.stamps[key] = c
  return c.h
end
function TINT.name(orig, cr, cg, cb)                              -- the painted copy's file: <rrggbb>_<hash>_<stamp>_<file name>;
  local key, h = pick_norm(orig):lower(), 2166136261              -- the hash (FNV-1a) of the whole own name, case-folded
  for i = 1, #key do h = ((h ~ key:byte(i)) * 16777619) & 0xFFFFFFFF end   -- (Windows folds case):
  return string.format("%s/%02x%02x%02x_%08x_%08x_p2_%s", TINT.dir, cr, cg, cb, h, TINT.stamp(TINT.resolve(orig)),
    (pick_norm(orig):gsub("^.*/", ""):gsub("[^%w%.%-]", "_")))   -- "Drums/Kick.png" and "Drums_Kick.png" made ONE file
                                                                  -- p2 = the paint's second recipe (the shade left out)
end                                                               -- before it (outside audit 2026-10-06)
function TINT.own(tr)                                             -- the track's own icon (for the picker: the one to mark)
  local _, icon = r.GetSetMediaTrackInfo_String(tr, "P_ICON", "", false)
  if icon ~= "" and TINT.in_dir(icon) then
    local _, orig = r.GetSetMediaTrackInfo_String(tr, TINT.key, "", false)
    return orig ~= "" and TINT.resolve(orig) or icon, true
  end
  return icon, false
end
function TINT.pass(force)                                         -- every track: the icon it should wear now
  local now = r.time_precise()                                    -- twice a second: the project's state count does NOT
  if not force and now - TINT.t < 0.5 then return end             -- move for a colour or an icon set by a script
  TINT.t = now                                                    -- (measured 2026-10-06), so the tracks are read each time
  local proj = r.EnumProjects(-1)
  local on = opt.tint == "1"
  local n, made = 0, 0
  for i = 0, r.CountTracks(proj) - 1 do
    local tr = r.GetTrack(proj, i)
    local _, icon = r.GetSetMediaTrackInfo_String(tr, "P_ICON", "", false)
    local _, orig = r.GetSetMediaTrackInfo_String(tr, TINT.key, "", false)
    local tinted = icon ~= "" and TINT.in_dir(icon)
    if on and not tinted then                                     -- what it wears is its own: remembered
      local own = icon ~= "" and TINT.own_name(icon) or ""
      if own ~= orig then r.GetSetMediaTrackInfo_String(tr, TINT.key, own, true); orig = own end
    end
    local col = math.floor(r.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR"))
    if on and orig ~= "" and (col & 0x1000000) ~= 0 then
      local cr, cg, cb = TINT.soft(r.ColorFromNative(col & 0xFFFFFF))
      local dst = TINT.name(orig, cr, cg, cb)
      if not r.file_exists(dst) then
        local src = TINT.resolve(orig)
        if r.file_exists(src) and TINT.paint(src, cr, cg, cb, dst) then made = made + 1 else dst = nil end
      end
      if dst and pick_norm(icon):lower() ~= dst:lower() then r.GetSetMediaTrackInfo_String(tr, "P_ICON", dst, true); n = n + 1 end
    elseif tinted and orig ~= "" then                             -- no colour now, or the option off: its own back
      r.GetSetMediaTrackInfo_String(tr, "P_ICON", orig, true); n = n + 1
    end
  end
  if n > 0 then r.TrackList_AdjustWindows(false); ticon.t = 0 end
  if n > 0 or made > 0 then dbg(string.format("tint: %d track(s) changed, %d file(s) painted", n, made)) end
end
local BUILTIN_ORDER = { "Drums", "Guitars", "Bass", "Keys", "Synths", "Strings", "Brass", "Winds", "Vocals", "Mics",
                        "Buses", "FX", "Rooms", "Marks", "Folders" }      -- one thing per group (the user, 2026-10-06: no "&")
local BUILTIN = {
  ["Drums"] = "beats bongos cabasa congas cowbell cowbell_more cymbal_large cymbal_small drumbox drums hihat kick maracas overheads pads ride_bell ride_rim snare_bottom snare_top tamborine tom xylophone",
  ["Guitars"] = "ac_guitar ac_guitar_full amp amp_combo balalaika banjo guitar guitar2 guitar3 guitar4 guitar5 guitar_full pedal",
  ["Bass"] = "bass bass2 bass3 bass4 bass_full double_bass",
  ["Keys"] = "organ piano",
  ["Synths"] = "synth synth2 synthbass",
  ["Strings"] = "cello harp violin",
  ["Brass"] = "trombone trumpet",
  ["Winds"] = "harmonica sax",
  ["Vocals"] = "female female_head male male_head speech yeah_you_guys_are_great",
  ["Mics"] = "mic mic_condenser_1 mic_condenser_2 mic_dynamic_1 mic_dynamic_2 mic_shotgun",
  ["Buses"] = "group mixer system midi phones meter",
  ["FX"] = "fx reverb tape deck",
  ["Rooms"] = "room_large room_medium room_small",
  ["Marks"] = "bass_clef treble_clef ff pp envelope film idea bin",
  ["Folders"] = "folder folder_down folder_left folder_right folder_up",
}

-- SUB-GROUPS (the user, 2026-10-07: "do the path layout with no cap"). A group's name is a path, "Drums/Cymbals", as
-- deep as anyone likes: our set's groups.txt ("[Drums/Cymbals]"), the user's own groups (same file form) and the
-- folders (a subfolder is a sub-category). A group holds its own icons AND everything below it. The picker shows the
-- top groups as before, and under them the path to where you are ("Drums › Cymbals ›", each step clickable) with one
-- row for just that level; on the side, an indented tree that opens along the path. REAPER's own icons go into our
-- sub-groups by this list (PICK.bsub: path, names; the top group's BUILTIN line still holds them all). Kept on PICK:
-- the main chunk sits at Lua's 200-local limit.
PICK.bsub = {
  { "Drums/Kick", "kick" }, { "Drums/Snare", "snare_bottom snare_top" }, { "Drums/Toms", "tom" },
  { "Drums/Hi-hats", "hihat" }, { "Drums/Cymbals", "cymbal_large cymbal_small ride_bell ride_rim" },
  { "Drums/Overheads and kit", "drums overheads" },
  { "Guitars/Acoustic", "ac_guitar ac_guitar_full" }, { "Guitars/Electric", "guitar guitar2 guitar3 guitar4 guitar5 guitar_full" },
  { "Guitars/Folk", "balalaika banjo" },
  { "Bass/Electric", "bass bass2 bass3 bass4 bass_full" }, { "Bass/Upright", "double_bass" },
  { "Keys/Piano", "piano" }, { "Keys/Organ", "organ" },
  { "Mics/Dynamic", "mic_dynamic_1 mic_dynamic_2 mic" }, { "Mics/Condenser", "mic_condenser_1 mic_condenser_2 mic_shotgun" },
  { "FX/Reverb", "reverb" },
  { "Buses/Instrument buses", "group" }, { "Buses/Master", "mixer system" },   -- the same names as our groups.txt
}
function PICK.parent(path) return path:match("^(.*)/[^/]*$") end   -- nil at the top
function PICK.leaf(path) return path:match("([^/]*)$") end
function PICK.under(path, top) return path == top or path:sub(1, #top + 1) == top .. "/" end   -- top or below it
PICK.bdeep_c = {}
function PICK.bdeep(path)                                         -- REAPER's own icons in a built-in group and below it
  local c = PICK.bdeep_c[path]
  if c then return c end
  c = {}
  if not PICK.parent(path) then for w in (BUILTIN[path] or ""):gmatch("%S+") do c[w] = true end end
  for _, s in ipairs(PICK.bsub) do
    if PICK.under(s[1], path) then for w in s[2]:gmatch("%S+") do c[w] = true end end
  end
  PICK.bdeep_c[path] = c
  return c
end
local function pick_split(sv) local t = {}; for v in (sv or ""):gmatch("[^|]+") do t[#t + 1] = v end; return t end
local function pick_load_state()
  PICK.dirs = pick_split(r.GetExtState(EXT, "pick_dirs"))
  PICK.fav = {}; for _, k in ipairs(pick_split(r.GetExtState(EXT, "pick_fav"))) do PICK.fav[k] = true end
  PICK.recent = pick_split(r.GetExtState(EXT, "pick_recent"))
  PICK.size = PICK.norm_size(r.GetExtState(EXT, "pick_size"))
  PICK.side = r.GetExtState(EXT, "pick_side") == "1"
  PICK.close_after = r.GetExtState(EXT, "pick_close") == "1"
  local rect = r.GetExtState(EXT, "pick_rect")
  local x, y, w, h, ds = rect:match("^(%-?%d+) (%-?%d+) (%d+) (%d+) ?([%d%.]*)$")   -- physical px + the scale seen
  PICK.rect = x and { tonumber(x), tonumber(y), tonumber(w), tonumber(h), tonumber(ds) } or nil   -- (an old place: 4 numbers)
  -- our icon set's own groups (2026-10-06): the icons package ships <icon folder>/EON/groups.txt ("[Group]" then one
  -- icon name per line, written by rkfx_icons_draw.py with the icons, so a set that grows brings its own grouping and
  -- the dock needs no update). Its icons join the built-in pill of the same name (Drums = REAPER's drums AND ours);
  -- a group REAPER's set lacks (Percussion, Amps, Meters...) becomes a new pill; the file's order is the pills'
  -- order, any built-in group it leaves out follows. No file (an older icons package): the built-in pills as before.
  -- A group may be a path ("[Drums/Cymbals]", sub-groups): PICK.eon holds each path's own icons, PICK.eon_order the
  -- paths in the file's order, PICK.border the TOP groups in order of first sight, PICK.eon_deep a path's icons with
  -- everything below it (what its pill shows).
  PICK.eon, PICK.border, PICK.eon_order, PICK.eon_deep = {}, {}, {}, {}
  local tops = {}
  local fh = io.open(ICON_ROOT .. "/EON/groups.txt", "r")
  if fh then
    local g
    for line in fh:lines() do
      line = line:gsub("[\r]$", ""):gsub("^%s+", ""):gsub("%s+$", "")
      local name = line:match("^%[(.+)%]$")
      if name then
        g = name:gsub("%s*/%s*", "/"):gsub("^/+", ""):gsub("/+$", "")
        if not PICK.eon[g] then PICK.eon[g] = {}; PICK.eon_order[#PICK.eon_order + 1] = g end
        local top = g:match("^[^/]*")
        if not tops[top] then tops[top] = true; PICK.border[#PICK.border + 1] = top end
      elseif g and line ~= "" and not line:match("^#") then PICK.eon[g][line] = true end
    end
    fh:close()
  end
  for p, set in pairs(PICK.eon) do                                -- each path's icons count for it and every group above it
    local a = p
    while a do
      local d = PICK.eon_deep[a] or {}; PICK.eon_deep[a] = d
      for n in pairs(set) do d[n] = true end
      a = PICK.parent(a)
    end
  end
  local have = {}
  for _, g in ipairs(PICK.border) do have[g] = true end
  for _, g in ipairs(BUILTIN_ORDER) do if not have[g] then PICK.border[#PICK.border + 1] = g end end
  -- the user's own groups
  PICK.groups, PICK.gorder = {}, {}
  local fh = io.open(GROUPS_FILE, "r")
  if fh then
    local g
    for line in fh:lines() do
      line = line:gsub("[\r]$", "")
      local name = line:match("^%[(.+)%]$")
      if name then
        g = name:gsub("%s*/%s*", "/"):gsub("^/+", ""):gsub("/+$", "")
        local chain, a = {}, g                                    -- a sub-group's parents exist as groups too
        while a do table.insert(chain, 1, a); a = PICK.parent(a) end
        for _, p in ipairs(chain) do
          if not PICK.groups[p] then PICK.groups[p] = {}; PICK.gorder[#PICK.gorder + 1] = p end
        end
      elseif g and line ~= "" then PICK.groups[g][line] = true end
    end
    fh:close()
  end
end
local function pick_save_groups()
  local fh = io.open(GROUPS_FILE, "w")
  if not fh then return end
  for _, g in ipairs(PICK.gorder) do
    fh:write("[", g, "]\n")
    local keys = {}
    for k in pairs(PICK.groups[g]) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do fh:write(k, "\n") end
    fh:write("\n")
  end
  fh:close()
end
local function pick_group_name(nm)                                -- a group's name as the file can hold it ("/" is the
  nm = (nm or ""):gsub("[%[%]\r\n|/]", ""):gsub("^%s+", ""):gsub("%s+$", "")   -- sub-group mark, so not in one name)
  return nm
end
-- The user's groups, edited (the picker's menus and the tests' hooks): a new group (par nil = at the top) or a
-- sub-group; a rename (the last step of the path, its sub-groups follow); a delete (its icons go to the group above
-- it, its sub-groups move up a step; a top group's icons simply leave). Each returns the path to show, or nil.
function PICK.g_new(par, name, icon)
  name = pick_group_name(name)
  if name == "" or (par and not PICK.groups[par]) then return nil end
  local p = par and (par .. "/" .. name) or name
  if PICK.groups[p] then return nil end
  PICK.groups[p] = icon and { [icon] = true } or {}
  PICK.gorder[#PICK.gorder + 1] = p
  pick_save_groups()
  return p
end
function PICK.g_rename(p, nn)
  nn = pick_group_name(nn)
  local par = PICK.parent(p)
  local np = par and (par .. "/" .. nn) or nn
  if nn == "" or np == p or PICK.groups[np] or not PICK.groups[p] then return nil end
  local moved = {}
  for j, g in ipairs(PICK.gorder) do
    if PICK.under(g, p) then
      local ng = np .. g:sub(#p + 1)
      moved[ng] = PICK.groups[g]; PICK.groups[g] = nil; PICK.gorder[j] = ng
    end
  end
  for g, set in pairs(moved) do PICK.groups[g] = set end
  pick_save_groups()
  return np
end
function PICK.g_delete(p)
  if not PICK.groups[p] then return nil end
  local par = PICK.parent(p)
  if par then for k in pairs(PICK.groups[p]) do PICK.groups[par][k] = true end end
  local order = {}
  for _, g in ipairs(PICK.gorder) do
    if g == p then PICK.groups[g] = nil
    elseif PICK.under(g, p) then                                  -- a sub-group one step up (merged into one there already)
      local ng = (par and (par .. "/") or "") .. g:sub(#p + 2)
      local set = PICK.groups[g]; PICK.groups[g] = nil
      if PICK.groups[ng] then for k in pairs(set) do PICK.groups[ng][k] = true end
      else PICK.groups[ng] = set; order[#order + 1] = ng end
    else order[#order + 1] = g end
  end
  PICK.gorder = order
  pick_save_groups()
  return par
end
local function pick_save_fav()
  local t = {}; for k in pairs(PICK.fav) do t[#t + 1] = k end; table.sort(t)
  r.SetExtState(EXT, "pick_fav", table.concat(t, "|"), true)
end
local function pick_key(e) return e.src == 1 and e.store or e.full end  -- how an icon is named in groups and favourites (a root
                                                                  -- icon by its bare name as before; "EON/kick.png" apart from "kick.png")
local function pick_dir_label(i)                                  -- the folder's name; "parent · name" when two end the same
  local d = pick_norm(PICK.dirs[i]):gsub("/+$", "")                -- (not "/": that is the sub-category mark now)
  local last = d:match("([^/]+)$") or d
  for j, o in ipairs(PICK.dirs) do
    if j ~= i and (pick_norm(o):gsub("/+$", ""):match("([^/]+)$") or o) == last then
      return (d:match("([^/]+)/[^/]+$") or "") .. " \u{00B7} " .. last
    end
  end
  return last
end
local function picker_scan()
  local list = {}
  local seen, nfold = {}, 0                                       -- a junction pointing back up the tree would loop forever
  local function scan(dir, cat, si, label, depth)                 -- (outside audit, 2026-10-05): a path is read once, eight
    local key = dir:lower()                                       -- levels down at most, 400 folders in all (a junction's
    if seen[key] or depth > 8 or nfold >= 400 then return end     -- copies carry new path names, so the depth is the guard)
    seen[key] = true; nfold = nfold + 1
    r.EnumerateFiles(dir, -1)                                     -- REAPER caches listings: a fresh one
    local i = 0
    while true do
      local f = r.EnumerateFiles(dir, i)
      if not f or f == "" then break end
      if f:lower():match("%.png$") then
        -- what goes into the track's icon field: for REAPER's own folder a name relative to it ("kick.png",
        -- "EON/kick.png": REAPER resolves both against its folder and expands them, measured icon_subdir_probe.lua
        -- 2026-10-05, so a project travels between machines); for an added folder the full path
        list[#list + 1] = { name = (f:gsub("%.[Pp][Nn][Gg]$", "")), file = f, full = dir .. "/" .. f, cat = cat, src = si,
                            store = si == 1 and (dir .. "/" .. f):sub(#ICON_ROOT + 2) or (dir .. "/" .. f) }
      end
      i = i + 1
    end
    i = 0
    while true do
      local d = r.EnumerateSubdirectories(dir, i)
      if not d or d == "" then break end
      scan(dir .. "/" .. d, cat == "" and (label and (label .. "/" .. d) or d) or (cat .. "/" .. d), si, label, depth + 1)
      i = i + 1
    end
  end
  scan(ICON_ROOT, "", 1, nil, 0)
  for i, d in ipairs(PICK.dirs) do
    local dn, lb = pick_norm(d):gsub("/+$", ""), pick_dir_label(i)
    scan(dn, lb, i + 1, lb, 0)
  end
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  PICK.list = list
end
-- The categories as a tree: returns the TOP row { key, label } in order and sets PICK.kids[key] = the level under a
-- key, { key, label (its last step) }, in order: ours and REAPER's groups (the shipped file's order, then REAPER's own
-- sub-groups), the user's groups (their file's order), the folders (by name; a subfolder under its folder).
local function pick_cats()
  local t = { { "", "All" } }
  if next(PICK.fav) then t[#t + 1] = { "*fav", "Favourites" } end
  if #PICK.recent > 0 then t[#t + 1] = { "*recent", "Recent" } end
  local kids, seen = {}, {}
  local function add(kind, path)                                 -- the path and every group above it, first seen first
    local key = kind .. ":" .. path
    if seen[key] then return key end
    seen[key] = true
    local par = PICK.parent(path)
    if par then
      local pk = add(kind, par)
      kids[pk] = kids[pk] or {}; kids[pk][#kids[pk] + 1] = { key, PICK.leaf(path) }
    else t[#t + 1] = { key, path } end
    return key
  end
  for _, g in ipairs(#PICK.border > 0 and PICK.border or BUILTIN_ORDER) do add("b", g) end
  for _, p in ipairs(PICK.eon_order or {}) do add("b", p) end
  for _, s in ipairs(PICK.bsub) do add("b", s[1]) end
  for _, g in ipairs(PICK.gorder) do add("g", g) end
  local fseen, folders = {}, {}
  for _, e in ipairs(PICK.list) do if e.cat ~= "" and not fseen[e.cat] then fseen[e.cat] = true; folders[#folders + 1] = e.cat end end
  table.sort(folders, function(a, b) return a:lower() < b:lower() end)
  for _, c in ipairs(folders) do add("f", c) end
  PICK.kids = kids
  return t
end
local function pick_in_cat(e, key)                                -- a group shows its own icons and all below it
  if key == "" then return true end
  local k = pick_key(e)
  if key == "*fav" then return PICK.fav[k] == true end
  if key == "*recent" then for _, v in ipairs(PICK.recent) do if v == k then return true end end; return false end
  local kind, name = key:match("^(%a):(.*)$")
  if kind == "b" then
    if e.src ~= 1 then return false end
    if e.cat == "" then return PICK.bdeep(name)[e.name] == true end                    -- REAPER's own
    return e.cat == "EON" and PICK.eon_deep[name] ~= nil and PICK.eon_deep[name][e.name] == true   -- ours, by the shipped groups
  elseif kind == "g" then
    for _, g in ipairs(PICK.gorder) do if PICK.under(g, name) and PICK.groups[g][k] then return true end end
    return false
  elseif kind == "f" then return PICK.under(e.cat, name) end
  return false
end
local function pick_targets()                                     -- the shown track, or every selected one
  if r.GetExtState(EXT, "pick_all") == "1" then
    local t = {}
    for i = 0, r.CountSelectedTracks2(0, true) - 1 do t[#t + 1] = r.GetSelectedTrack2(0, i, true) end
    if #t > 0 then return t end
  end
  local tr = shown_track()
  return tr and { tr } or {}
end
local function picker_set(e)                                      -- e = an entry, nil = no icon
  local trs = pick_targets()
  if #trs == 0 then return end
  local want = e and e.store or ""
  local wantn = pick_norm(want):lower()
  local todo = {}
  for _, tr in ipairs(trs) do                                     -- only the tracks it would change
    local cur = TINT.own(tr)                                    -- a tinted copy stands for the track's own icon
    local curn = pick_norm(cur):lower()
    local same = cur == want or curn == wantn or (e and e.src == 1 and curn == e.full:lower())   -- REAPER wrote the full path back
    if not same then todo[#todo + 1] = tr end
  end
  if #todo > 0 then
    r.Undo_BeginBlock()
    for _, tr in ipairs(todo) do r.GetSetMediaTrackInfo_String(tr, "P_ICON", want, true) end
    r.Undo_EndBlock(e and ("ReaKit FX dock: track icon " .. e.name) or "ReaKit FX dock: track icon removed", -1)
  end
  ticon.t = 0                                                     -- the bar reads the field again at once
  r.TrackList_AdjustWindows(false)
  if opt.tint == "1" then TINT.pass(true) end                     -- the colour on it at once
  if e then                                                       -- the recent row
    local k, t = pick_key(e), { }
    t[1] = k
    for _, v in ipairs(PICK.recent) do if v ~= k and #t < 12 then t[#t + 1] = v end end
    PICK.recent = t; r.SetExtState(EXT, "pick_recent", table.concat(t, "|"), true)
  end
  dbg("picker: " .. (e and e.store or "none") .. " on " .. #trs .. " track(s)")
end
local function picker_close()
  if PICK.on and PICK.rect then r.SetExtState(EXT, "pick_rect", string.format("%d %d %d %d %.2f", PICK.rect[1], PICK.rect[2], PICK.rect[3], PICK.rect[4], PICK.rect[5] or D.sc()), true) end
  PICK.on, PICK.ctx, PICK.img = false, nil, {}
  PICK.cells_pub, PICK.cats_pub = nil, nil
  r.SetExtState(EXT, "picker_cells", "", false); r.SetExtState(EXT, "picker_cats", "", false); r.SetExtState(EXT, "picker_sel", "", false)
end
local function pick_add_dir(d)
  d = pick_norm(d):gsub("/+$", "")
  if d == "" or d:lower() == ICON_ROOT:lower() then return end
  for _, v in ipairs(PICK.dirs) do if v:lower() == d:lower() then return end end
  PICK.dirs[#PICK.dirs + 1] = d
  r.SetExtState(EXT, "pick_dirs", table.concat(PICK.dirs, "|"), true)
  picker_scan()
  dbg("picker: folder added " .. d .. ", " .. #PICK.list .. " icons")
end
local function pick_remove_dir(label)
  for i = 1, #PICK.dirs do
    if pick_dir_label(i) == label then table.remove(PICK.dirs, i); break end
  end
  r.SetExtState(EXT, "pick_dirs", table.concat(PICK.dirs, "|"), true)
  picker_scan()
  if PICK.cat:sub(1, 2) == "f:" then PICK.cat = "" end
end
local function picker_open()
  local ImGui = MENU.imgui()
  if not ImGui then                                               -- REAPER's own dialog, on the shown track
    local tr = shown_track()
    if not tr then return false end
    r.SetOnlyTrackSelected(tr); r.Main_OnCommand(40899, 0)
    return false
  end
  if PICK.on then return true end
  pick_load_state()
  picker_scan()
  PICK.ctx = ImGui.CreateContext("ReaKit FX Dock icons")
  local okf, f = pcall(ImGui.CreateFont, "sans-serif", 0); PICK.font = okf and f or nil
  local okb, fb = pcall(ImGui.CreateFont, "sans-serif", ImGui.FontFlags_Bold); PICK.font_b = okb and fb or nil
  if PICK.font then pcall(ImGui.Attach, PICK.ctx, PICK.font) end
  if PICK.font_b then pcall(ImGui.Attach, PICK.ctx, PICK.font_b) end
  PICK.img, PICK.q, PICK.cat, PICK.enter = {}, "", "", false
  -- where it was last time (physical, with the scale it was seen at); else under the bar around the dock's middle
  -- (400 x 440 logical, so sc of it physical); kept on the screen in physical pixels, then handed to ImGui logical
  local sc, dock = D.sc(), D.dock()  -- the display scale and the dock's window, live from the dock
  local s = sc
  local pw, ph = math.floor(400 * sc), math.floor(440 * sc)
  local sx, sy = r.JS_Window_ClientToScreen(dock, math.floor(gfx.w / 2) - math.floor(pw / 2), bar_h())
  if PICK.rect then sx, sy, pw, ph, s = PICK.rect[1], PICK.rect[2], PICK.rect[3], PICK.rect[4], PICK.rect[5] or sc end
  if r.JS_Window_GetViewportFromRect then
    local vl, vt, vr, vb = r.JS_Window_GetViewportFromRect(sx, sy, sx + 1, sy + 1, true)
    if vb and sy + ph > vb then sy = math.max(vt or 0, vb - ph) end
    if vr and sx + pw > vr then sx = vr - pw end
    if vl and sx < vl then sx = vl end
    if vt and sy < vt then sy = vt end
  end
  PICK.phys, PICK.dpi, PICK.fix = { sx, sy, pw, ph }, s, 2
  PICK.x, PICK.y = DPI.to_logical(sx, sy, s)
  PICK.w, PICK.h = pw / s, ph / s
  PICK.hwnd = nil
  PICK.on, PICK.first, PICK.again, PICK.frames = true, true, false, 0
  dbg("picker: open, " .. #PICK.list .. " icons, " .. #PICK.dirs .. " folders, " .. #PICK.gorder .. " groups")
  return true
end
local function picker_frame()
  local ImGui, ctx = MENU.ImGui, PICK.ctx
  if not (ImGui and ctx) then PICK.on = false; return end
  local tr = shown_track()
  local has, cr, cg, cb = track_color(tr)
  local hue = has and MENU.rgba(cr, cg, cb) or MENU.c.accent
  local CELL = PICK.size                                           -- logical px (ReaImGui scales with the fonts)
  if PICK.first or PICK.again then ImGui.SetNextWindowPos(ctx, PICK.x, PICK.y); ImGui.SetNextWindowSize(ctx, PICK.w, PICK.h); PICK.again = false end
  ImGui.SetNextWindowSizeConstraints(ctx, math.max(CELL * 4 + 30, 330), CELL * 3 + 140, 4000, 4000)
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, MENU.c.bg)
  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, 0x161F28FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, MENU.c.line)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, MENU.c.text)
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBg, 0x141B23FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_TitleBgActive, 0x1A2630FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x283644FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x283644FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x34465AFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, MENU.alpha(hue, 0x80))
  ImGui.PushStyleColor(ctx, ImGui.Col_CheckMark, hue)
  ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, 0x1C2732FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, MENU.alpha(hue, 0x40))
  ImGui.PushStyleColor(ctx, ImGui.Col_Header, MENU.alpha(hue, 0x30))
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 5)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowBorderSize, 1)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 10, 8)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 6, 5)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 4)
  local flags = ImGui.WindowFlags_NoDocking | ImGui.WindowFlags_NoSavedSettings | ImGui.WindowFlags_NoCollapse
  if PICK.font then ImGui.PushFont(ctx, PICK.font, 13) end
  local visible, open = ImGui.Begin(ctx, "Track icon##rkdock_picker", true, flags)
  if visible then
    local dl = ImGui.GetWindowDrawList(ctx)
    local wx, wy = ImGui.GetWindowPos(ctx)
    local ww, wh = ImGui.GetWindowSize(ctx)
    PICK.frames = (PICK.frames or 0) + 1
    local real = ImGui.GetWindowDpiScale and ImGui.GetWindowDpiScale(ctx) or PICK.dpi
    -- only while it settles (its first frames): a picker the user later drags onto a screen scaled otherwise is
    -- NOT snapped back (outside audit 2026-10-07)
    if PICK.frames > 8 then PICK.fix = 0 end
    if PICK.frames >= 2 and PICK.fix > 0 and math.abs(real - PICK.dpi) > 0.01 then   -- it stands on a monitor scaled
      PICK.dpi, PICK.fix = real, PICK.fix - 1                       -- otherwise than it was placed for: placed again
      -- its size with the window's own minimum applied FIRST, then kept on the monitor (a minimum applied after
      -- the clamp pushed a saved place 95 px off a screen's right edge -- outside audit 2026-10-07)
      PICK.w = math.max(PICK.phys[3] / real, math.max(CELL * 4 + 30, 330))
      PICK.h = math.max(PICK.phys[4] / real, CELL * 3 + 140)
      local px, py = PICK.phys[1], PICK.phys[2]
      if r.JS_Window_GetViewportFromRect then
        local vl, vt, vr, vb = r.JS_Window_GetViewportFromRect(px, py, px + 1, py + 1, true)
        if vr and px + PICK.w * real > vr then px = vr - math.floor(PICK.w * real) end
        if vb and py + PICK.h * real > vb then py = vb - math.floor(PICK.h * real) end
        if vl and px < vl then px = vl end
        if vt and py < vt then py = vt end
      end
      PICK.x, PICK.y = DPI.to_logical(px, py, real)
      PICK.again = true
      dbg("picker: the screen is scaled " .. real .. ", placed again")
    end
    if PICK.frames == 2 or (PICK.hwnd and not r.JS_Window_IsWindow(PICK.hwnd)) then   -- its own OS window, for the
      PICK.hwnd = nil                                                                  -- physical place it is saved at
      local _, list = r.JS_Window_ListFind("Track icon", true)
      for a in (list or ""):gmatch("[^,]+") do
        local h = r.JS_Window_HandleFromAddress(tonumber(a))
        if h and r.JS_Window_GetRelated(h, "OWNER") == r.GetMainHwnd() then PICK.hwnd = h end   -- this REAPER's
      end
    end
    if PICK.hwnd then
      local okr, L, T, R, B = r.JS_Window_GetRect(PICK.hwnd)
      if okr then PICK.rect = { L, T, R - L, B - T, real } end
    end
    if PICK.frames == 3 then dbg(string.format("picker frame 3: ImGui pos %d,%d size %dx%d, dpi scale %s, D.sc() %s, own window %s", wx, wy, ww, wh, tostring(real), tostring(D.sc()), PICK.rect and (PICK.rect[1] .. "," .. PICK.rect[2] .. " " .. PICK.rect[3] .. "x" .. PICK.rect[4]) or "?")) end
    ImGui.DrawList_AddRectFilled(dl, wx, wy, wx + ww, wy + 3, hue)             -- the track's stripe
    local cur = ""                                                   -- the track's icon field (an "and" would keep one value)
    if tr then cur = TINT.own(tr) end                                -- a tinted copy stands for the track's own icon
    -- REAPER writes the field back as a full path with backslashes even when given a bare name (measured
    -- 2026-10-05, picker_run.py): compared slash-blind and case-blind, by the full path or the bare name
    local curn = pick_norm(cur):lower()
    -- the track's line: its name in its colour; + Folder, + Group and "No icon" at the right
    if PICK.font_b then ImGui.PushFont(ctx, PICK.font_b, 12) end
    ImGui.TextColored(ctx, hue, tr and track_name(tr) or "no track")
    if PICK.font_b then ImGui.PopFont(ctx) end
    ImGui.SameLine(ctx, ww - 196)
    if ImGui.SmallButton(ctx, "+ Folder") and r.JS_Dialog_BrowseForFolder then PICK.ask = { "folder" } end
    if opt.tips ~= "0" and ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Add a folder of icons; its subfolders become categories") end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, "+ Group") then PICK.ask = { "newgroup" } end
    if opt.tips ~= "0" and ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "A group of your own; right-click an icon to put it in") end
    ImGui.SameLine(ctx)
    if ImGui.SmallButton(ctx, cur == "" and "No icon" or "Remove") and cur ~= "" then picker_set(nil) end
    -- the search box
    if PICK.first then ImGui.SetKeyboardFocusHere(ctx) end
    ImGui.SetNextItemWidth(ctx, -1)
    local ent, q = ImGui.InputTextWithHint(ctx, "##q", "Search the icons (arrows move, Enter picks)", PICK.q, ImGui.InputTextFlags_EnterReturnsTrue)
    if q ~= PICK.q then PICK.q = q end
    PICK.qact = ImGui.IsItemActive(ctx)
    if ent and PICK.q ~= "" then PICK.enter = true end
    -- the switches: all selected tracks, close after a pick; the size (S M L: 34 / 44 / 72 px, names under the icons
    -- at L) and the categories as a list on the side instead of pills (2026-10-06, after a look at Reapertips &
    -- Sexan's selector: its sidebar, size slider and used-icon outline; ideas only, GPL)
    local all_on = r.GetExtState(EXT, "pick_all") == "1"
    local chg, v = ImGui.Checkbox(ctx, "All selected tracks", all_on)
    if chg then r.SetExtState(EXT, "pick_all", v and "1" or "0", true) end
    ImGui.SameLine(ctx, 0, 14)
    chg, v = ImGui.Checkbox(ctx, "Close after a pick", PICK.close_after)
    if chg then PICK.close_after = v; r.SetExtState(EXT, "pick_close", v and "1" or "0", true) end
    local need = ImGui.CalcTextSize(ctx, "Categories on the side") + ImGui.GetFrameHeight(ctx) + 8
    if wx + ww - 10 - select(1, ImGui.GetItemRectMax(ctx)) - 14 >= need then ImGui.SameLine(ctx, 0, 14) end   -- else its own line
    chg, v = ImGui.Checkbox(ctx, "Categories on the side", PICK.side)
    if chg then PICK.side = v; r.SetExtState(EXT, "pick_side", v and "1" or "0", true) end
    -- two sliders: the icon size (PICK.norm_size) and how strongly a coloured track's colour paints its icon (the
    -- gear's "Icons follow the track colour"; TINT.pct; moved here from the gear menu, the user 2026-10-07: "track icon
    -- slider should be in the track icon menu"). The colour repaints the tracks once, when its drag ends.
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0x34465AFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0x34465AFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab, hue)
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive, hue)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabRounding, 4)
    local sw = math.max(80, math.floor((ImGui.GetContentRegionAvail(ctx) - 110) / 2))
    ImGui.AlignTextToFramePadding(ctx)
    ImGui.TextColored(ctx, MENU.c.muted, "Size"); ImGui.SameLine(ctx, 0, 6)
    ImGui.SetNextItemWidth(ctx, sw)
    local sch, sv = ImGui.SliderInt(ctx, "##pick_size", PICK.size, 28, 96, "%d px")
    if sch then
      sv = PICK.norm_size(sv)
      if sv ~= PICK.size then PICK.size = sv; PICK.lbl = {}; r.SetExtState(EXT, "pick_size", tostring(sv), true) end
    end
    ImGui.SameLine(ctx, 0, 14)
    ImGui.TextColored(ctx, MENU.c.muted, "Colour"); ImGui.SameLine(ctx, 0, 6)
    ImGui.SetNextItemWidth(ctx, sw)
    local tk = TINT.pct()
    local tch, tv = ImGui.SliderInt(ctx, "##tintk", tk, 10, 100, "%d %%")
    if tch then
      tv = math.max(10, math.min(100, math.floor(tv / 5 + 0.5) * 5))
      if tv ~= tk then opt_set("tintk", tostring(tv)) end
    end
    if opt.tips ~= "0" and ImGui.IsItemHovered(ctx) then
      ImGui.SetTooltip(ctx, "How strongly a coloured track paints its icon" .. (opt.tint == "1" and "" or " (the gear: Icons follow the track colour)"))
    end
    if ImGui.IsItemDeactivatedAfterEdit(ctx) and opt.tint == "1" then TINT.pass(true) end
    ImGui.PopStyleVar(ctx, 1)
    ImGui.PopStyleColor(ctx, 4)
    -- the categories: pills that wrap, or a list on the side; the same right-click menus either way
    local cats = pick_cats()
    local cats_s = {}
    local function cat_rect(key, label)
      local px0, py0 = ImGui.GetItemRectMin(ctx)
      local px1, py1 = ImGui.GetItemRectMax(ctx)
      cats_s[#cats_s + 1] = string.format("%s=%s:%d,%d,%d,%d", key, label, math.floor(px0), math.floor(py0), math.floor(px1 - px0), math.floor(py1 - py0))
    end
    local function cat_menu(_, key, on)                           -- the popups' ids by KEY: a row that reshapes under an
      local kind, name = key:match("^(%a):(.*)$")                 -- open menu must not hand it to a neighbour
      if kind == "g" and ImGui.BeginPopupContextItem(ctx, "##gp" .. key) then
        if ImGui.MenuItem(ctx, "New sub-group...") then PICK.ask = { "newsub", name } end
        if ImGui.MenuItem(ctx, "Rename the group...") then PICK.ask = { "rename", name } end
        if ImGui.MenuItem(ctx, "Delete the group") then
          local up = PICK.g_delete(name)                          -- its icons go up a step, its sub-groups too
          if PICK.under(PICK.cat:sub(3), name) and PICK.cat:sub(1, 2) == "g:" then PICK.cat = up and ("g:" .. up) or "" end
        end
        ImGui.EndPopup(ctx)
      elseif kind == "f" and not name:find("/", 1, true) and ImGui.BeginPopupContextItem(ctx, "##fp" .. key) then
        local is_dir = false
        for j = 1, #PICK.dirs do if pick_dir_label(j) == name then is_dir = true end end
        if is_dir and ImGui.MenuItem(ctx, "Remove this folder from the picker") then pick_remove_dir(name) end
        if not is_dir then ImGui.TextDisabled(ctx, "A subfolder of REAPER's icon folder") end
        ImGui.EndPopup(ctx)
      end
    end
    -- where the shown category sits: "on" for it and every group above it; a click on the one shown goes up a step
    -- (from the top: back to All), a click on another shows it
    local function in_path(key) return PICK.cat == key or (key ~= "" and PICK.cat:sub(1, #key + 1) == key .. "/") end
    local function pick_cat(key)
      if PICK.cat == key then
        local kind, path = key:match("^(%a):(.*)$")
        local up = path and PICK.parent(path)
        PICK.cat = up and (kind .. ":" .. up) or ""
      else PICK.cat = key end
    end
    local ci = 0
    if PICK.side then
      if ImGui.BeginChild(ctx, "##side", 150, 0, ImGui.ChildFlags_None, ImGui.WindowFlags_None) then
        local function tree(list, depth)                         -- an indented tree, open along the path shown
          for _, c in ipairs(list) do
            local key, label = c[1], c[2]
            ci = ci + 1
            local on, kids = in_path(key), PICK.kids[key]
            ImGui.PushStyleColor(ctx, ImGui.Col_Text, PICK.cat == key and hue or (on and MENU.c.text or (key:sub(1, 1) == "*" and MENU.c.accent or MENU.c.text)))
            if ImGui.Selectable(ctx, string.rep("   ", depth) .. label .. ((kids and not on) and "  \u{203A}" or "") .. "##cat" .. key, PICK.cat == key) then pick_cat(key) end
            ImGui.PopStyleColor(ctx)
            cat_rect(key, label); cat_menu(ci, key, on)
            if kids and on then tree(kids, depth + 1) end
          end
        end
        tree(cats, 0)
        ImGui.EndChild(ctx)
      end
      ImGui.SameLine(ctx)
    else
      -- the pills wrap; the first row holds the top groups, the second (when the group shown has any below it) the
      -- path to the level listed ("Drums › Cymbals ›", each step a click back to it) and that level's groups
      local avail = ImGui.GetContentRegionAvail(ctx)
      local lx, first = 0, true
      local function pill(key, label, on, crumb)
        ci = ci + 1
        local tw = ImGui.CalcTextSize(ctx, label) + 12
        if not first and lx + tw > avail then lx = 0 elseif not first then ImGui.SameLine(ctx, 0, 4) end
        first = false
        lx = lx + tw + 4
        if crumb then                                            -- a step of the path: plain text, no pill
          ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x00000000)
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, MENU.c.muted)
        else
          ImGui.PushStyleColor(ctx, ImGui.Col_Button, on and hue or 0x283644FF)
          ImGui.PushStyleColor(ctx, ImGui.Col_Text, on and 0x14191EFF or (key:sub(1, 1) == "*" and MENU.c.accent or MENU.c.text))
        end
        local hit = ImGui.SmallButton(ctx, label .. "##cat" .. (crumb and "crumb" or "") .. key)
        ImGui.PopStyleColor(ctx, 2)
        if hit then if crumb then PICK.cat = key else pick_cat(key) end end
        cat_rect(key, label); cat_menu(ci, key, on)
      end
      for _, c in ipairs(cats) do pill(c[1], c[2], in_path(c[1])) end
      local kind, path = PICK.cat:match("^(%a):(.*)$")
      if kind then
        local lkey = PICK.kids[PICK.cat] and PICK.cat or (PICK.parent(path) and (kind .. ":" .. PICK.parent(path)))
        if lkey and PICK.kids[lkey] then                         -- the level to list: the one shown, or the one above it
          first, lx = true, 0
          ImGui.Dummy(ctx, 0, 2)                                 -- a little air: two levels, not one long row
          local steps, a = {}, lkey:sub(3)
          while a do table.insert(steps, 1, a); a = PICK.parent(a) end
          for _, st in ipairs(steps) do pill(kind .. ":" .. st, PICK.leaf(st) .. " \u{203A}", false, true) end
          for _, c in ipairs(PICK.kids[lkey]) do pill(c[1], c[2], in_path(c[1])) end
        end
      end
    end
    local cp = table.concat(cats_s, ";")
    if cp ~= PICK.cats_pub then PICK.cats_pub = cp; r.SetExtState(EXT, "picker_cats", cp, false) end
    -- the icons the other selected tracks wear (a thin outline; the shown track's own is marked in its colour)
    local worn = {}
    for i = 0, r.CountSelectedTracks2(0, true) - 1 do
      local t2 = r.GetSelectedTrack2(0, i, true)
      if t2 ~= tr then local o = TINT.own(t2); if o ~= "" then worn[pick_norm(o):lower()] = true end end
    end
    -- the grid: the icons that pass the category and the search, in a highlight the arrow keys move
    -- (Up / Down always, Left / Right when the search box is not typing) and Enter picks; with the colour follow
    -- on, every icon is drawn in the shown track's colour (a multiply: REAPER's dark icons come out darker than
    -- the real paint, which scales them up)
    local LBL = PICK.size >= 64 and 14 or 0
    local CH = CELL + LBL
    local tintc = 0xFFFFFFFF
    if opt.tint == "1" and has then                               -- the same soft colour as the paint (TINT.soft, 0..255)
      local sr, sg, sb = TINT.soft(cr * 255, cg * 255, cb * 255)
      tintc = MENU.rgba(sr / 255, sg / 255, sb / 255)
    end
    if ImGui.BeginChild(ctx, "##grid", 0, 0, ImGui.ChildFlags_None, ImGui.WindowFlags_None) then
      local cdl = ImGui.GetWindowDrawList(ctx)
      local x0, y0 = ImGui.GetCursorScreenPos(ctx)
      local gavail = ImGui.GetContentRegionAvail(ctx)
      local cols = math.max(1, math.floor(gavail / CELL))
      local needle = PICK.q:lower():gsub("[%s_%-]", "")
      local vis = {}
      for _, e in ipairs(PICK.list) do
        if pick_in_cat(e, PICK.cat) and (needle == "" or e.name:lower():gsub("[%s_%-]", ""):find(needle, 1, true)) then vis[#vis + 1] = e end
      end
      local sig = PICK.cat .. "|" .. needle .. "|" .. #vis
      if sig ~= PICK.sig then PICK.sig = sig; PICK.sel = 1 end
      local mv, kreq = 0, PICK.key_req
      PICK.key_req = nil
      if ImGui.IsKeyPressed(ctx, ImGui.Key_DownArrow) or kreq == "down" then mv = cols
      elseif ImGui.IsKeyPressed(ctx, ImGui.Key_UpArrow) or kreq == "up" then mv = -cols
      elseif (not PICK.qact and ImGui.IsKeyPressed(ctx, ImGui.Key_RightArrow)) or kreq == "right" then mv = 1
      elseif (not PICK.qact and ImGui.IsKeyPressed(ctx, ImGui.Key_LeftArrow)) or kreq == "left" then mv = -1 end
      if (not ImGui.IsAnyItemActive(ctx) and (ImGui.IsKeyPressed(ctx, ImGui.Key_Enter) or ImGui.IsKeyPressed(ctx, ImGui.Key_KeypadEnter))) or kreq == "enter" then PICK.enter = true end
      if mv ~= 0 and #vis > 0 then PICK.sel = math.max(1, math.min(#vis, PICK.sel + mv)) end
      if PICK.enter and vis[PICK.sel] then picker_set(vis[PICK.sel]); if PICK.close_after then open = false end end
      PICK.enter = false
      local cells = {}
      local pad = 6
      for n0, e in ipairs(vis) do
        local n = n0 - 1
        local cx, cy = x0 + (n % cols) * CELL, y0 + (n // cols) * CH
        ImGui.SetCursorScreenPos(ctx, cx, cy)
        ImGui.InvisibleButton(ctx, "##i" .. n0, CELL, CH)
        if n0 == PICK.sel and mv ~= 0 then ImGui.SetScrollHereY(ctx, 0.5) end
        local k = pick_key(e)
        if ImGui.IsRectVisibleEx(ctx, cx, cy, cx + CELL, cy + CH) then
          local hov = ImGui.IsItemHovered(ctx)
          local is_cur = cur ~= "" and (curn == e.full:lower() or (e.src == 1 and e.cat == "" and curn == e.file:lower()))
          local on_sel = not is_cur and (worn[e.full:lower()] or (e.src == 1 and e.cat == "" and worn[e.file:lower()])) and true or false
          if hov or is_cur then
            ImGui.DrawList_AddRectFilled(cdl, cx + 2, cy + 2, cx + CELL - 2, cy + CH - 2, is_cur and MENU.alpha(hue, 0x50) or 0x34465AFF, 4)
          end
          if is_cur then ImGui.DrawList_AddRect(cdl, cx + 2, cy + 2, cx + CELL - 2, cy + CH - 2, hue, 4, 0, 1.5)
          elseif on_sel then ImGui.DrawList_AddRect(cdl, cx + 2, cy + 2, cx + CELL - 2, cy + CH - 2, MENU.c.muted, 4, 0, 1) end
          if n0 == PICK.sel then ImGui.DrawList_AddRect(cdl, cx + 4, cy + 4, cx + CELL - 4, cy + CH - 4, MENU.alpha(MENU.c.text, 0x90), 3, 0, 1) end
          local img = PICK.img[e.full]
          if img == nil then
            local ok, im = pcall(ImGui.CreateImage, e.full)
            img = ok and im or false
            if img then pcall(ImGui.Attach, ctx, img) end
            PICK.img[e.full] = img
          end
          if img then ImGui.DrawList_AddImage(cdl, img, cx + pad, cy + pad, cx + CELL - pad, cy + CELL - pad, 0, 0, 1, 1, tintc)
          else ImGui.DrawList_AddText(cdl, cx + CELL * 0.5 - 4, cy + CELL * 0.5 - 7, MENU.c.dim, "?") end
          if LBL > 0 then                                            -- the name under the icon, cut to the cell
            local lbl = PICK.lbl[e.full]
            if not lbl then
              lbl = e.name
              while #lbl > 1 and ImGui.CalcTextSize(ctx, lbl) > CELL - 6 do lbl = lbl:sub(1, -2) end
              PICK.lbl[e.full] = lbl
            end
            ImGui.DrawList_AddText(cdl, cx + math.floor((CELL - ImGui.CalcTextSize(ctx, lbl)) / 2), cy + CELL - pad + 1, MENU.c.text, lbl)   -- (the track colour over its own fill read badly)
          end
          if PICK.fav[k] then ImGui.DrawList_AddText(cdl, cx + CELL - 11, cy + 1, MENU.c.accent, "*") end
          if hov and opt.tips ~= "0" then ImGui.SetTooltip(ctx, e.name .. (e.cat ~= "" and ("  (" .. e.cat .. ")") or "") .. (PICK.fav[k] and "  favourite" or "") .. (on_sel and "  on a selected track" or "")) end
          if #cells < 60 then cells[#cells + 1] = string.format("%s:%d,%d,%d,%d", e.name, math.floor(cx), math.floor(cy), CELL, CH) end
        end
        if ImGui.IsItemClicked(ctx, 0) then
          PICK.sel = n0
          picker_set(e)
          if ImGui.IsMouseDoubleClicked(ctx, 0) or PICK.close_after then open = false end
        end
        if ImGui.BeginPopupContextItem(ctx, "##cp" .. n0) then   -- right-click: favourite, the groups
          ImGui.TextDisabled(ctx, e.name)
          if ImGui.MenuItem(ctx, PICK.fav[k] and "Unfavourite" or "Favourite") then
            if PICK.fav[k] then PICK.fav[k] = nil else PICK.fav[k] = true end; pick_save_fav()
          end
          local function grp_items(par)                         -- the user's groups at one level; one with groups
            for _, g in ipairs(PICK.gorder) do                 -- under it opens a menu of its own
              if PICK.parent(g) == par then
                local inn, lbl, sub = PICK.groups[g][k] == true, PICK.leaf(g), false
                for _, o in ipairs(PICK.gorder) do if PICK.parent(o) == g then sub = true; break end end
                local function toggle()
                  if inn then PICK.groups[g][k] = nil else PICK.groups[g][k] = true end; pick_save_groups()
                end
                if sub then
                  if ImGui.BeginMenu(ctx, lbl .. "##gm_" .. g) then
                    if ImGui.MenuItem(ctx, (inn and "Remove from " or "Add to ") .. lbl) then toggle() end
                    ImGui.Separator(ctx)
                    grp_items(g)
                    ImGui.EndMenu(ctx)
                  end
                elseif ImGui.MenuItem(ctx, (inn and "Remove from " or "Add to ") .. lbl .. "##gi_" .. g) then toggle() end
              end
            end
          end
          grp_items(nil)
          if ImGui.MenuItem(ctx, "New group with this icon...") then PICK.ask = { "newgroup", k } end
          ImGui.EndPopup(ctx)
        end
      end
      ImGui.SetCursorScreenPos(ctx, x0, y0 + math.ceil(#vis / cols) * CH)
      ImGui.Dummy(ctx, 1, 1)                                     -- so the child scrolls to the last row
      if #vis == 0 then
        ImGui.SetCursorScreenPos(ctx, x0 + 4, y0 + 4)
        ImGui.TextColored(ctx, MENU.c.muted, #PICK.list == 0 and "No icons in the folders" or "No icon matches")
      end
      local cp2 = table.concat(cells, ";")
      if cp2 ~= PICK.cells_pub then PICK.cells_pub = cp2; r.SetExtState(EXT, "picker_cells", cp2, false) end
      local sp = vis[PICK.sel] and vis[PICK.sel].name or ""
      if sp ~= PICK.sel_pub then PICK.sel_pub = sp; r.SetExtState(EXT, "picker_sel", sp, false) end
      ImGui.EndChild(ctx)
    end
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) and not ImGui.IsPopupOpen(ctx, "", ImGui.PopupFlags_AnyPopupId) then open = false end
    ImGui.End(ctx)                                       -- only after a true Begin (ReaImGui ends a hidden window itself)
  end
  if PICK.font then ImGui.PopFont(ctx) end
  ImGui.PopStyleVar(ctx, 5)
  ImGui.PopStyleColor(ctx, 14)
  PICK.first = false
  if not open then picker_close() end
  -- the dialogs, after the frame (a modal dialog inside Begin/End would stall ReaImGui's frame)
  local ask = PICK.ask
  PICK.ask = nil
  if ask and ask[1] == "folder" then
    local ok, d = r.JS_Dialog_BrowseForFolder("A folder of track icons", PICK.dirs[#PICK.dirs] or ICON_ROOT)
    if ok == 1 and d and d ~= "" then pick_add_dir(d) end
  elseif ask and ask[1] == "newgroup" then
    local ok, name = r.GetUserInputs("New icon group", 1, "Name", "")
    local p = ok and PICK.g_new(nil, name, ask[2])
    if p then PICK.cat = "g:" .. p end
  elseif ask and ask[1] == "newsub" then                         -- a group inside the one right-clicked
    local ok, name = r.GetUserInputs("New sub-group in " .. PICK.leaf(ask[2]), 1, "Name", "")
    local p = ok and PICK.g_new(ask[2], name)
    if p then PICK.cat = "g:" .. p end
  elseif ask and ask[1] == "rename" then
    local name = ask[2]
    local ok, nn = r.GetUserInputs("Rename the group", 1, "Name", PICK.leaf(name))
    local np = ok and PICK.g_rename(name, nn)
    if np and PICK.cat:sub(1, 2) == "g:" and PICK.under(PICK.cat:sub(3), name) then PICK.cat = "g:" .. np .. PICK.cat:sub(3 + #name) end
  end
end

-- what the dock calls (PICK is what the load returns); everything else above stays this file's own
PICK.open, PICK.close, PICK.frame, PICK.scan, PICK.set = picker_open, picker_close, picker_frame, picker_scan, picker_set
PICK.key, PICK.load_state, PICK.add_dir, PICK.save_fav, PICK.save_groups = pick_key, pick_load_state, pick_add_dir, pick_save_fav, pick_save_groups
return PICK
