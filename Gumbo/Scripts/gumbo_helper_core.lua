-- Copyright (c) 2026 EON Studios (Quaz). All rights reserved. Free to use: see Gumbo_LICENSE.md.
-- gumbo_helper_core.lua -- the Gumbo helper's parts that need no REAPER: the mailbox layout and how text travels
-- through it, where an import goes, the browser list rebuilt with the imports, and a file written without ever
-- losing the old one. Loaded by "Gumbo helper.lua" and "Gumbo - Add a library.lua"; tested offline
-- (.dev_tests/gumbo_helper_test.py). Pure Lua 5.4: io / os only, no reaper.* calls. EON Studios, 2026.
--
-- The mailbox is the EON_GUMBO_HELPER band in Swing_Media_Transfer (.refs/gmem_regions_supplement.tsv, the layout's
-- one written description); the offsets below must match it, and Gumbo's own copy (EON/ReaKit/gb_helper.jsfx-inc) is
-- checked against this file by the test.

local C = {}

C.BAND = 31600000
C.HB, C.PROTO, C.LIBGEN, C.LOCK = 0, 1, 2, 3
C.REQ_SEQ, C.REQ_KIND, C.REQ_TOKEN, C.REQ_LEN, C.REQ_PATH = 16, 17, 18, 19, 20
C.REP_SEQ, C.REP_STATUS, C.REP_TOKEN, C.REP_REGIONS, C.REP_LEN, C.REP_PATH = 1024, 1025, 1026, 1027, 1028, 1029
C.REP_REASON = 2029                                    -- why a conversion failed (C.WHY_*), written before REP_SEQ
C.PATH_MAX = 1000
C.PROTO_VERSION = 1
C.KIND_IMPORT = 1
C.KIND_FAV = 2                                         -- toggle this path in Data/EON_Gumbo/favourites.txt
C.ST_DONE, C.ST_WORKING = 1, 2
C.ERR_KIND, C.ERR_PATH, C.ERR_CONVERT, C.ERR_LIST = -1, -2, -3, -4
-- why a conversion failed: the sound files it points to are missing; the .sfz (or a file it #includes) could not be
-- read; nothing in it Gumbo can play (oscillators, regions a controller switches off, an empty file); sound files
-- Gumbo cannot read (not WAV / FLAC, or damaged)
C.WHY_NONE, C.WHY_MISSING, C.WHY_UNREADABLE, C.WHY_NOTHING, C.WHY_BADAUDIO = 0, 1, 2, 3, 4

-- ── NAME TRACKS: the EON_GUMBO_TRACKS band (.refs/gmem_regions_supplement.tsv; Gumbo's copy: gb_helper.jsfx-inc GBT_*).
-- One slot per track index; Gumbo writes what it plays there, GEN last.
C.TRACKS = { BAND = 31610000, STRIDE = 640, SLOTS = 512, GEN = 0, FAM = 1, R = 2, G = 3, B = 4, NLEN = 5, NAME = 6,
             NAME_MAX = 120, PLEN = 126, PATH = 127, PATH_MAX = 500 }
-- What the helper does to a track for a new record, carefully (the owner, 2026-10-30): each of name, icon and colour
-- changes only while it is empty or still what the helper set last time (kept in the track's P_EXT:EON_Gumbo as
-- three lines: name, icon, colour), so a name, icon or colour the user chose stays. cur / last / want: { name=,
-- icon=, color= } (color a native colour number, 0 = none). Returns the fields to set (nil = leave) and the new memory:
-- a field the helper owns remembers the wanted value, one the user owns keeps the old memory.
function C.track_plan(cur, last, want)
  local set, mem = {}, {}
  for _, k in ipairs({ "name", "icon", "color" }) do
    local empty = (k == "color") and 0 or ""
    -- ours: empty, or still what the helper set. A value the user chose that happens to equal the wanted one stays
    -- the user's (it is not remembered as the helper's, so the next instrument leaves it too)
    local ours = cur[k] == empty or (last[k] ~= empty and cur[k] == last[k])
    if ours and want[k] ~= empty then
      if cur[k] ~= want[k] then set[k] = want[k] end
      mem[k] = want[k]
    else
      mem[k] = last[k]
    end
  end
  return set, mem
end
function C.mem_text(m) return (m.name or "") .. "\n" .. (m.icon or "") .. "\n" .. tostring(m.color or 0) end
function C.mem_parse(s)
  local a, b, c = tostring(s or ""):match("^(.-)\n(.-)\n(.-)$")
  return { name = a or "", icon = b or "", color = tonumber(c) or 0 }
end

-- ── text <-> mailbox cells: one byte per cell (UTF-8 passes through untouched) ──────────────────────────────
function C.text_to_cells(s)
  s = tostring(s or "")
  local t = {}
  for i = 1, #s do t[i] = s:byte(i) end
  return t
end
function C.cells_to_text(t)
  local parts = {}
  for i = 1, #t do
    local v = math.floor(tonumber(t[i]) or 0)
    if v < 0 or v > 255 then return nil end            -- not bytes: a torn or foreign write
    parts[i] = string.char(v)
  end
  return table.concat(parts)
end

-- ── where an import goes ────────────────────────────────────────────────────────────────────────────────────
-- <imports root>/<library folder>_<6 hex of the folder's full path>/<instrument>.gumbo.txt: one folder per source
-- folder (two libraries both called "Programs" never meet), the instrument keeps its own name (the browser shows it).
-- A folder with a generic name ("Programs", "SFZ" ...) is named after the one above it.
local GENERIC = { programs = true, program = true, sfz = true, instruments = true, presets = true, patches = true }
-- names Windows refuses for a file whatever its extension ("aux.gumbo.txt" cannot be made)
local RESERVED = { con = true, prn = true, aux = true, nul = true }
for k = 1, 9 do RESERVED["com" .. k] = true; RESERVED["lpt" .. k] = true end
function C.slug(s)
  -- letters, digits, space, - _ . ( ), and UTF-8 bytes stay; anything Windows forbids in a name becomes _
  s = tostring(s or ""):gsub("[^%w%s%-_%.%(%)\128-\255]", "_"):gsub("^%s+", ""):gsub("[%s%.]+$", "")
  if RESERVED[s:lower()] then s = s .. "_" end
  return s ~= "" and s or "x"
end
function C.hash6(s)                                    -- FNV-1a 32 bit, the low 24 bits as 6 hex digits
  local h = 2166136261
  for i = 1, #s do h = ((h ~ s:byte(i)) * 16777619) & 0xffffffff end
  return string.format("%06x", h & 0xffffff)
end
function C.import_target(sfz_path, imports_root)
  local p = tostring(sfz_path):gsub("\\", "/")
  local dir, file = p:match("^(.*)/([^/]+)$")
  if not dir then dir, file = ".", p end
  local lib = dir:match("([^/]+)$") or "library"
  if GENERIC[lib:lower()] then lib = dir:match("([^/]+)/[^/]+$") or lib end
  local base = file:gsub("%.[Ss][Ff][Zz]$", "")
  local root = tostring(imports_root):gsub("\\", "/"):gsub("/+$", "")
  return root .. "/" .. C.slug(lib) .. "_" .. C.hash6(dir:lower()) .. "/" .. C.slug(base) .. ".gumbo.txt", root .. "/"
    .. C.slug(lib) .. "_" .. C.hash6(dir:lower())
end

-- ── the browser list with the imports ───────────────────────────────────────────────────────────────────────
-- Every line of the old list that is NOT under the imports root stays (our library, the user's own entries); the
-- imports are taken fresh from what is on disk now, so a rebuild is the same whoever runs it (the helper, the Add a
-- library action) and an import deleted by hand drops out. imported = { {path=, head=}, ... } (head = the file's
-- first 2000 bytes). X = gumbo_index.lua.
function C.rebuild_list(X, old_text, imports_root, imported)
  local root = tostring(imports_root):gsub("\\", "/"):gsub("/+$", ""):lower() .. "/"
  local entries = {}
  for _, e in ipairs(X.parse(old_text or "")) do
    if e.path:gsub("\\", "/"):lower():sub(1, #root) ~= root then entries[#entries + 1] = e end
  end
  for _, f in ipairs(imported) do entries[#entries + 1] = X.entry(f.path, f.head) end
  return (X.build(entries))
end

-- ── a text file written whole or not at all; the old one is kept until the new one is in place ───────────────
function C.write_safely(path, text)
  local tmp, bak = path .. ".tmp", path .. ".bak"
  local f = io.open(tmp, "wb")
  if not f then return false, "cannot write " .. tmp end
  f:write(text); f:close()
  local g = io.open(tmp, "rb"); local back = g and g:read("a"); if g then g:close() end
  if back ~= text then os.remove(tmp); return false, "write check failed" end
  local had = io.open(path, "rb")
  if had then
    had:close()
    os.remove(bak)
    local ok, err = os.rename(path, bak)
    if not ok then os.remove(tmp); return false, "cannot move the old file aside: " .. tostring(err) end
  end
  local ok, err = os.rename(tmp, path)
  if not ok then
    if had then os.rename(bak, path) end
    return false, "rename failed: " .. tostring(err)
  end
  if had then os.remove(bak) end
  return true
end

-- the first n bytes of a file ("" when it cannot be read)
function C.head(path, n)
  local f = io.open(path, "rb")
  if not f then return "" end
  local s = f:read(n or 2000) or ""
  f:close()
  return s
end

-- why a conversion with no output failed, from its report (one C.WHY_*)
function C.failure_reason(report)
  if not report then return C.WHY_NOTHING end
  if report.fatal then return C.WHY_UNREADABLE end
  for _, e in ipairs(report.errors or {}) do if tostring(e):find("cannot read", 1, true) then return C.WHY_UNREADABLE end end
  local sk = report.skipped or {}
  local miss, bad = sk.missing_sample or 0, sk.bad_audio or 0
  if miss > 0 and miss >= bad then return C.WHY_MISSING end
  if bad > 0 then return C.WHY_BADAUDIO end
  return C.WHY_NOTHING
end

-- one instrument converted into its import folder. The folder is made only when there is something to put in it, so
-- a failed import leaves nothing behind: the conversion goes to a spare file in the imports root, then (only if it
-- worked) into place with C.write_safely (an earlier copy stays until the new one is in). Returns ok, regions, out,
-- report, why (a C.WHY_*). G = gumbo_sfz.lua; env.mkdir as for C.import_one.
function C.convert_into(G, env, sfz_path, imports_root)
  local out, out_dir = C.import_target(sfz_path, imports_root)
  local root = tostring(imports_root):gsub("\\", "/"):gsub("/+$", "")
  env.mkdir(root)
  local tmp = root .. "/.converting-" .. C.hash6(out:lower()) .. ".gumbo.txt"
  os.remove(tmp)
  local res = G.convert(sfz_path, tmp)
  if not res.ok then os.remove(tmp); return false, 0, nil, res.report, C.failure_reason(res.report) end
  local text = C.head(tmp, 1 << 30)
  os.remove(tmp)
  env.mkdir(out_dir)
  if not C.write_safely(out, text) then return false, 0, nil, res.report, C.WHY_UNREADABLE end
  return true, res.regions, out, res.report, C.WHY_NONE
end

-- ── one import, end to end ──────────────────────────────────────────────────────────────────────────────────
-- G = gumbo_sfz.lua, X = gumbo_index.lua; env = { mkdir = function(dir), find_imports = function(root) -> paths }
-- (REAPER's folder calls, handed in so this stays testable). Returns status, regions, converted path, report, why.
function C.import_one(G, X, env, sfz_path, imports_root, list_path)
  local ok, regions, out, report, why = C.convert_into(G, env, sfz_path, imports_root)
  if not ok then return C.ERR_CONVERT, 0, nil, report, why end
  local st = C.relist(X, env, imports_root, list_path)
  return st, regions, out, report, C.WHY_NONE
end

-- the words for a C.WHY_* (the Add a library summary; Gumbo's face has its own copy of these sentences)
function C.why_text(why)
  return why == C.WHY_MISSING and "its sound files are missing" or why == C.WHY_UNREADABLE and "the file could not be read"
    or why == C.WHY_BADAUDIO and "its sound files are not WAV / FLAC or are damaged" or "nothing in it Gumbo can play"
end

-- the list rebuilt from disk and written; ST_DONE or ERR_LIST
function C.relist(X, env, imports_root, list_path)
  local imported = {}
  for _, p in ipairs(env.find_imports(imports_root)) do imported[#imported + 1] = { path = p, head = C.head(p, 2000) } end
  local ok = C.write_safely(list_path, C.rebuild_list(X, C.head(list_path, 1 << 30), imports_root, imported))
  return ok and C.ST_DONE or C.ERR_LIST
end

-- favourites (2026-11-01): one instrument path a line; a star clicked in Gumbo toggles its path (any case matches).
-- The new text, from the old file's text; the caller writes it with C.write_safely.
function C.fav_toggle(text, path)
  local out, found = {}, false
  for line in (tostring(text or "") .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    if line ~= "" then
      if line:lower() == path:lower() then found = true else out[#out + 1] = line end
    end
  end
  if not found then out[#out + 1] = path end
  return #out > 0 and (table.concat(out, "\n") .. "\n") or ""
end

return C
