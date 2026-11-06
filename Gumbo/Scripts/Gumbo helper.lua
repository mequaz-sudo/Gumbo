-- Copyright (c) 2026 EON Studios (Quaz). All rights reserved. Free to use: see Gumbo_LICENSE.md.
-- Gumbo helper -- lets Gumbo open any SFZ. A .sfz dropped on Gumbo's window comes here through shared memory; the
-- helper converts it (gumbo_sfz.lua, the one master of Gumbo's SFZ rules) into Gumbo's import folder
-- (REAPER's Data/EON_Gumbo/Imported), adds it to Gumbo's browser list and answers; Gumbo then plays the converted copy.
-- The samples stay where they are: nothing is copied. Without the helper Gumbo still plays its own library and
-- every saved project.
--
-- A background script: run it once to start, run it again to stop. Idle it reads a handful of shared-memory cells
-- per pass. Protocol: the EON_GUMBO_HELPER band in the Swing_Media_Transfer segment (.refs/gmem_regions_supplement.tsv;
-- offsets in gumbo_helper_core.lua). EON Studios, 2026.
local r = reaper
local _, own, sec, cmd = r.get_action_context()
local dir = own:match("^(.*)[\\/]") or "."
local G = dofile(dir .. "/gumbo_sfz.lua")
local SF2 = dofile(dir .. "/gumbo_sf2.lua")      -- SoundFonts: unpacked into an SFZ bank, then converted as one
local X = dofile(dir .. "/gumbo_index.lua")
local C = dofile(dir .. "/gumbo_helper_core.lua")

-- A toggle, GainKit Plus's way: set_action_options(1) ends a running copy on relaunch (its atexit runs), so the
-- running copy stamps a heartbeat (EXT/alive) every pass, and a launch that finds a fresh one, newer than the last
-- stop request, is the user's second press: it asks the running copy to stop and ends at once.
local EXT = "EON_GumboHelper"
local now0 = r.time_precise()
local alive = tonumber(r.GetExtState(EXT, "alive")) or 0
local stop = tonumber(r.GetExtState(EXT, "stop")) or 0
if alive > stop and now0 - alive < 1.0 then
  r.SetExtState(EXT, "stop", tostring(now0), false)
  if sec and cmd and cmd > 0 then r.SetToggleCommandState(sec, cmd, 0); r.RefreshToolbar2(sec, cmd) end
  return
end
if r.set_action_options then r.set_action_options(1) end
if sec and cmd and cmd > 0 then r.SetToggleCommandState(sec, cmd, 1); r.RefreshToolbar2(sec, cmd) end

r.gmem_attach("Swing_Media_Transfer")
local res = r.GetResourcePath():gsub("\\", "/")
local LIST = res .. "/Data/EON_Gumbo/library.txt"
local IMPORTS = res .. "/Data/EON_Gumbo/Imported"
local FAVS = res .. "/Data/EON_Gumbo/favourites.txt"
local LOOKS = res .. "/Data/EON_Gumbo/pad_looks.txt"       -- the pads' hand-picked icons / colours (C.look_update)
local B = C.BAND
local function gr(i) return r.gmem_read(B + i) end
local function gw(i, v) r.gmem_write(B + i, v) end

-- REAPER's folder calls for the core (it stays testable without REAPER)
local function find_imports(root)
  local out = {}
  local function walk(d)
    r.EnumerateFiles(d, -1)                              -- -1: forget REAPER's cached listing of this folder
    local i = 0
    while true do
      local f = r.EnumerateFiles(d, i)
      if not f then break end
      if f:lower():sub(-10) == ".gumbo.txt" and f:sub(1, 1) ~= "." then out[#out + 1] = d .. "/" .. f end
      i = i + 1
    end
    r.EnumerateSubdirectories(d, -1)
    i = 0
    while true do
      local s = r.EnumerateSubdirectories(d, i)
      if not s then break end
      walk(d .. "/" .. s)
      i = i + 1
    end
  end
  walk(root)
  return out
end
local ENV = { mkdir = function(d) r.RecursiveCreateDirectory(d, 0) end, find_imports = find_imports, sf2 = SF2,
              probe = C.reaper_probe(r) }   -- (the length of an .ogg sample / an SF3's streams, through REAPER)
-- (find_imports lists *.gumbo.txt; a conversion in progress is ".converting-*.gumbo.txt" in the imports ROOT, which
-- holds no instruments -- walk skips it below)

-- Gumbo opens embedded in the mixer strip (the owner, 2026-11-05: "gumbo should always open its embedd mcp view"):
-- once per install path REAPER lists for Gumbo_ReaKit.jsfx (reaper-jsfx.ini), its reaper-fxoptions.ini [defcfg]
-- line gets the mixer bit (C.embed_defaults_text; REAPER reads the file at every insert). A path done once is left
-- as the user later sets it (the paths done: the EON_Gumbo "embed_paths" state, "|"-separated).
local function embed_defaults()
  local fh = io.open(res .. "/reaper-jsfx.ini", "rb"); local ini = fh and fh:read("a"); if fh then fh:close() end
  if not ini then return end
  local done = "|" .. (r.GetExtState("EON_Gumbo", "embed_paths") or "") .. "|"
  local paths, seen = {}, {}
  for p in ini:gmatch('NAME%s+"?([^"\r\n]-Gumbo_ReaKit%.jsfx)"?%s') do
    if not seen[p] and not done:find("|" .. p .. "|", 1, true) then seen[p] = true; paths[#paths + 1] = p end
  end
  if #paths == 0 then return end
  local opt = res .. "/reaper-fxoptions.ini"
  fh = io.open(opt, "rb"); local txt = fh and fh:read("a"); if fh then fh:close() end
  if txt == nil and r.file_exists(opt) then return end     -- locked for a moment: next start
  local new, changed = C.embed_defaults_text(txt or "", paths)
  if changed > 0 and not C.write_safely(opt, new) then return end
  r.SetExtState("EON_Gumbo", "embed_paths", (done .. table.concat(paths, "|") .. "|"):gsub("^|+", ""):gsub("|+$", ""), true)
end
embed_defaults()

local function answer(seq, token, status, regions, path, why)
  local cells = C.text_to_cells(path or "")
  if #cells > C.PATH_MAX then cells, status = {}, C.ERR_PATH end
  gw(C.REP_STATUS, status); gw(C.REP_TOKEN, token); gw(C.REP_REGIONS, regions or 0); gw(C.REP_LEN, #cells)
  gw(C.REP_REASON, why or C.WHY_NONE)
  for i = 1, #cells do gw(C.REP_PATH + i - 1, cells[i]) end
  gw(C.REP_SEQ, seq)                                     -- LAST: the reply is complete
end

-- The face look saved as the default for new Gumbos (OPTIONS > USE AS DEFAULT, 2026-11-05): kept in the EON_Gumbo
-- "face_defaults" ext state, published in the band (DEF_* cells, DEF_GEN last) at each start and each save; a fresh
-- Gumbo (no saved state, no look of its own yet) takes it once (gb_face_p2 gbf_defaults_take).
local function publish_defaults(t)
  local d = C.defaults_parse(t)
  if not d then return end
  gw(C.DEF_TYPE, d[1]); gw(C.DEF_SIZE, d[2]); gw(C.DEF_SCREEN, d[3]); gw(C.DEF_ICONS, d[4]); gw(C.DEF_COLS, d[5])
  gw(C.DEF_GEN, gr(C.DEF_GEN) + 1)                       -- LAST: the set is complete
end

-- A request already answered (by an earlier run) is not answered again; one that came while no helper ran is.
local last_seq = gr(C.REP_SEQ)
local function poll()
  local seq = gr(C.REQ_SEQ)
  if seq == 0 or seq == last_seq then return end
  local kind, token, len = gr(C.REQ_KIND), gr(C.REQ_TOKEN), math.floor(gr(C.REQ_LEN))
  local cells = {}
  if len > 0 and len <= C.PATH_MAX then for i = 0, len - 1 do cells[#cells + 1] = gr(C.REQ_PATH + i) end end
  if gr(C.REQ_SEQ) ~= seq then return end                -- written while we read: take it on the next pass
  last_seq = seq
  gw(C.REP_TOKEN, token); gw(C.REP_STATUS, C.ST_WORKING)
  if kind == C.KIND_FAV then                              -- a star: the favourites file, then every browser rereads
    local p = (len > 0 and len <= C.PATH_MAX) and C.cells_to_text(cells) or nil
    if not p then return answer(seq, token, C.ERR_PATH) end
    -- a file that is there but cannot be read is refused, never rewritten as if empty (the stars would be lost)
    local f = io.open(FAVS, "rb"); local old = f and f:read("a"); if f then f:close() end
    if old == nil and r.file_exists(FAVS) then return answer(seq, token, C.ERR_LIST) end
    old = old or ""
    r.RecursiveCreateDirectory(res .. "/Data/EON_Gumbo", 0)
    if not C.write_safely(FAVS, C.fav_toggle(old, p)) then return answer(seq, token, C.ERR_LIST) end
    gw(C.LIBGEN, gr(C.LIBGEN) + 1)
    return answer(seq, token, C.ST_DONE)
  end
  if kind == C.KIND_DEFAULTS then                         -- OPTIONS > USE AS DEFAULT: the face look for new Gumbos
    local t = (len > 0 and len <= C.PATH_MAX) and C.cells_to_text(cells) or nil
    if not (t and C.defaults_parse(t)) then return answer(seq, token, C.ERR_PATH) end
    r.SetExtState("EON_Gumbo", "face_defaults", t, true)
    publish_defaults(t)
    return answer(seq, token, C.ST_DONE)
  end
  if kind == C.KIND_LOOK then                             -- a pad's hand-picked icon / colour: pad_looks.txt (no list change)
    local line = (len > 0 and len <= C.PATH_MAX) and C.cells_to_text(cells) or nil
    if not line then return answer(seq, token, C.ERR_PATH) end
    local f = io.open(LOOKS, "rb"); local old = f and f:read("a"); if f then f:close() end
    if old == nil and r.file_exists(LOOKS) then return answer(seq, token, C.ERR_LIST) end
    local new = C.look_update(old or "", line)
    if not new then return answer(seq, token, C.ERR_PATH) end
    r.RecursiveCreateDirectory(res .. "/Data/EON_Gumbo", 0)
    if not C.write_safely(LOOKS, new) then return answer(seq, token, C.ERR_LIST) end
    return answer(seq, token, C.ST_DONE)
  end
  if kind ~= C.KIND_IMPORT then return answer(seq, token, C.ERR_KIND) end
  local sfz = (len > 0 and len <= C.PATH_MAX) and C.cells_to_text(cells) or nil
  if not sfz or not (sfz:lower():match("%.sfz$") or sfz:lower():match("%.sf[23]$")) then return answer(seq, token, C.ERR_PATH) end
  -- a converter error must not end the helper (Gumbo would wait for a reply that never comes): it is a failed import
  local okc, st, regions, out, _, why = pcall(C.import_one, G, X, ENV, sfz, IMPORTS, LIST)
  if not okc then st, regions, out, why = C.ERR_CONVERT, 0, nil, C.WHY_NOTHING end
  if st == C.ST_DONE then gw(C.LIBGEN, gr(C.LIBGEN) + 1) end   -- the list changed: the browsers reload it
  answer(seq, token, st, regions, out, why)
end

-- NAME TRACKS: a Gumbo tells what it plays on its track (the EON_GUMBO_TRACKS band, C.TRACKS); the track takes the
-- instrument's name, its family's colour and its icon -- each only where it is empty or still what this helper set
-- (C.track_plan; the memory is the track's P_EXT:EON_Gumbo), in one undo point. Records written before this run are
-- left alone (a Gumbo writes again when it loads, switches or moves).
local T = C.TRACKS
local tseen = {}
for idx = 0, T.SLOTS - 1 do tseen[idx] = r.gmem_read(T.BAND + idx * T.STRIDE + T.GEN) end
local function has_gumbo(tr)
  for i = 0, r.TrackFX_GetCount(tr) - 1 do
    local _, nm = r.TrackFX_GetFXName(tr, i, "")
    if nm:find("Gumbo", 1, true) then return true end
  end
  return false
end
local function cells(base, len_at, at, max)
  local n, t = math.max(0, math.min(max, math.floor(r.gmem_read(base + len_at)))), {}
  for i = 0, n - 1 do t[#t + 1] = r.gmem_read(base + at + i) end
  return C.cells_to_text(t) or ""
end
local function icon_file(name)
  -- (EON_Gumbo/gumbo_icons: the Gumbo package's own, 2026-11-04; EON_Gumbo/icons: the 1.0 starter package's)
  for _, d in ipairs({ res .. "/Data/track_icons/EON/", res .. "/Data/EON_Gumbo/gumbo_icons/", res .. "/Data/EON_Gumbo/icons/" }) do
    if r.file_exists(d .. name .. ".png") then return d .. name .. ".png" end
  end
  return ""
end
local function tracks_tick()
  for idx = 0, math.min(r.CountTracks(0), T.SLOTS) - 1 do
    local base = T.BAND + idx * T.STRIDE
    local g = r.gmem_read(base + T.GEN)
    if g > 0 and g ~= tseen[idx] then                   -- -1: Gumbo is writing it (taken on a later pass)
      tseen[idx] = g
      local tr = r.GetTrack(0, idx)
      if tr and has_gumbo(tr) then
        local name, path = cells(base, T.NLEN, T.NAME, T.NAME_MAX), cells(base, T.PLEN, T.PATH, T.PATH_MAX)
        local fam = X.TILES[math.floor(r.gmem_read(base + T.FAM)) + 1] or X.OTHER
        local col = r.ColorToNative(math.floor(r.gmem_read(base + T.R) * 255 + 0.5), math.floor(r.gmem_read(base + T.G) * 255 + 0.5),
                                    math.floor(r.gmem_read(base + T.B) * 255 + 0.5)) | 0x1000000
        if r.gmem_read(base + T.GEN) == g and name ~= "" then
          local _, cname = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)   -- "" when unnamed ("Track 3" is REAPER's)
          local _, cicon = r.GetSetMediaTrackInfo_String(tr, "P_ICON", "", false)
          local cur = { name = cname, icon = cicon, color = math.floor(r.GetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR")) }
          local _, ms = r.GetSetMediaTrackInfo_String(tr, "P_EXT:EON_Gumbo", "", false)
          local ic = icon_file(X.icon(name, path, fam))
          if ic == "" then ic = icon_file(X.FAMILY_ICON[fam] or "keys") end   -- no such file: the family's
          local set, mem = C.track_plan(cur, C.mem_parse(ms), { name = name, icon = ic, color = col })
          if next(set) then
            r.Undo_BeginBlock()
            if set.name then r.GetSetMediaTrackInfo_String(tr, "P_NAME", set.name, true) end
            if set.icon then r.GetSetMediaTrackInfo_String(tr, "P_ICON", set.icon, true) end
            if set.color then r.SetMediaTrackInfo_Value(tr, "I_CUSTOMCOLOR", set.color) end
            r.GetSetMediaTrackInfo_String(tr, "P_EXT:EON_Gumbo", C.mem_text(mem), true)
            r.Undo_EndBlock("Gumbo: track follows the instrument (" .. name .. ")", -1)
            r.TrackList_AdjustWindows(false)
          else
            r.GetSetMediaTrackInfo_String(tr, "P_EXT:EON_Gumbo", C.mem_text(mem), true)
          end
        end
      end
    end
  end
end
local tracks_t = 0

-- DOCK: a double-click on a Gumbo's logo (C.DOCK_*): the ReaKit FX dock's "Gumbo - Dock" tab takes that Gumbo in, or
-- pops it out when it holds it already -- the same show request GainKit Plus writes for the other plugins, to the Gumbo
-- tab's own EXT; the tab is started first when it is closed (its start leaves a request younger than 5 s alone). A
-- track's own chain only (flags 0). A double-click from before this run is not acted on.
local dock_seen = gr(C.DOCK_SEQ)
local function dock_tick()
  local seq = gr(C.DOCK_SEQ)
  if seq == dock_seen then return end
  dock_seen = seq
  local ti, pos, fl = math.floor(gr(C.DOCK_T) + 0.5), math.floor(gr(C.DOCK_POS) + 0.5), math.floor(gr(C.DOCK_FL) + 0.5)
  if fl ~= 0 then return end
  local tr = ti == -1 and r.GetMasterTrack(0) or (ti >= 0 and r.GetTrack(0, ti) or nil)
  if not tr or pos < 0 or pos >= r.TrackFX_GetCount(tr) then return end
  local fg = r.TrackFX_GetFXGUID(tr, pos)
  if not fg then return end
  local DX = "EON_ReaKitDock_gmb"
  r.SetExtState(DX, "show_req", r.GetTrackGUID(tr) .. "|" .. fg .. "|" .. string.format("%.3f", r.time_precise()), false)
  if r.time_precise() - (tonumber(r.GetExtState(DX, "alive")) or 0) < 1.0 then return end   -- the tab is up: it takes it
  local p = dir .. "/Gumbo - Dock.lua"
  if not r.file_exists(p) then return end
  local id = r.AddRemoveReaScript(true, 0, p, true)
  if id and id ~= 0 then r.Main_OnCommand(id, 0) end
end

gw(C.PROTO, C.PROTO_VERSION)                             -- Gumbo: a helper of this protocol is here
publish_defaults(r.GetExtState("EON_Gumbo", "face_defaults"))   -- the saved default look, for fresh Gumbos
local function loop()
  local now = r.time_precise()
  if (tonumber(r.GetExtState(EXT, "stop")) or 0) > now0 then return end   -- asked to stop: atexit cleans up
  r.SetExtState(EXT, "alive", tostring(now), false)
  gw(C.HB, gr(C.HB) + 1)                                 -- moving = running
  poll()
  dock_tick()
  if now - tracks_t > 0.25 then tracks_t = now; tracks_tick() end
  r.defer(loop)
end

r.atexit(function()
  gw(C.PROTO, 0)                                         -- Gumbo shows "start the helper" at once
  if sec and cmd and cmd > 0 then r.SetToggleCommandState(sec, cmd, 0); r.RefreshToolbar2(sec, cmd) end
end)
loop()
