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
local ENV = { mkdir = function(d) r.RecursiveCreateDirectory(d, 0) end, find_imports = find_imports }
-- (find_imports lists *.gumbo.txt; a conversion in progress is ".converting-*.gumbo.txt" in the imports ROOT, which
-- holds no instruments -- walk skips it below)

local function answer(seq, token, status, regions, path, why)
  local cells = C.text_to_cells(path or "")
  if #cells > C.PATH_MAX then cells, status = {}, C.ERR_PATH end
  gw(C.REP_STATUS, status); gw(C.REP_TOKEN, token); gw(C.REP_REGIONS, regions or 0); gw(C.REP_LEN, #cells)
  gw(C.REP_REASON, why or C.WHY_NONE)
  for i = 1, #cells do gw(C.REP_PATH + i - 1, cells[i]) end
  gw(C.REP_SEQ, seq)                                     -- LAST: the reply is complete
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
  if kind ~= C.KIND_IMPORT then return answer(seq, token, C.ERR_KIND) end
  local sfz = (len > 0 and len <= C.PATH_MAX) and C.cells_to_text(cells) or nil
  if not sfz or not sfz:lower():match("%.sfz$") then return answer(seq, token, C.ERR_PATH) end
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
  for _, d in ipairs({ res .. "/Data/track_icons/EON/", res .. "/Data/EON_Gumbo/icons/" }) do
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

gw(C.PROTO, C.PROTO_VERSION)                             -- Gumbo: a helper of this protocol is here
local function loop()
  local now = r.time_precise()
  if (tonumber(r.GetExtState(EXT, "stop")) or 0) > now0 then return end   -- asked to stop: atexit cleans up
  r.SetExtState(EXT, "alive", tostring(now), false)
  gw(C.HB, gr(C.HB) + 1)                                 -- moving = running
  poll()
  if now - tracks_t > 0.25 then tracks_t = now; tracks_tick() end
  r.defer(loop)
end

r.atexit(function()
  gw(C.PROTO, 0)                                         -- Gumbo shows "start the helper" at once
  if sec and cmd and cmd > 0 then r.SetToggleCommandState(sec, cmd, 0); r.RefreshToolbar2(sec, cmd) end
end)
loop()
