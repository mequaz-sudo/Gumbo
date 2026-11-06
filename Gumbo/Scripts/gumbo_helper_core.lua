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
C.DOCK_SEQ, C.DOCK_T, C.DOCK_POS, C.DOCK_FL = 4, 5, 6, 7   -- a double-click on the GUMBO logo (Gumbo writes SEQ last)
C.REQ_SEQ, C.REQ_KIND, C.REQ_TOKEN, C.REQ_LEN, C.REQ_PATH = 16, 17, 18, 19, 20
C.REP_SEQ, C.REP_STATUS, C.REP_TOKEN, C.REP_REGIONS, C.REP_LEN, C.REP_PATH = 1024, 1025, 1026, 1027, 1028, 1029
C.REP_REASON = 2029                                    -- why a conversion failed (C.WHY_*), written before REP_SEQ
C.PATH_MAX = 1000
C.PROTO_VERSION = 1
C.KIND_IMPORT = 1
C.KIND_FAV = 2                                         -- toggle this path in Data/EON_Gumbo/favourites.txt
C.KIND_LOOK = 3                                        -- keep a pad's hand-picked icon / colour in Data/EON_Gumbo/pad_looks.txt
C.KIND_DEFAULTS = 4                                    -- keep the face look for new Gumbos (OPTIONS > USE AS DEFAULT): "typeface|size|screen|icons|colours"
-- the saved look, published in the band for fresh Gumbos (DEF_GEN written LAST; 0 = none saved yet)
C.DEF_GEN, C.DEF_TYPE, C.DEF_SIZE, C.DEF_SCREEN, C.DEF_ICONS, C.DEF_COLS = 8, 9, 10, 11, 12, 13
-- "typeface|size|screen|icons|colours" -> { typeface 0..4, size -3..6, screen 0..2, icons 0..1, colours 0..2 }, or nil
function C.defaults_parse(t)
  local a, b, c, d, e = tostring(t or ""):match("^(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)|(%-?%d+)$")
  if not a then return nil end
  local function clamp(v, lo, hi) v = tonumber(v); return math.max(lo, math.min(hi, v)) end
  return { clamp(a, 0, 4), clamp(b, -3, 6), clamp(c, 0, 2), clamp(d, 0, 1), clamp(e, 0, 2) }
end
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
  local base = file:gsub("%.[Ss][Ff][Zz23]$", "")   -- .sfz, .sf2 or .sf3
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
-- A SoundFont (.sf2, 2026-11-02) is unpacked first (env.sf2 = gumbo_sf2.lua) into its import folder -- its samples
-- and an SFZ bank -- and that SFZ is converted beside them (so its sample paths stay relative to the folder).
-- Each unpack writes its samples into a NEW folder of its own (C.sf2_sub; 2026-11-05, outside audit: a re-import
-- used to overwrite the samples the earlier import still played, and a failed one then deleted them). The earlier
-- import keeps playing until the new instrument file is in place; a failed unpack or conversion removes only the
-- new samples; a finished one removes the earlier import's own samples (never the shared "samples" folder of
-- imports made before 1.1.1). The empty folders stay (Lua cannot remove a folder).
-- a new folder name for one unpack of the SoundFont base (its name, the time, a count if that one is taken)
function C.sf2_sub(out_dir, base, now)
  local n = now or os.time()
  for _ = 1, 1000 do
    local sub = "samples-" .. C.slug(base) .. "-" .. n
    local f = io.open(out_dir .. "/" .. sub .. "/.gumbo", "rb")
    if not f then return sub end
    f:close(); n = n + 1
  end
  return "samples-" .. C.slug(base) .. "-" .. n
end
-- the sample paths an instrument file uses (relative ones only, as written)
function C.sample_paths(text)
  local t = {}
  for p in tostring(text or ""):gmatch("<region> sample=(.-) lokey=") do t[p] = true end
  return t
end
-- a sound's length through REAPER's own reader (env.probe for the converters: an .ogg sample, an SF3's streams --
-- the pure-Lua readers open WAV / FLAC only). r = the reaper table; nil when REAPER cannot open the file
function C.reaper_probe(r)
  return function(path)
    local src = r.PCM_Source_CreateFromFile(path)
    if not src then return nil end
    local len = r.GetMediaSourceLength(src)
    local sr, ch = r.GetMediaSourceSampleRate(src), r.GetMediaSourceNumChannels(src)
    r.PCM_Source_Destroy(src)
    if not len or len <= 0 or not sr or sr <= 0 then return nil end
    return math.floor(len * sr + 0.5), ch or 1, sr
  end
end
function C.convert_into(G, env, sfz_path, imports_root)
  local out, out_dir = C.import_target(sfz_path, imports_root)
  local root = tostring(imports_root):gsub("\\", "/"):gsub("/+$", "")
  env.mkdir(root)
  local tmp_dir = root
  local sub, new_wavs                  -- a SoundFont's new sample folder and what went into it
  local function drop_new()
    for _, nm in ipairs(new_wavs or {}) do os.remove(out_dir .. "/" .. sub .. "/" .. nm) end
    if sub then os.remove(out_dir .. "/" .. sub .. "/.gumbo") end
  end
  if tostring(sfz_path):lower():match("%.sf[23]$") then   -- (.sf3 = MuseScore's compressed SoundFont, 2026-11-05)
    if not env.sf2 then return false, 0, nil, nil, C.WHY_UNREADABLE end
    local base = (tostring(sfz_path):gsub("\\", "/"):match("([^/]+)$") or "bank"):gsub("%.[Ss][Ff][23]$", "")
    sub = C.sf2_sub(out_dir, base)
    env.mkdir(out_dir .. "/" .. sub)
    local mk = io.open(out_dir .. "/" .. sub .. "/.gumbo", "wb")   -- marks the name as taken (C.sf2_sub)
    if mk then mk:write("Gumbo's samples of ", base, ".sf2\n"); mk:close() end
    local xr = env.sf2.extract(sfz_path, out_dir, sub, env.probe)   -- (env.probe: REAPER's reader, for an SF3's .ogg lengths)
    new_wavs = xr.written
    if not xr.ok then
      drop_new()
      -- why: compressed streams that are not Ogg, or ROM samples only -> not playable audio; no zones -> nothing to
      -- play; else unreadable
      local sk = xr.report and xr.report.skipped or {}
      local why = ((sk.sf3_not_ogg or 0) + (sk.rom_sample or 0) > 0) and C.WHY_BADAUDIO
        or (xr.regions == 0 and #(xr.report and xr.report.errors or {}) > 0
            and tostring(xr.report.errors[1]):find("no playable", 1, true)) and C.WHY_NOTHING or C.WHY_UNREADABLE
      return false, 0, nil, xr.report, why
    end
    sfz_path, tmp_dir = xr.sfz, out_dir
  end
  local tmp = tmp_dir .. "/.converting-" .. C.hash6(out:lower()) .. ".gumbo.txt"
  os.remove(tmp)
  local res = G.convert(sfz_path, tmp, { probe = env.probe })   -- (the probe: an .ogg sample's length for the RAM estimate)
  if not res.ok then os.remove(tmp); drop_new(); return false, 0, nil, res.report, C.failure_reason(res.report) end
  local text = C.head(tmp, 1 << 30)
  os.remove(tmp)
  env.mkdir(out_dir)
  local old = sub and C.head(out, 1 << 30) or nil   -- the earlier import of this SoundFont, if any
  if not C.write_safely(out, text) then drop_new(); return false, 0, nil, res.report, C.WHY_UNREADABLE end
  if old then
    -- the earlier import's own samples (its "samples-..." folder), unless the new file uses them too
    local keep = C.sample_paths(text)
    for p in pairs(C.sample_paths(old)) do
      if not keep[p] and p:match("^samples%-[^/]+/[^/]+$") then os.remove(out_dir .. "/" .. p) end
    end
  end
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

-- pad looks (2026-11-05, the owner: "change the icon and color"): one pad a line, "path|section|program|note|icon|family"
-- (the path as the browser lists write it; icon an icon name or "" = automatic; family 0..6 or -1 = automatic). A new
-- line replaces the one with the same path (any case), section, program and note; both automatic = that line goes.
-- The new text, from the old file's text (nil = the line is malformed); the caller writes it with C.write_safely.
function C.look_update(text, line)
  -- a seventh field since the colour wheel: the pad's own colour "rrggbb" (hex), "" or absent = none
  local p, sec, prog, note, icon, fam, rest = line:match("^(.-)|(%-?%d+)|(%-?%d+)|(%-?%d+)|([^|]*)|(%-?%d+)(.*)$")
  if not p or p == "" then return nil end
  local col = rest == "" and "" or rest:match("^|(%x%x%x%x%x%x)$")
  if col == nil and rest ~= "|" then return nil end
  col = col or ""
  local key = p:lower() .. "|" .. sec .. "|" .. prog .. "|" .. note
  local out = {}
  for l in (tostring(text or "") .. "\n"):gmatch("([^\r\n]*)\r?\n") do
    if l ~= "" then
      local lp, ls, lg, ln = l:match("^(.-)|(%-?%d+)|(%-?%d+)|(%-?%d+)|")
      if not (lp and (lp:lower() .. "|" .. ls .. "|" .. lg .. "|" .. ln) == key) then out[#out + 1] = l end
    end
  end
  if icon ~= "" or tonumber(fam) >= 0 or col ~= "" then out[#out + 1] = line end
  return #out > 0 and (table.concat(out, "\n") .. "\n") or ""
end

-- OPEN EMBEDDED IN THE MIXER (2026-11-05, the owner: "gumbo should always open its embedd mcp view"). REAPER's
-- "Default settings for new instances > Show embedded UI in MCP" is bit 4 of the plugin's line in
-- reaper-fxoptions.ini [defcfg] (read at every insert; the first [defcfg] section only; measured 2026-10-01). The
-- file's text with every path in `paths` given bit 4 -- bit 2 (the track panel) taken off, since with both REAPER
-- uses the track panel -- the other bits and every other line kept, a missing line added; returns the new text and
-- how many lines changed. (ReaKit FX's start action does the same for its eight effects.)
function C.embed_defaults_text(txt, paths)
  txt = tostring(txt or "")
  local bom = txt:sub(1, 3) == "\239\187\191" and "\239\187\191" or ""
  txt = txt:sub(#bom + 1)
  local nl = txt:find("\r\n", 1, true) and "\r\n" or (txt == "" and "\r\n" or "\n")
  local lines, sec_at, sec_end, first = {}, nil, nil, false
  for line in ((txt == "" and "" or txt .. (txt:sub(-1) == "\n" and "" or "\n"))):gmatch("(.-)\r?\n") do
    lines[#lines + 1] = line
    local s = line:match("^%[(.-)%]%s*$")
    if s then first = (s == "defcfg" and not sec_at); if first then sec_at = #lines end
    elseif first and line:match("%S") then sec_end = #lines end
  end
  if not sec_at then lines[#lines + 1] = "[defcfg]"; sec_at = #lines end
  sec_end = sec_end or sec_at
  local changed = 0
  for _, p in ipairs(paths) do
    local found = false
    for i = sec_at + 1, #lines do
      if lines[i]:match("^%[") then break end
      local k, v = lines[i]:match("^(.-)=(%-?%d+)%s*$")
      if k == p then
        found = true
        local n = tonumber(v) or 0
        local n2 = n - (math.floor(n / 2) % 2) * 2 + (math.floor(n / 4) % 2 == 0 and 4 or 0)
        if n2 ~= n then lines[i] = p .. "=" .. n2; changed = changed + 1 end
      end
    end
    if not found then table.insert(lines, sec_end + 1, p .. "=4"); sec_end = sec_end + 1; changed = changed + 1 end
  end
  return bom .. table.concat(lines, nl) .. nl, changed
end

return C
