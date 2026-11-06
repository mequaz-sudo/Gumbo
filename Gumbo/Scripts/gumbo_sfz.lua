-- Copyright (c) 2026 EON Studios (Quaz). All rights reserved. Free to use: see Gumbo_LICENSE.md.
-- gumbo_sfz.lua -- Gumbo's SFZ converter: one SFZ instrument (with its #include files) in, one flat, explicit SFZ
-- out that Gumbo reads line by line. THE master copy of Gumbo's SFZ rules: the offline library builder
-- (.dev_tests/gumbo_sfz_convert.py, through lupa) and the Gumbo helper inside REAPER both load this file; nothing
-- else may re-implement them. Pure Lua 5.4, no reaper.* calls.
--
-- Rules: .docs/refs/SFZ_As_Gumbo_Reads_It_2026-10-30.md (sfzformat.com, read 2026-10-30). The output:
--   * one <region> line per playable region, every Gumbo field written in a fixed order, numbers only (note names
--     resolved), inheritance (global > master > group > region), #define and #include already applied;
--   * sample paths relative to the output file (absolute when they cannot be);
--   * loop points read from the WAV 'smpl' chunk (or a FLAC's foreign 'riff' block) when the SFZ leaves them out;
--   * regions that can never sound (missing sample, a CC range the controller's starting value misses, an oscillator
--     sample other than *silence, which stays because it chokes) are left out and counted in the report; opcodes Gumbo v1 does not use are counted, never fatal.
--   * it is still valid SFZ, so the result can be checked by ear in another SFZ player.
--
-- API:  local G = dofile(".../gumbo_sfz.lua")
--       local res = G.convert(sfz_path, out_path [, opts])   -- writes out_path; returns { ok, regions, report, ... }
--         opts.cc_mode = "live" (default: CC gates kept, checked by Gumbo) | "fixed" (regions a CC's start misses dropped)
--         opts.relocate = { from = <folder>, to = <folder>, ext = ".flac" }: a sample under `from` is WRITTEN as the same
--           path under `to` (extension swapped when ext is given) -- the library builder's packaged copy; the audio
--           facts (frames, loops, root) still come from the original file
--         opts.probe = function(path) -> frames, channels, rate: the length of a sound the pure-Lua reader cannot
--           open (.ogg: REAPER plays it, measured 2026-11-05) -- the helper passes REAPER's reader, the offline builder
--           python's -- for the RAM estimate (which decides packing in the player); without it such a sound counts 0
--       G.parse_note(s), G.FIELDS (the output order), G.FORMAT_VERSION
--       G.instrument_files(files, lib_dir) -> which .sfz of a library are instruments (files = { {path=, text=}, ... })
--       G.programs(sfz_path) -> a GM bank's programs ({} for an ordinary instrument); convert one with opts.program

local M = {}
-- 2 (2026-10-30): live controllers. A region may carry up to M.MAX_MODS "mod=T,CC,A,B" tokens after its gates (T:
-- 1 amplitude % / 2 volume dB / 3 pan % / 4 tune cents, each moved by CC with depth A through curve B; 5 / 6
-- crossfade in / out on CC between A and B; 7 / 8 on velocity; 9 / 10 on key; 11..16 the amp envelope's delay /
-- attack / hold / decay / sustain / release (2026-11-05: seconds, or % for the sustain, added at CC 127 through
-- curve B -- read when a note starts, the release again when it is let go; the opcode's own value stays the base);
-- +100 = the "gain" (straight) curve instead of "power"), and the file may carry "// label_cc N name", "// sw_label
-- NOTE name" and "// curve I v0..v127" lines. Gumbo still reads version 1 files (no such lines).
-- Also in 2 (2026-10-31, the owner: "on drum kits can we put the name of the sound on the keyboard?"): "// label_key
-- NOTE name" lines -- the SFZ's own label_keyN, else, for a drum map (one sound per key, the keys' sounds named
-- differently), a name made from each key's sample file. A player that does not know the line skips it (a comment).
M.FORMAT_VERSION = 2
-- 3 (2026-11-02, the owner: banks open "the regular way"): a GM bank in one file stays ONE instrument; every region of a
-- program carries "prog=S,LO,HI" (section, program range) and the file lists "// program S LO HI name" and "// drums S"
-- (the section channel 10 plays). Only bank files are written as 3, so an older Gumbo refuses a bank instead of playing
-- every program at once; ordinary instruments stay 2. Variation banks (2026-11-05) stay format 3: each is a section of
-- its own after the kits, "// bank S N" says which MIDI bank number (bank select, CC0) picks section S; a Gumbo that
-- does not know the line plays the main programs and the kits, and the variations never sound.
M.BANK_FORMAT_VERSION = 3
M.MAX_MODS = 8                       -- (4 until 2026-11-05; Gumbo's GB_MAXMOD is the same number)
local LIVE_T = { amplitude = 1, volume = 2, pan = 3, tune = 4,
                 -- the amp envelope's times on a controller (2026-11-05): live, not folded
                 ampeg_delay = 11,
                 ampeg_attack = 12,
                 ampeg_hold = 13,
                 ampeg_decay = 14,
                 ampeg_sustain = 15,
                 ampeg_release = 16 }

-- ── fields Gumbo writes on every region, in this order, with the default used when the SFZ is silent ──────────
-- kind: "int" whole number, "num" decimal, "note" note number (accepts names), "str" word.
-- Defaults are sfzformat.com's (= sfizz 1.2.3's; ampeg_release 0.001 by the owner's call 2026-10-30, "match sfizz",
-- replacing ARIA's 0.03), except off_mode (fast, but Gumbo fades over off_time so a cut never clicks).
M.FIELDS = {
  { "lokey", "note", 0 }, { "hikey", "note", 127 }, { "pitch_keycenter", "note", 60 }, { "pitch_keytrack", "num", 100 },
  { "lovel", "int", 1 }, { "hivel", "int", 127 },
  { "tune", "num", 0 }, { "transpose", "int", 0 }, { "volume", "num", 0 }, { "pan", "num", 0 },
  { "amp_veltrack", "num", 100 }, { "amp_random", "num", 0 },
  { "ampeg_delay", "num", 0 }, { "ampeg_attack", "num", 0 }, { "ampeg_hold", "num", 0 }, { "ampeg_decay", "num", 0 },
  { "ampeg_sustain", "num", 100 }, { "ampeg_release", "num", 0.001 },
  { "loop_mode", "str", "no_loop" }, { "loop_start", "int", 0 }, { "loop_end", "int", 0 },
  { "offset", "int", 0 }, { "offset_random", "int", 0 }, { "end", "int", -2 },   -- -2 = whole sample (not written by SFZ)
  { "trigger", "str", "attack" }, { "rt_decay", "num", 0 },
  { "seq_length", "int", 1 }, { "seq_position", "int", 1 }, { "lorand", "num", 0 }, { "hirand", "num", 1 },
  { "group", "int", 0 }, { "off_by", "int", 0 }, { "off_mode", "str", "fast" }, { "off_time", "num", 0.006 },
  { "polyphony", "int", 0 }, { "note_polyphony", "int", 0 },
  { "locc64", "int", 0 }, { "hicc64", "int", 127 },
  { "sw_last", "note", -1 }, { "sw_lokey", "note", -1 }, { "sw_hikey", "note", -1 }, { "sw_default", "note", -1 },
}
local FIELD = {}
for i, f in ipairs(M.FIELDS) do FIELD[f[1]] = { kind = f[2], default = f[3], order = i } end
-- recognised and used outside the field list
local SPECIAL = { sample = true, key = true, default_path = true, note_offset = true, octave_offset = true,
                  count = true, sustain_cc = true, sustain_sw = true,
                  -- a header's own level, added to volume (sfizz: global_volume, master_volume, group_volume, dB)
                  global_volume = true, master_volume = true, group_volume = true,
                  -- programs (a GM bank in one file): M.programs splits it; each output holds one program
                  loprog = true, hiprog = true,
                  -- the MIDI bank number(s) a <global> section answers to (Gumbo's SoundFont importer): "// bank"
                  gumbo_bank = true }
local LOOP_MODES = { no_loop = true, one_shot = true, loop_continuous = true, loop_sustain = true }
local TRIGGERS = { attack = true, release = true, release_key = true, first = true, legato = true }

-- ── small helpers ───────────────────────────────────────────────────────────────────────────────────────────
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function dirname(p) return p:match("^(.*)[/\\]") or "." end
local function is_abs(p) return p:match("^%a:[/\\]") or p:match("^[/\\]") end
local function norm_path(p)
  p = p:gsub("\\", "/")
  local drive, rest = p:match("^(%a:)(.*)$")
  local lead = ""
  if drive then lead = drive; p = rest
  elseif p:sub(1, 2) == "//" and p:sub(3, 3) ~= "/" then lead = "/" end   -- a network path (\\server\share) keeps its //
  local abs = p:sub(1, 1) == "/"
  local parts = {}
  for seg in p:gmatch("[^/]+") do
    if seg == ".." then if #parts > 0 and parts[#parts] ~= ".." then parts[#parts] = nil else parts[#parts + 1] = seg end
    elseif seg ~= "." then parts[#parts + 1] = seg end
  end
  return lead .. (abs and "/" or "") .. table.concat(parts, "/")
end
local function join(a, b) if is_abs(b) then return norm_path(b) end; return norm_path(a .. "/" .. b) end
local function exists(p) local f = io.open(p, "rb"); if f then f:close(); return true end; return false end
local function read_all(p) local f = io.open(p, "rb"); if not f then return nil end; local s = f:read("a"); f:close(); return s end

-- a path relative to base_dir when it lies under it, else absolute
local function rel_to(p, base_dir)
  local np, nb = norm_path(p), norm_path(base_dir)
  local lp, lb = np:lower(), nb:lower() .. "/"
  if lp:sub(1, #lb) == lb then return np:sub(#lb + 1) end
  return np
end

-- note name or number -> MIDI number; IPN: c4 = 60; octave_offset shifts the octave numbering
local NOTE = { c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11 }
function M.parse_note(s, octave_offset)
  if s == nil then return nil end
  s = trim(tostring(s))
  local n = tonumber(s)
  if n then return math.floor(n + 0.5) end
  local l, acc, oct = s:lower():match("^([a-g])([#b]?)(%-?%d+)$")
  if not l then return nil end
  local v = NOTE[l] + (acc == "#" and 1 or acc == "b" and -1 or 0)
  return (tonumber(oct) + 1 + (octave_offset or 0)) * 12 + v
end

-- ── audio file facts: frames, channels, rate, first loop (WAV 'smpl'; FLAC STREAMINFO + foreign 'riff' block) ──
local function u16(s, i) local a, b = s:byte(i, i + 1); return a + b * 256 end
local function u32(s, i) local a, b, c, d = s:byte(i, i + 3); return a + b * 256 + c * 65536 + d * 16777216 end
local function u32be(s, i) local a, b, c, d = s:byte(i, i + 3); return ((a * 256 + b) * 256 + c) * 256 + d end
local function u24be(s, i) local a, b, c = s:byte(i, i + 2); return (a * 256 + b) * 256 + c end

local function smpl_loop(chunk)   -- chunk = the smpl body; returns start, end (inclusive) of the first loop
  if #chunk < 36 then return nil end
  local root = u32(chunk, 13)              -- MIDI unity note
  local nloops = u32(chunk, 29)
  if nloops < 1 or #chunk < 36 + 24 then return nil, nil, root end
  return u32(chunk, 36 + 9), u32(chunk, 36 + 13), root
end

function M.audio_info(path)
  local f = io.open(path, "rb")
  if not f then return nil, "missing" end
  local head = f:read(12) or ""
  local info = { frames = 0, channels = 0, rate = 0 }
  if head:sub(1, 4) == "RIFF" and head:sub(9, 12) == "WAVE" then
    while true do
      local ch = f:read(8)
      if not ch or #ch < 8 then break end
      local id, size = ch:sub(1, 4), u32(ch, 5)
      if id == "fmt " or id == "smpl" then
        -- a damaged or truncated file must not stop the converter: read at most 64 KB, check what came back
        local want = math.min(size, 65536)
        local b = f:read(want) or ""
        if #b == want and size > want then f:seek("cur", size - want) end
        if id == "fmt " then
          if #b >= 16 then info.channels = u16(b, 3); info.rate = u32(b, 5); info.block = u16(b, 13); info.bits = u16(b, 15) end
        else
          info.loop_start, info.loop_end, info.root = smpl_loop(b)
        end
      elseif id == "data" then
        info.data_bytes = size; f:seek("cur", size)
      else
        f:seek("cur", size)
      end
      if size % 2 == 1 then f:seek("cur", 1) end
    end
    if info.block and info.block > 0 and info.data_bytes then info.frames = info.data_bytes // info.block end
    info.format = "wav"
  elseif head:sub(1, 4) == "fLaC" then
    f:seek("set", 4)
    while true do
      local bh = f:read(4)
      if not bh or #bh < 4 then break end
      local last, btype, len = bh:byte(1) >= 128, bh:byte(1) % 128, u24be(bh, 2)
      local b = f:read(len) or ""
      if btype == 0 and #b >= 18 then   -- STREAMINFO
        local x = b:byte(11) * 65536 + b:byte(12) * 256 + b:byte(13)
        info.rate = x >> 4
        info.channels = ((x >> 1) & 7) + 1
        local hi4 = b:byte(14) & 15
        info.frames = hi4 * 4294967296 + u32be(b, 15)
      elseif btype == 2 and b:sub(1, 4) == "riff" then   -- foreign metadata (flac --keep-foreign-metadata)
        local body = b:sub(5)
        if body:sub(1, 4) == "smpl" then info.loop_start, info.loop_end, info.root = smpl_loop(body:sub(9)) end
      end
      if last then break end
    end
    info.format = "flac"
  else
    info.format = "other"
  end
  f:close()
  return info
end

-- ── which files of a library are instruments ─────────────────────────────────────────────────────────────────
-- A .sfz that another file pulls in with #include is a piece of an instrument, not one; so is anything under a
-- "modules" or "inc" folder. files = every .sfz / .inc / .sfzh of the library as { path =, text = } (the text only
-- needs its #include lines); an #include is looked up next to the including file, then at lib_dir, among those files.
-- Returns the instruments' paths, sorted. (The library builder's rule since 2026-10-30, moved here from
-- .dev_tests/gumbo_sfz_convert.py so the Gumbo helper uses the same.)
function M.instrument_files(files, lib_dir)
  local known, included = {}, {}
  for _, f in ipairs(files) do known[norm_path(f.path):lower()] = true end
  for _, f in ipairs(files) do
    for inc in tostring(f.text or ""):gmatch('#include%s+"([^"]+)"') do
      for _, base in ipairs({ dirname(f.path), lib_dir }) do
        local q = join(base, inc):lower()
        if known[q] then included[q] = true end
      end
    end
  end
  local out = {}
  for _, f in ipairs(files) do
    local low = norm_path(f.path):lower()
    if low:match("%.sfz$") and not low:find("/modules/", 1, true) and not low:find("/inc/", 1, true) and not included[low] then
      out[#out + 1] = f.path
    end
  end
  table.sort(out)
  return out
end

-- ── stage 1: text with #include pasted in and #define applied, comments stripped ────────────────────────────
-- Returns the text, or nil + error. report.include_* record what happened.
local function strip_comments(t)
  t = t:gsub("/%*.-%*/", " ")            -- block comments (some players accept them)
  t = t:gsub("//[^\n]*", "")
  return t
end

local function expand(path, report, defines, depth, stack)
  if depth > 16 then report.errors[#report.errors + 1] = "include depth over 16 at " .. path; return "" end
  local key = norm_path(path):lower()
  if stack[key] then report.errors[#report.errors + 1] = "include loop at " .. path; return "" end
  local raw = read_all(path)
  if not raw then report.errors[#report.errors + 1] = "cannot read " .. path; report.fatal = true; return nil end
  if raw:sub(1, 3) == "\239\187\191" then raw = raw:sub(4) end      -- UTF-8 BOM
  raw = raw:gsub("\r\n", "\n"):gsub("\r", "\n")
  raw = strip_comments(raw)
  stack[key] = true
  local out = {}
  for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
    local name, val = line:match("^%s*#define%s+(%$[%w_]+)%s+(.-)%s*$")
    if name then
      defines[name] = val
    else
      -- apply defines (longest names first so $A does not eat $AB)
      if next(defines) and line:find("%$") then
        local names = {}
        for k in pairs(defines) do names[#names + 1] = k end
        table.sort(names, function(a, b) return #a > #b end)
        for _, k in ipairs(names) do line = line:gsub((k:gsub("%$", "%%$")), (defines[k]:gsub("%%", "%%%%"))) end
      end
      -- an #include may also sit after opcodes on the same line (a combined GM bank: '<master> loprog=0 ...
      -- master_label=... #include "Melodic/001-....sfz"'): the text before it stays on its own line, then the file
      local pre, inc, post = line:match('^(.-)#include%s+"([^"]+)"(.*)$')
      if inc and not pre:match("^%s*$") then
        out[#out + 1] = pre
        line = '#include "' .. inc .. '"' .. post
      end
      inc = line:match('^%s*#include%s+"([^"]+)"')
      if inc then
        local p = join(dirname(path), inc)
        if not exists(p) and report.top_dir then
          local p2 = join(report.top_dir, inc)
          if exists(p2) then p = p2; report.include_from_top = (report.include_from_top or 0) + 1 end
        end
        report.includes = (report.includes or 0) + 1
        local sub = expand(p, report, defines, depth + 1, stack)
        out[#out + 1] = sub or ""
      elseif line:match("^%s*#include") then
        report.errors[#report.errors + 1] = "bad #include line: " .. trim(line); report.fatal = true
      else
        out[#out + 1] = line
      end
    end
  end
  stack[key] = nil
  return table.concat(out, "\n")
end

-- ── stage 2: tokens. Headers <name>; opcodes name=value where a value runs to the next opcode, header or line end
-- (so sample paths may hold spaces). ──────────────────────────────────────────────────────────────────────────
local function tokenize(text)
  local toks = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    local i, n = 1, #line
    while i <= n do
      local s, e, h = line:find("^%s*<([%w_]+)>", i)
      if s then
        toks[#toks + 1] = { h = h:lower() }; i = e + 1
      else
        local s2, e2, k = line:find("^%s*([%w_]+)%s*=", i)
        if s2 then
          -- the value ends where the next " name=" or "<header>" starts
          local rest = line:sub(e2 + 1)
          local stop = #rest + 1
          local a = rest:find("%s+[%w_]+%s*=")
          local b = rest:find("<[%w_]+>")
          if a and a < stop then stop = a end
          if b and b < stop then stop = b end
          toks[#toks + 1] = { k = k:lower(), v = trim(rest:sub(1, stop - 1)) }
          i = e2 + stop
        else
          local s3, e3 = line:find("^%s*%S+", i)
          if not s3 then break end
          toks[#toks + 1] = { junk = trim(line:sub(s3, e3)) }; i = e3 + 1
        end
      end
    end
  end
  return toks
end

-- ── stage 3: regions with inheritance ────────────────────────────────────────────────────────────────────────
local function copy(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end

local function collect(toks, report)
  local control, global, master, group, region = {}, {}, {}, {}, nil
  local cur = nil                    -- the table opcodes go into
  local part = 0                     -- which <global> section a region sits under (a combined GM bank: melodic, drums)
  local regions, curves = {}, {}
  local function close_region() if region then regions[#regions + 1] = region; region = nil end end
  for _, t in ipairs(toks) do
    if t.h then
      close_region()
      local h = t.h
      -- a later <control> applies to the regions AFTER it (VSCO 2's keyswitch instruments move default_path halfway
      -- through): a fresh copy, so the regions before keep the one they were read under (found 2026-10-30)
      if h == "control" then control = copy(control); cur = control
      elseif h == "global" then global = {}; master = {}; group = {}; cur = global; part = part + 1
      elseif h == "master" then master = {}; group = {}; cur = master
      elseif h == "group" then group = {}; cur = group
      elseif h == "curve" then cur = {}; curves[#curves + 1] = cur   -- curve_index + vNNN points (applied after all)
      elseif h == "region" then
        region = {}
        for k, v in pairs(global) do region[k] = v end
        for k, v in pairs(master) do region[k] = v end
        for k, v in pairs(group) do region[k] = v end
        region._control = control
        region._part = part
        cur = region
      else
        report.headers_skipped[h] = (report.headers_skipped[h] or 0) + 1
        cur = nil                     -- <effect>, <midi>, <sample>: their opcodes are not region opcodes
      end
    elseif t.k then
      if cur then
        cur[t.k] = t.v
        -- key= is lokey + hikey + root at the SAME level, so a region's key beats a group's lokey
        if t.k == "key" then cur.lokey = t.v; cur.hikey = t.v; cur.pitch_keycenter = t.v end
      end
    elseif t.junk then
      report.junk = (report.junk or 0) + 1
    end
  end
  close_region()
  return regions, control, curves
end

-- ── stage 4: one region -> Gumbo's explicit fields ───────────────────────────────────────────────────────────
local function num(v) if v == nil then return nil end; return tonumber(v) end

-- a CC Gumbo does not play sits at its starting value: set_ccN (0-127), else set_hdccN (0-1), else 0
local function cc_reaches(control, n, lo, hi)
  local start = tonumber(control["set_cc" .. n])
  if start == nil then local hd = tonumber(control["set_hdcc" .. n]); start = hd and hd * 127 or 0 end
  return start >= lo and start <= hi
end

-- ── controller-driven opcodes, taken at the controllers' starting values ──────────────────────────────────────
-- Gumbo plays a controller live for CC7 / CC11 (volume, expression), CC64, the loccN/hiccN gates, and (format 2) the
-- amplitude / volume / pan / tune opcodes and, since 2026-11-05, the amp envelope's times (LIVE_T below, while a mod
-- slot is free). Every other "<opcode>_onccN" (or the older "<opcode>_ccN") is folded in at the CC's starting value,
-- as sfizz would play it before anyone moves the controller (sfizz 1.2.3: RegionStateful.cpp, ModId.cpp -- amplitude
-- multiplies, the rest add; Curve.cpp -- curves). A library's "Extra mics" set to 0 silences those regions; its
-- tuning control at 63 tunes.
local CC_DEFAULT = { [7] = 100 / 127, [10] = 0.5, [11] = 1 }   -- MIDI defaults (sfizz's CC7 = 100 measured)
-- family pattern -> the field it moves, how, and the prefix of its curve opcode (<prefix>_curveccN)
local CC_MODS = {
  { "^amplitude_oncc(%d+)$", "amplitude", "mul", "amplitude" }, { "^amplitude_cc(%d+)$", "amplitude", "mul", "amplitude" },
  { "^volume_oncc(%d+)$", "volume", "add", "volume" }, { "^gain_oncc(%d+)$", "volume", "add", "volume" },
  { "^gain_cc(%d+)$", "volume", "add", "volume" },
  { "^pan_oncc(%d+)$", "pan", "add", "pan" }, { "^pan_cc(%d+)$", "pan", "add", "pan" },
  { "^tune_oncc(%d+)$", "tune", "add", "tune" }, { "^tune_cc(%d+)$", "tune", "add", "tune" },
  { "^pitch_oncc(%d+)$", "tune", "add", "pitch" }, { "^pitch_cc(%d+)$", "tune", "add", "pitch" },
  { "^amp_veltrack_oncc(%d+)$", "amp_veltrack", "add", "amp_veltrack" },
  -- offset and region delay follow the controller in a straight line: sfizz reads no curve for them
  -- (RegionStateful.cpp sampleOffset / regionDelay; delay_curveccN belongs to ampeg_delay there)
  { "^offset_oncc(%d+)$", "offset", "add", nil }, { "^offset_cc(%d+)$", "offset", "add", nil },
  { "^delay_oncc(%d+)$", "ampeg_delay", "add", nil }, { "^delay_cc(%d+)$", "ampeg_delay", "add", nil },
}
for _, x in ipairs({ "delay", "attack", "hold", "decay", "sustain", "release" }) do
  CC_MODS[#CC_MODS + 1] = { "^ampeg_" .. x .. "_oncc(%d+)$", "ampeg_" .. x, "add", "ampeg_" .. x }
  CC_MODS[#CC_MODS + 1] = { "^ampeg_" .. x .. "cc(%d+)$", "ampeg_" .. x, "add", "ampeg_" .. x }
end
local function cc_mod_of(k)
  for _, m in ipairs(CC_MODS) do local n = k:match(m[1]); if n then return m, tonumber(n) end end
  return nil
end
local function is_cc_aux(k)          -- opcodes these modulations read (curves), or handled here (amplitude, delay)
  return k == "amplitude" or k == "delay" or k:match("_curvecc%d+$") ~= nil
end
-- the crossfades (format 2): xfin/xfout on a CC, on velocity, on key, and the curve each uses
local function is_xf(k)
  return k:match("^xfin_locc%d+$") ~= nil or k:match("^xfin_hicc%d+$") ~= nil
    or k:match("^xfout_locc%d+$") ~= nil or k:match("^xfout_hicc%d+$") ~= nil
    or k == "xfin_lovel" or k == "xfin_hivel" or k == "xfout_lovel" or k == "xfout_hivel"
    or k == "xfin_lokey" or k == "xfin_hikey" or k == "xfout_lokey" or k == "xfout_hikey"
    or k == "xf_cccurve" or k == "xf_velcurve" or k == "xf_keycurve"
end
-- ── the tone filter, its envelope and the LFOs (2026-11-03) ─────────────────────────────────────────────────────
-- Written as three optional region tokens (an older Gumbo skips them and plays the region unfiltered):
--   fil=TYPE,CUTOFF,RES,KEYTRACK,KEYCENTER,VELTRACK,RANDOM,CC,CCDEPTH   (TYPE as gb_sfz GBR_FTYPE: 1 lpf_1p 2 hpf_1p
--       3 lpf_2p 4 hpf_2p 5 bpf_2p 6 brf_2p 7 lpf_4p 8 hpf_4p; CC 0 = none)
--   feg=DELAY,ATTACK,HOLD,DECAY,SUSTAIN%,RELEASE,DEPTH,VEL2DEPTH,VEL2ATTACK,VEL2DECAY,VEL2RELEASE
--   lfo=SLOT,WAVE,FREQ,DEPTH,DELAY,FADE,CC1DEPTH   (slot 0 pitch cents, 1 amp dB, 2 filter cents; wave 0 sine, 1 triangle)
--   vel=POW,VEL2ATTACK,VEL2DECAY,VEL2RELEASE   (2026-11-04: amp_velpow -- Gumbo's own opcode, gain = (v/127)^POW, what a
--       SoundFont's velocity-to-attenuation modulator is -- and sfizz's ampeg_vel2attack / decay / release, seconds added
--       at velocity 127)
--   peg=DELAY,ATTACK,HOLD,DECAY,SUSTAIN%,RELEASE,DEPTH,VEL2DEPTH,VEL2ATTACK,VEL2DECAY,VEL2RELEASE   (2026-11-05: the pitch
--       envelope, pitcheg_* in cents -- an 808's drop, a brass scoop; a SoundFont's modEnvToPitch; a region needs no
--       filter for it)
--   keg=AHOLD,ADECAY,FHOLD,FDECAY   (2026-11-05: key-scaled envelope times -- Gumbo's own opcodes ampeg_hold_keytrack,
--       ampeg_decay_keytrack, fileg_hold_keytrack, fileg_decay_keytrack, timecents per key: the time x
--       2^(k x (60 - key) / 1200), a positive k ringing the low keys longer, key 60 unchanged. What a SoundFont's
--       keynumToVolEnvHold / Decay and keynumToModEnvHold / Decay generators say -- a piano's low notes ring longer;
--       SFZ has no opcode for it, so other players ignore these four)
--   bend=UP,DOWN   (2026-11-05: bend_up / bend_down in cents, written only when the SFZ sets either -- a region without
--       it bends over the range MIDI's RPN 0 set on its channel, else Gumbo's SETTINGS knob; bend_step / bend_smooth
--       stay counted)
-- Read from SFZ v1 (fil_*, cutoff, resonance, fileg_*, pitchlfo_* / amplfo_* / fillfo_*) and the v2 LFOs (lfoN_freq /
-- delay / fade / wave and their pitch / volume / cutoff targets). Rules: sfizz's (Research
-- .docs/research/Gumbo_Tone_Filter_Research_2026-11-03.md).
local FIL_TYPE = { lpf_1p = 1, hpf_1p = 2, lpf_2p = 3, hpf_2p = 4, bpf_2p = 5, brf_2p = 6, lpf_4p = 7, hpf_4p = 8,
                   lpf_2p_sv = 3, hpf_2p_sv = 4, bpf_2p_sv = 5, brf_2p_sv = 6,
                   lpf_6p = 7, hpf_6p = 8, bpf_1p = 5, brf_1p = 6 }   -- (the last four: the nearest Gumbo has)
local FIL_NEAR = { lpf_6p = true, hpf_6p = true, bpf_1p = true, brf_1p = true }
local SHAPE_KEYS = { fil_type = true, cutoff = true, resonance = true, fil_keytrack = true, fil_keycenter = true,
                     fil_veltrack = true, fil_random = true, fileg_delay = true, fileg_attack = true, fileg_hold = true,
                     fileg_decay = true, fileg_sustain = true, fileg_release = true, fileg_depth = true,
                     fileg_vel2depth = true, fileg_vel2attack = true, fileg_vel2decay = true, fileg_vel2release = true,
                     amp_velpow = true, ampeg_vel2attack = true, ampeg_vel2decay = true, ampeg_vel2release = true,
                     pitcheg_delay = true, pitcheg_attack = true, pitcheg_hold = true, pitcheg_decay = true,
                     pitcheg_sustain = true, pitcheg_release = true, pitcheg_depth = true, pitcheg_vel2depth = true,
                     pitcheg_vel2attack = true, pitcheg_vel2decay = true, pitcheg_vel2release = true,
                     ampeg_hold_keytrack = true, ampeg_decay_keytrack = true, fileg_hold_keytrack = true, fileg_decay_keytrack = true,
                     bend_up = true, bend_down = true }
for _, t in ipairs({ "pitchlfo", "amplfo", "fillfo" }) do
  for _, x in ipairs({ "freq", "depth", "delay", "fade" }) do SHAPE_KEYS[t .. "_" .. x] = true end
end
local function is_shape(k)
  return SHAPE_KEYS[k] or k:match("^cutoff_oncc%d+$") ~= nil or k:match("^cutoff_cc%d+$") ~= nil
    or k:match("^[a-z]+lfo_depthcc1$") ~= nil or k:match("^[a-z]+lfo_depth_oncc1$") ~= nil
    or k:match("^lfo%d+_freq$") ~= nil or k:match("^lfo%d+_delay$") ~= nil or k:match("^lfo%d+_fade$") ~= nil
    or k:match("^lfo%d+_wave$") ~= nil or k:match("^lfo%d+_pitch$") ~= nil or k:match("^lfo%d+_volume$") ~= nil
    or k:match("^lfo%d+_cutoff$") ~= nil or k:match("^lfo%d+_pitch_oncc1$") ~= nil
    or k:match("^lfo%d+_volume_oncc1$") ~= nil or k:match("^lfo%d+_cutoff_oncc1$") ~= nil
end
M.is_shape = is_shape
-- the region's filter / envelope / LFO tokens ({ fil = "...", feg = "...", lfo = { "...", ... } }), or nil
local function shape_of(r, oo, report)
  local function fmtn(v)
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return (string.format("%.6f", v):gsub("0+$", ""):gsub("%.$", ""))
  end
  local function n(k, d) local v = tonumber(r[k]); if v == nil or v ~= v or v == math.huge or v == -math.huge then return d end; return v end
  local out = {}
  local cut = n("cutoff", nil)
  if cut and cut > 0 then
    local ty = tostring(r.fil_type or "lpf_2p"):lower()
    local code = FIL_TYPE[ty]
    if not code then report.ignored["fil_type=" .. ty] = (report.ignored["fil_type=" .. ty] or 0) + 1
    else
      if FIL_NEAR[ty] then report.filter_nearest = (report.filter_nearest or 0) + 1 end
      local cc, ccd = 0, 0
      local ks = {}
      for k, _ in pairs(r) do local c = k:match("^cutoff_oncc(%d+)$") or k:match("^cutoff_cc(%d+)$"); if c then ks[#ks + 1] = tonumber(c) end end
      table.sort(ks)
      if ks[1] and ks[1] >= 1 and ks[1] <= 127 then
        cc = ks[1]; ccd = n("cutoff_oncc" .. cc, nil) or n("cutoff_cc" .. cc, 0)
        if #ks > 1 then report.cutoff_cc_dropped = (report.cutoff_cc_dropped or 0) + #ks - 1 end
      end
      local kc = r.fil_keycenter ~= nil and M.parse_note(r.fil_keycenter, oo) or 60
      out.fil = table.concat({ code, fmtn(math.min(20000, cut)), fmtn(n("resonance", 0)), fmtn(n("fil_keytrack", 0)),
                               kc or 60, fmtn(n("fil_veltrack", 0)), fmtn(n("fil_random", 0)), cc, fmtn(ccd) }, ",")
      local d, vd = n("fileg_depth", 0), n("fileg_vel2depth", 0)
      if d ~= 0 or vd ~= 0 then
        out.feg = table.concat({ fmtn(n("fileg_delay", 0)), fmtn(n("fileg_attack", 0)), fmtn(n("fileg_hold", 0)),
                                 fmtn(n("fileg_decay", 0)), fmtn(n("fileg_sustain", 100)), fmtn(n("fileg_release", 0.001)),
                                 fmtn(d), fmtn(vd), fmtn(n("fileg_vel2attack", 0)), fmtn(n("fileg_vel2decay", 0)),
                                 fmtn(n("fileg_vel2release", 0)) }, ",")
      end
    end
  end
  -- the pitch envelope (2026-11-05): pitcheg_* as feg=, the depths in cents; written with or without a filter
  local pd, pvd = n("pitcheg_depth", 0), n("pitcheg_vel2depth", 0)
  if pd ~= 0 or pvd ~= 0 then
    out.peg = table.concat({ fmtn(n("pitcheg_delay", 0)), fmtn(n("pitcheg_attack", 0)), fmtn(n("pitcheg_hold", 0)),
                             fmtn(n("pitcheg_decay", 0)), fmtn(n("pitcheg_sustain", 100)), fmtn(n("pitcheg_release", 0.001)),
                             fmtn(pd), fmtn(pvd), fmtn(n("pitcheg_vel2attack", 0)), fmtn(n("pitcheg_vel2decay", 0)),
                             fmtn(n("pitcheg_vel2release", 0)) }, ",")
  end
  -- key-scaled hold and decay times (2026-11-05): Gumbo's own opcodes, timecents a key
  local kah, kad, kfh, kfd = n("ampeg_hold_keytrack", 0), n("ampeg_decay_keytrack", 0), n("fileg_hold_keytrack", 0), n("fileg_decay_keytrack", 0)
  if kah ~= 0 or kad ~= 0 or kfh ~= 0 or kfd ~= 0 then
    out.keg = table.concat({ fmtn(kah), fmtn(kad), fmtn(kfh), fmtn(kfd) }, ",")
  end
  -- the bend range (2026-11-05): only when the SFZ says; the other side takes SFZ's default (200 / -200)
  if r.bend_up ~= nil or r.bend_down ~= nil then
    out.bend = fmtn(n("bend_up", 200)) .. "," .. fmtn(n("bend_down", -200))
  end
  -- velocity on the loudness curve and the amp envelope's times
  local vp, va, vdc, vr = n("amp_velpow", 0), n("ampeg_vel2attack", 0), n("ampeg_vel2decay", 0), n("ampeg_vel2release", 0)
  if vp > 0 or va ~= 0 or vdc ~= 0 or vr ~= 0 then
    out.vel = table.concat({ fmtn(math.max(0, vp)), fmtn(va), fmtn(vdc), fmtn(vr) }, ",")
  end
  -- the LFOs: v1 first (pitchlfo / amplfo / fillfo), then a v2 LFO fills a slot still free
  local slots = {}
  local function cc1(base) return n(base .. "_depthcc1", nil) or n(base .. "_depth_oncc1", 0) end
  for s, base in ipairs({ "pitchlfo", "amplfo", "fillfo" }) do
    local f, dp, c1 = n(base .. "_freq", 0), n(base .. "_depth", 0), cc1(base)
    if f > 0 and (dp ~= 0 or c1 ~= 0) then
      slots[s - 1] = table.concat({ s - 1, 0, fmtn(f), fmtn(dp), fmtn(n(base .. "_delay", 0)), fmtn(n(base .. "_fade", 0)), fmtn(c1) }, ",")
    end
  end
  local ids = {}
  for k, _ in pairs(r) do local i = k:match("^lfo(%d+)_freq$"); if i then ids[#ids + 1] = i end end
  table.sort(ids, function(a, b) return tonumber(a) < tonumber(b) end)
  for _, i in ipairs(ids) do
    local p = "lfo" .. i .. "_"
    local f = n(p .. "freq", 0)
    local w = n(p .. "wave", 0)               -- SFZ v2: 0 triangle (the default, measured against sfizz), 1 sine;
    local wave = (w == 0) and 1 or 0          -- the other shapes (pulse, square, ramps) play as a sine here
    if f > 0 then
      for s, tgt in ipairs({ "pitch", "volume", "cutoff" }) do
        local dp, c1 = n(p .. tgt, 0), n(p .. tgt .. "_oncc1", 0)
        if dp ~= 0 or c1 ~= 0 then
          if slots[s - 1] then report.lfo_dropped = (report.lfo_dropped or 0) + 1
          else
            slots[s - 1] = table.concat({ s - 1, wave, fmtn(f), fmtn(dp), fmtn(n(p .. "delay", 0)), fmtn(n(p .. "fade", 0)), fmtn(c1) }, ",")
          end
        end
      end
    end
  end
  out.lfo = {}
  for s = 0, 2 do if slots[s] then out.lfo[#out.lfo + 1] = slots[s] end end
  if not out.fil and not out.feg and #out.lfo == 0 and not out.vel and not out.peg and not out.keg and not out.bend then return nil end
  return out
end

-- names the player shows (format 2): a controller's name, a keyswitch's name
local function is_label(k) return k:match("^label_cc%d+$") ~= nil or k:match("^label_key%d+$") ~= nil or k == "sw_label" end

-- a drum key's name from its sample file: "Snare2-HitSN_v1_rr1_Sum.flac" -> "Snare2 Hit SN". Layer, round-robin, mic
-- and dynamic tags go; words split at - _ spaces, at a lower-to-upper change and before a number; each word capitalised.
local DROP_TAG = { sum = true, mid = true, close = true, room = true, oh = true, ovh = true, mono = true, stereo = true,
                   ppp = true, pp = true, p = true, mp = true, mf = true, f = true, ff = true, fff = true }
local function key_name_from_file(path)
  local b = (path:match("([^/\\]+)$") or path):gsub("%.[^.]+$", "")
  b = b:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2")
  local words = {}
  for w in b:gmatch("[^%s_%-%.]+") do
    local lw = w:lower()
    if not (DROP_TAG[lw] or lw:match("^v%d+$") or lw:match("^rr%d+$") or lw:match("^vl%d+$")) then
      words[#words + 1] = (w:sub(1, 1):upper() .. w:sub(2)):gsub("(%a)(%d+)$", "%1 %2")
    end
  end
  -- a leading number of four or more digits is a file index ("0816 Std Kick"), not a name: dropped when a name
  -- follows it (the owner, 2026-11-05: "do we have to keep the number in front? makes the name longer"). A short one
  -- stays: "808 Kick", "909 Snare" are names.
  if #words > 1 and words[1]:match("^%d%d%d%d+$") then table.remove(words, 1) end
  return table.concat(words, " "):sub(1, 24)
end
-- the stem two keys of one pitched instrument share ("Piano_C4_v1" and "Piano_D4_v1" -> "piano"): no digits, no
-- note names, no tags
local function key_stem(name)
  local w = {}
  for t in name:lower():gmatch("%S+") do
    if not (t:match("^%d+$") or t:match("^[a-g][#b]?%-?%d*$")) then w[#w + 1] = (t:gsub("%d", "")) end
  end
  return table.concat(w, " ")
end
-- names for the keys of a drum map, { [note] = name }: a single-key recording names its key; a recording stretched over
-- a few keys (a GM kit's kick on 35 and 36, an orchestra kit's timpani over 13) names every key it covers that no
-- single-key recording took (2026-11-05, the owner: the Standard kit's kick had no pad). Empty when the instrument
-- looks pitched (one recording spread over several keys, or every key's file the same instrument at another pitch)
-- -- unless `kit` says the file declares it a drum kit (a SoundFont's bank 128): then the guess is skipped; a marching
-- bass line's five drums, "MBass-2 hit" to "MBass-6 hit", are a kit, not a scale.
local function drum_key_names(outs, kit)
  local names, keys, single, attack, spans = {}, 0, 0, 0, {}
  for _, o in ipairs(outs) do
    if o.trigger == "attack" and o.sample ~= "*silence" and type(o.lokey) == "number" and type(o.hikey) == "number" then
      attack = attack + 1
      if o.lokey == o.hikey then
        single = single + 1
        if names[o.lokey] == nil then
          local nm = key_name_from_file(o.sample)
          if nm ~= "" then names[o.lokey] = nm; keys = keys + 1 end
        end
      elseif o.lokey < o.hikey then
        spans[#spans + 1] = o
      end
    end
  end
  if not kit then
    local stems, ns = {}, 0
    for _, nm in pairs(names) do local st = key_stem(nm); if not stems[st] then stems[st] = true; ns = ns + 1 end end
    if keys < 6 or single < attack * 0.8 or ns < 4 or ns < keys * 0.3 then return {} end
  end
  for _, o in ipairs(spans) do
    local nm = key_name_from_file(o.sample)
    if nm ~= "" then
      for n = math.max(0, o.lokey), math.min(127, o.hikey) do
        if names[n] == nil then names[n] = nm end
      end
    end
  end
  return names
end
M.key_name_from_file, M.drum_key_names = key_name_from_file, drum_key_names
M.is_xf, M.is_label = is_xf, is_label
M.cc_mod_of = cc_mod_of

-- a curve read at x (0..1): sfizz's built-in 0..6, a <curve> header's points (straight lines between them, ends
-- 0 and 1 unless given), else straight 0..1
local function curve_at(curves, idx, x)
  x = math.max(0, math.min(1, x))
  idx = math.floor(tonumber(idx) or 0)
  if idx == 1 then return -1 + 2 * x elseif idx == 2 then return 1 - x elseif idx == 3 then return 1 - 2 * x
  elseif idx == 4 then return x * x elseif idx == 5 then return math.sqrt(x) elseif idx == 6 then return math.sqrt(1 - x) end
  local pts = curves and curves[idx]
  if not pts then return x end
  local f = x * 127; local i = math.floor(f); if i >= 127 then return pts[127] end
  return pts[i] + (pts[i + 1] - pts[i]) * (f - i)
end
M.curve_at = curve_at

-- <curve> headers -> { [index] = { [0..127] = value } }
local function build_curves(list)
  local out = {}
  for _, c in ipairs(list or {}) do
    local idx = tonumber(c.curve_index)
    if idx then
      local set = { [0] = 0, [127] = 1 }
      for k, v in pairs(c) do
        local n = k:match("^v(%d+)$"); local y = tonumber(v)
        if n and y and tonumber(n) <= 127 then set[tonumber(n)] = y end
      end
      local pts, last = {}, 0
      for i = 0, 127 do
        if set[i] ~= nil then
          for j = last + 1, i - 1 do pts[j] = set[last] + (set[i] - set[last]) * (j - last) / (i - last) end
          pts[i] = set[i]; last = i
        end
      end
      out[math.floor(idx)] = pts
    end
  end
  return out
end
M.build_curves = build_curves

local function resolve(r, ctx, report)
  local control = r._control or {}
  local oo = num(control.octave_offset) or 0
  local no = num(control.note_offset) or 0
  local out = {}
  -- recognised opcode bookkeeping
  for k, _ in pairs(r) do
    if k:sub(1, 1) ~= "_" and not FIELD[k] and not SPECIAL[k] and not k:match("^locc%d+$") and not k:match("^hicc%d+$") and not k:match("^amp_velcurve_%d+$")
       and not cc_mod_of(k) and not is_cc_aux(k) and not is_xf(k) and not is_label(k) and not is_shape(k) then
      local base = k:gsub("%d+$", "N")
      report.ignored[base] = (report.ignored[base] or 0) + 1
    end
  end
  for _, f in ipairs(M.FIELDS) do
    local name, kind, def = f[1], f[2], f[3]
    local v = r[name]
    local val
    if v == nil then val = def
    elseif kind == "note" then
      if v == "sample" and name == "pitch_keycenter" then val = "sample"
      else val = M.parse_note(v, oo); if val == nil then report.bad_values[name] = (report.bad_values[name] or 0) + 1; val = def end end
    elseif kind == "int" or kind == "num" then
      val = tonumber(v)
      if val == nil or val ~= val or val == math.huge or val == -math.huge then
        report.bad_values[name] = (report.bad_values[name] or 0) + 1; val = def
      elseif kind == "int" then val = math.floor(val + 0.5) end
    else
      val = v:lower()
    end
    out[name] = val
  end
  -- note_offset: incoming notes are shifted by +no, so a region's keys move by -no
  if no ~= 0 then
    for _, k in ipairs({ "lokey", "hikey" }) do out[k] = out[k] - no end
    if type(out.pitch_keycenter) == "number" then out.pitch_keycenter = out.pitch_keycenter - no end
  end
  -- controller-driven opcodes at the starting values (see CC_MODS); amplitude (%) and region delay join them here
  local amp = (num(r.amplitude) or 100) / 100
  out.ampeg_delay = out.ampeg_delay + math.max(0, num(r.delay) or 0)   -- Gumbo's start delay is the region delay
  -- format 2: the crossfades first (each a mod; up to M.MAX_MODS per region with the live controllers below)
  local mods = {}
  local function xf(kind, lo_k, hi_k, cc, curve_k, lo_def, hi_def, base)
    local lo, hi = r[lo_k], r[hi_k]
    if lo == nil and hi == nil then return end
    local a = (base == 9 or base == 10) and M.parse_note(lo or "", oo) or tonumber(lo)
    local b = (base == 9 or base == 10) and M.parse_note(hi or "", oo) or tonumber(hi)
    a = a or lo_def; b = b or hi_def
    local gain = tostring(r[curve_k] or "power"):lower() == "gain"
    mods[#mods + 1] = { base + (gain and 100 or 0), cc, a, b }
  end
  local xccs, xseen = {}, {}
  for k, _ in pairs(r) do
    local n = k:match("^xfin_[lh][oi]cc(%d+)$") or k:match("^xfout_[lh][oi]cc(%d+)$")
    if n and not xseen[n] then xseen[n] = true; xccs[#xccs + 1] = tonumber(n) end
  end
  table.sort(xccs)
  for _, n in ipairs(xccs) do
    if n <= 127 then
      xf("in", "xfin_locc" .. n, "xfin_hicc" .. n, n, "xf_cccurve", 0, 0, 5)
      xf("out", "xfout_locc" .. n, "xfout_hicc" .. n, n, "xf_cccurve", 127, 127, 6)
    end
  end
  xf("in", "xfin_lovel", "xfin_hivel", 0, "xf_velcurve", 0, 0, 7)
  xf("out", "xfout_lovel", "xfout_hivel", 0, "xf_velcurve", 127, 127, 8)
  xf("in", "xfin_lokey", "xfin_hikey", 0, "xf_keycurve", 0, 0, 9)
  xf("out", "xfout_lokey", "xfout_hikey", 0, "xf_keycurve", 127, 127, 10)
  if #mods > M.MAX_MODS then
    report.mods_dropped = (report.mods_dropped or 0) + #mods - M.MAX_MODS
    for i = #mods, M.MAX_MODS + 1, -1 do mods[i] = nil end
  end
  -- the controller-driven opcodes, in a fixed order (pairs() has none): amplitude / volume / pan / tune on a real
  -- controller play LIVE while a mod slot is free; everything else is folded in at the starting value as before
  local cand = {}
  for k, v in pairs(r) do
    local m, n = cc_mod_of(k)
    if m and tonumber(v) then cand[#cand + 1] = { k = k, v = v, m = m, n = n } end
  end
  -- the lowest controller numbers stay live first (the mod wheel 1, breath 2, foot 4, expression 11 are the ones
  -- played); then by name, so the order never depends on pairs()
  table.sort(cand, function(a, b) if a.n ~= b.n then return a.n < b.n end; return a.k < b.k end)
  for _, cd in ipairs(cand) do
    local k, m, n = cd.k, cd.m, cd.n
    local depth = tonumber(cd.v)
    local live_t = LIVE_T[m[2]]
    if live_t and n <= 127 and not ((n == 7 or n == 11) and m[2] == "amplitude") and #mods < M.MAX_MODS then
      local cidx = math.floor(tonumber(m[4] and r[m[4] .. "_curvecc" .. n]) or 0)
      if cidx >= 7 then ctx.used_curves[cidx] = true end
      mods[#mods + 1] = { live_t, n, depth, cidx }
      report.cc_live_mod[tostring(n)] = (report.cc_live_mod[tostring(n)] or 0) + 1
    elseif m and depth then
      if (n == 7 or n == 11) and m[2] == "amplitude" then
        report.cc_played_live[tostring(n)] = (report.cc_played_live[tostring(n)] or 0) + 1   -- Gumbo's own CC7 / CC11 (sfizz's default)
      else
        local x
        if n == 133 then x = (type(out.pitch_keycenter) == "number" and out.pitch_keycenter or 60) / 127   -- note number: the root
        elseif n >= 128 then x = nil
        else
          local start = tonumber(control["set_cc" .. n])
          if start then x = start / 127 else
            local hd = tonumber(control["set_hdcc" .. n]); x = hd or CC_DEFAULT[n] or 0
          end
        end
        if x == nil then
          report.cc_per_note[tostring(n)] = (report.cc_per_note[tostring(n)] or 0) + 1                -- velocity, random ... : not folded
        else
          local c = curve_at(ctx.curves, m[4] and r[m[4] .. "_curvecc" .. n], x)
          if m[3] == "mul" then amp = amp * depth / 100 * c
          elseif m[2] == "offset" then local o = depth * c; out.offset = out.offset + (o >= 0 and math.floor(o) or math.ceil(o))   -- sfizz truncates each
          else out[m[2]] = out[m[2]] + depth * c end
          report.cc_folded[tostring(n)] = (report.cc_folded[tostring(n)] or 0) + 1
        end
      end
    end
  end
  out._mods = mods
  if amp <= 0.000001 then return nil, "silent_at_start" end   -- e.g. an "extra mics" control that starts at 0
  if amp ~= 1 then out.volume = out.volume + 20 * math.log(amp, 10) end
  for _, k in ipairs({ "global_volume", "master_volume", "group_volume" }) do
    local hv = tonumber(r[k])
    if hv and hv == hv and math.abs(hv) < 1000 then out.volume = out.volume + hv
    elseif r[k] ~= nil then report.bad_values[k] = (report.bad_values[k] or 0) + 1 end
  end
  if type(out.offset) == "number" then out.offset = math.max(0, math.floor(out.offset + 0.5)) end
  -- ranges and words
  local function clamp(name, lo, hi) local x = out[name]; if x < lo then x = lo end; if x > hi then x = hi end; out[name] = x end
  clamp("lovel", 1, 127); clamp("hivel", 1, 127); clamp("volume", -144, 24); clamp("pan", -100, 100)
  clamp("amp_veltrack", -100, 100); clamp("ampeg_sustain", 0, 100); clamp("lorand", 0, 1); clamp("hirand", 0, 1)
  clamp("tune", -2400, 2400); clamp("transpose", -127, 127)
  if out.trigger and not TRIGGERS[out.trigger] then report.bad_values.trigger = (report.bad_values.trigger or 0) + 1; out.trigger = "attack" end
  local lm_given = r.loop_mode ~= nil
  if lm_given and not LOOP_MODES[out.loop_mode] then report.bad_values.loop_mode = (report.bad_values.loop_mode or 0) + 1; lm_given = false end
  if r.count ~= nil and (tonumber(r.count) or 0) >= 1 then out.loop_mode = "one_shot"; lm_given = true
    if tonumber(r.count) > 1 then report.count_over_1 = (report.count_over_1 or 0) + 1 end end
  -- the sample
  local s = r.sample
  if s == nil or s == "" then return nil, "no_sample" end
  local spath, info
  if s:lower() == "*silence" then
    -- a silent region still starts a voice, so its group/off_by chokes others (a hi-hat pedal note); keep it
    spath, info = "*silence", { frames = 0, channels = 0, rate = 0 }
  elseif s:sub(1, 1) == "*" then
    return nil, "oscillator"
  else
    local dp = control.default_path or ""
    spath = join(ctx.top_dir, (dp ~= "" and (dp:gsub("\\", "/"):gsub("/*$", "/")) or "") .. s:gsub("\\", "/"))
    -- keyed by the exact spelling: the player loads each spelling of a path once (gb_sample_index compares bytes)
    info = ctx.audio[spath]
    if info == nil then
      local okc, inf = pcall(M.audio_info, spath)
      if not okc then info = { format = "broken", frames = 0, channels = 0, rate = 0 }   -- it raised: unreadable audio
      else info = inf or false end                                                      -- nil = the file is missing
      ctx.audio[spath] = info
    end
    if not info then return nil, "missing_sample", spath end
    -- a WAV or FLAC must have sound in it; another format (.ogg: Gumbo plays it through REAPER's reader, measured
    -- 2026-11-05) is kept and counted; its length comes from opts.probe when the caller has one (the RAM estimate)
    local ext = (spath:match("%.([%w]+)$") or ""):lower()
    if info.format == "other" and ext ~= "wav" and ext ~= "flac" then
      report.audio_other = (report.audio_other or 0) + 1
      if ctx.probe and (info.frames or 0) < 1 then
        local okp, f, ch, rt = pcall(ctx.probe, spath)
        if okp and type(f) == "number" and f > 0 then
          info = { format = "other", frames = math.floor(f), channels = tonumber(ch) or 1, rate = tonumber(rt) or 44100 }
          ctx.audio[spath] = info
        end
      end
    elseif info.format ~= "wav" and info.format ~= "flac" or info.frames < 1 or info.channels < 1 or info.rate < 1 then
      return nil, "bad_audio", spath
    end
  end
  out.sample = spath
  out._frames, out._channels, out._rate = info.frames, info.channels, info.rate
  -- pitch_keycenter=sample: the file's MIDI unity note; with none, sfzformat.com says note 0 (counted, so it shows)
  if out.pitch_keycenter == "sample" then
    out.pitch_keycenter = ((info.root and info.root <= 127) and info.root or 0) - no   -- note_offset, as for a number
    report.keycenter_sample = (report.keycenter_sample or 0) + 1
  end
  -- loops: the SFZ wins; else the file's first loop; loop_mode unset -> loop_continuous if the file has a loop
  local file_loop = info.loop_start ~= nil and info.loop_end ~= nil and info.loop_end > info.loop_start
  if not lm_given then out.loop_mode = file_loop and "loop_continuous" or "no_loop" end
  if file_loop and (out.loop_mode == "loop_continuous" or out.loop_mode == "loop_sustain") and r.loop_start == nil then
    report.loops_from_file = (report.loops_from_file or 0) + 1
  end
  if spath == "*silence" then out.loop_mode = "one_shot"; out.loop_start = 0; out.loop_end = 0
  elseif out.loop_mode == "loop_continuous" or out.loop_mode == "loop_sustain" then
    if r.loop_start == nil then out.loop_start = file_loop and info.loop_start or 0 end
    if r.loop_end == nil then out.loop_end = file_loop and info.loop_end or 0 end
    if out.loop_end <= out.loop_start then
      report.loop_without_points = (report.loop_without_points or 0) + 1; out.loop_mode = "no_loop"; out.loop_start = 0; out.loop_end = 0
    end
  else
    out.loop_start = 0; out.loop_end = 0
  end
  -- release regions: no_loop / one_shot behave as one_shot
  if (out.trigger == "release" or out.trigger == "release_key") and out.loop_mode == "no_loop" then out.loop_mode = "one_shot" end
  -- CC-gated regions (loccN / hiccN; CC64 is a fixed field). ctx.cc_mode "live" (default): every gate is written
  -- and Gumbo checks the controller's value at each note-on (a hi-hat pedal on CC4 opens the hat). "fixed": a CC
  -- sits at its starting value (set_ccN, else 0), so a region whose range misses it can never sound and is left out
  -- -- the library builder's way to trim RAM.
  local gates, seen = {}, {}
  for k, _ in pairs(r) do
    local n = k:match("^locc(%d+)$") or k:match("^hicc(%d+)$")
    if n and n ~= "64" and not seen[n] then
      seen[n] = true
      local lo, hi = tonumber(r["locc" .. n]) or 0, tonumber(r["hicc" .. n]) or 127
      if ctx.cc_mode == "fixed" then
        if not cc_reaches(control, n, lo, hi) then report.cc_dropped[n] = (report.cc_dropped[n] or 0) + 1; return nil, "cc_unreachable" end
      else
        if lo > hi then report.cc_dropped[n] = (report.cc_dropped[n] or 0) + 1; return nil, "cc_unreachable" end
        gates[#gates + 1] = { tonumber(n), lo, hi }
        report.cc_live[n] = (report.cc_live[n] or 0) + 1
      end
    end
  end
  table.sort(gates, function(a, b) return a[1] < b[1] end)
  out._gates = gates
  -- amp_velcurve_N points (velocity N -> 0..1), written after the fixed fields, in velocity order
  local vc = {}
  for k, v in pairs(r) do
    local n = k:match("^amp_velcurve_(%d+)$")
    local x = tonumber(v)
    if n and x and tonumber(n) <= 127 then vc[#vc + 1] = { tonumber(n), math.max(0, math.min(1, x)) } end
  end
  table.sort(vc, function(a, b) return a[1] < b[1] end)
  out._velcurve = vc
  if out.lokey > out.hikey or out.lovel > out.hivel then return nil, "empty_range" end
  if out.lokey < 0 and out.hikey < 0 then return nil, "never_triggered" end
  if out["end"] == -1 then return nil, "end_minus_1" end
  out._shape = shape_of(r, oo, report)   -- the filter, its envelope, the LFOs (nil = none)
  if out._shape then report.shaped = (report.shaped or 0) + 1 end
  return out
end

-- ── output ───────────────────────────────────────────────────────────────────────────────────────────────────
local function fmt(v)
  if type(v) == "number" then
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return (string.format("%.6f", v):gsub("0+$", ""):gsub("%.$", ""))
  end
  return tostring(v)
end

-- ── programs: a GM bank in one file (loprog / hiprog, MIDI program numbers 0-127) ──────────────────────────
-- Each distinct (section, loprog..hiprog) is one program; a section is a <global> part of the file (a combined bank:
-- the melodic programs, then the drum kits, both starting at program 0). Returns a list, in file order, of
--   { part = n, lo = p, hi = p2, name = "..." }   (name: master_label / group_label without a leading "1:1 - ",
--   else global_label + the program number), or an empty list when no region names a program (an ordinary
--   instrument: convert it whole). Errors reading the file -> empty list (convert reports them).
local function prog_name(r, lo)
  local nm = r.master_label or r.group_label
  if nm then nm = trim(tostring(nm)):gsub("^%d+:%d+%s*%(?%d*%)?%s*%-%s*", "") end
  if not nm or nm == "" then nm = trim(tostring(r.global_label or "Program")) .. " " .. (lo + 1) end
  return nm
end
local function prog_range(r)
  local lo, hi = num(r.loprog), num(r.hiprog)
  if lo == nil and hi == nil then return nil end
  lo = math.max(0, math.min(127, math.floor(lo or 0))); hi = math.max(0, math.min(127, math.floor(hi or 127)))
  return lo, hi
end
local function list_programs(regs)
  local out, seen = {}, {}
  for _, r in ipairs(regs) do
    local lo, hi = prog_range(r)
    if lo and lo <= hi then
      local key = r._part .. ":" .. lo .. ":" .. hi
      if not seen[key] then seen[key] = true; out[#out + 1] = { part = r._part, lo = lo, hi = hi, name = prog_name(r, lo) } end
    end
  end
  return out
end
-- the section that is a drum bank (channel 10): its global_label, or every program name in it, says drums / kit /
-- percussion; 0 = none
local function drum_part(regs, progs)
  local parts = {}
  for _, pg in ipairs(progs) do parts[pg.part] = parts[pg.part] or { all = true } end
  for _, pg in ipairs(progs) do
    if not pg.name:lower():find("kit") and not pg.name:lower():find("drum") and not pg.name:lower():find("perc") then parts[pg.part].all = false end
  end
  for _, r in ipairs(regs) do
    local pr = parts[r._part]
    if pr and pr.label == nil then pr.label = tostring(r.global_label or ""):lower() end
  end
  local n = 0; for _ in pairs(parts) do n = n + 1 end
  if n < 2 then return 0 end         -- one section: nothing to tell apart
  -- the section that says it is MIDI bank 128 (the SoundFont importer's gumbo_bank) first; then, lowest section first
  -- (pairs() has no order, and with every variation bank kept a bank of percussive organs could pass the name test),
  -- a label saying drums; then every program name saying so
  for _, r in ipairs(regs) do
    if parts[r._part] and r.gumbo_bank and ("," .. tostring(r.gumbo_bank) .. ","):find(",128,", 1, true) then return r._part end
  end
  local order = {}
  for part in pairs(parts) do order[#order + 1] = part end
  table.sort(order)
  for _, part in ipairs(order) do
    local lb = parts[part].label or ""
    if lb:find("drum") or lb:find("perc") or lb:find("kit") then return part end
  end
  for _, part in ipairs(order) do if parts[part].all then return part end end
  return 0
end
function M.programs(sfz_path)
  local report = { errors = {}, ignored = {}, bad_values = {}, headers_skipped = {}, skipped = {}, top_dir = dirname(sfz_path) }
  local text = expand(sfz_path, report, {}, 0, {})
  if not text or report.fatal then return {} end
  return list_programs((collect(tokenize(text), report)))
end

function M.convert(sfz_path, out_path, opts)
  opts = opts or {}
  local report = { errors = {}, ignored = {}, bad_values = {}, headers_skipped = {}, skipped = {}, cc_dropped = {}, cc_live = {},
                   cc_folded = {}, cc_per_note = {}, cc_played_live = {}, cc_live_mod = {},
                   top_dir = dirname(sfz_path) }
  local res = { ok = false, report = report, regions = 0 }
  local text = expand(sfz_path, report, {}, 0, {})
  -- a missing or unreadable #include means part of the instrument is missing: no output (an earlier one is kept).
  -- An include loop or depth stop is not fatal: that text was already pasted in once.
  if not text or report.fatal then return res end
  local toks = tokenize(text)
  local regs, _, curve_list = collect(toks, report)
  -- opts.program = one entry of M.programs: only its section's regions whose program range takes in its program
  -- (a region naming no program plays in every program of its section)
  if opts.program then
    local pg, keep = opts.program, {}
    for _, r in ipairs(regs) do
      local lo, hi = prog_range(r)
      if r._part == pg.part and (lo == nil or (lo <= pg.lo and pg.lo <= hi)) then keep[#keep + 1] = r end
    end
    regs = keep
  end
  -- a whole bank (programs named, none picked): one instrument, every region tagged with its program (format 3)
  local bank = nil
  if not opts.program then
    local progs = list_programs(regs)
    -- (one range taking in every program is an ordinary instrument that merely says so: no bank)
    if #progs > 1 or (#progs == 1 and (progs[1].lo > 0 or progs[1].hi < 127)) then bank = { progs = progs, drums = drum_part(regs, progs) } end
  end
  res.bank = bank
  local ctx = { top_dir = dirname(sfz_path), audio = {}, cc_mode = opts.cc_mode == "fixed" and "fixed" or "live",
                probe = opts.probe or nil,   -- (a Lua function, or a callable the tests hand in from python; pcall'd)
                curves = build_curves(curve_list), used_curves = {} }
  local first_control = nil
  local outs, frames_total, missing = {}, 0, {}
  local counted = {}
  local labels, swl = {}, {}          -- format 2: controller names (label_ccN), keyswitch names (sw_label by sw_last)
  local klab = {}                     -- the SFZ's own key names (label_keyN)
  for _, r in ipairs(regs) do
    if first_control == nil then first_control = r._control end
    -- a bank: controller names from every program, key names only from its drum kits (a piano keeps note names)
    local keys_ok = not bank or r._part == bank.drums
    for ti, t in ipairs({ r._control or {}, r }) do
      for k, v in pairs(t) do
        local n = k:match("^label_cc(%d+)$")
        if n and tonumber(n) <= 127 and labels[tonumber(n)] == nil then labels[tonumber(n)] = trim(tostring(v)) end
        local kn = (ti == 1 or keys_ok) and k:match("^label_key(%d+)$")
        if kn and tonumber(kn) <= 127 and klab[tonumber(kn)] == nil then klab[tonumber(kn)] = trim(tostring(v)):sub(1, 24) end
      end
    end
    local o, why, p = resolve(r, ctx, report)
    if o and bank then
      local lo, hi = prog_range(r)
      if lo then o._prog = { r._part, lo, hi } end
      o._part = r._part
    end
    if o then
      if r.sw_label and o.sw_last >= 0 and swl[o.sw_last] == nil then swl[o.sw_last] = trim(tostring(r.sw_label)) end
      outs[#outs + 1] = o
      local key = o.sample              -- exact spelling, as the player dedupes
      if not counted[key] and o.sample ~= "*silence" then counted[key] = true; frames_total = frames_total + (o._frames or 0) * math.max(o._channels or 1, 1) end
    else
      report.skipped[why] = (report.skipped[why] or 0) + 1
      if why == "missing_sample" and #missing < 20 then missing[#missing + 1] = p end
    end
  end
  report.missing_examples = missing
  report.regions_in = #regs
  report.regions_out = #outs
  report.sample_files = 0; for _ in pairs(counted) do report.sample_files = report.sample_files + 1 end
  report.cells = frames_total
  report.ram_mb = frames_total * 8 / 1048576
  -- nothing playable: write nothing, so an earlier good conversion at out_path stays and nobody lists an empty
  -- instrument (found 2026-10-30 by the Gumbo helper's test: a failed import was listed in the browser)
  if #outs == 0 then report.errors[#report.errors + 1] = "no playable regions"; return res end
  -- write
  local out_dir = dirname(out_path)
  -- opts.relocate: where the packaged copy of a sample will be (written path only)
  local rl = opts.relocate
  local function relocate(p)
    if not rl or not rl.from or not rl.to then return p end
    local np, from = norm_path(p), norm_path(rl.from) .. "/"
    if np:lower():sub(1, #from) ~= from:lower() then return p end
    local rest = np:sub(#from + 1)
    if rl.ext then rest = rest:gsub("%.[^./]+$", "") .. rl.ext end
    return norm_path(rl.to) .. "/" .. rest
  end
  local L = {}
  L[#L + 1] = string.format("// gumbo-flat %d", bank and M.BANK_FORMAT_VERSION or M.FORMAT_VERSION)
  L[#L + 1] = "// source: " .. norm_path(sfz_path)
  L[#L + 1] = string.format("// regions %d of %d; sample files %d; RAM when loaded %.1f MB", #outs, #regs,
                            report.sample_files, report.ram_mb)
  local fields = {}
  for _, f in ipairs(M.FIELDS) do fields[#fields + 1] = f[1] end
  L[#L + 1] = "// fields: sample " .. table.concat(fields, " ") .. " [amp_velcurve_N...] [loccN hiccN...] [mod=T,CC,A,B...] [prog fil feg lfo vel peg keg bend tokens]"
  -- starting controller values (set_ccN, set_hdccN scaled to 0-127), so live CC gates begin where the SFZ meant
  local sets = {}
  for k, v in pairs(first_control or {}) do
    local n = k:match("^set_cc(%d+)$"); local x = tonumber(v)
    if n and x then sets[tonumber(n)] = math.max(0, math.min(127, math.floor(x + 0.5))) end
    local h = k:match("^set_hdcc(%d+)$")
    if h and x and sets[tonumber(h)] == nil then sets[tonumber(h)] = math.max(0, math.min(127, math.floor(x * 127 + 0.5))) end
  end
  local sk = {}
  for n in pairs(sets) do sk[#sk + 1] = n end
  table.sort(sk)
  if #sk > 0 then
    local cp = { "<control>" }
    for _, n in ipairs(sk) do cp[#cp + 1] = "set_cc" .. n .. "=" .. sets[n] end
    L[#L + 1] = table.concat(cp, " ")
  end
  -- format 2: names for the player's face, and the custom curves the live controllers use
  local function sorted_keys(t) local ks = {}; for n in pairs(t) do ks[#ks + 1] = n end; table.sort(ks); return ks end
  -- format 3: the bank's programs, in file order, and its drum section (names cut to 64 characters for the face)
  if bank then
    if bank.drums > 0 then L[#L + 1] = "// drums " .. bank.drums end
    -- the MIDI bank numbers each section answers to, "// bank S N" (gumbo_bank= on its <global>, from the SoundFont
    -- importer; a section without one gets the player's defaults: the first melodic section is bank 0, the drums 128)
    local bank_of, bparts = {}, {}
    for _, r in ipairs(regs) do
      if r.gumbo_bank and bank_of[r._part] == nil then bank_of[r._part] = tostring(r.gumbo_bank); bparts[#bparts + 1] = r._part end
    end
    table.sort(bparts)
    for _, part in ipairs(bparts) do
      for nb in bank_of[part]:gmatch("[^,]+") do
        local b = tonumber(nb)
        if b and b >= 0 and b <= 255 and b == math.floor(b) then L[#L + 1] = "// bank " .. part .. " " .. b end
      end
    end
    for _, pg in ipairs(bank.progs) do
      L[#L + 1] = "// program " .. pg.part .. " " .. pg.lo .. " " .. pg.hi .. " " .. pg.name:gsub("[%c|]", " "):gsub("^[<>]+", ""):sub(1, 64)
    end
  end
  for _, n in ipairs(sorted_keys(labels)) do
    if labels[n] ~= "" then L[#L + 1] = "// label_cc " .. n .. " " .. labels[n] end
  end
  for _, n in ipairs(sorted_keys(swl)) do
    if swl[n] ~= "" then L[#L + 1] = "// sw_label " .. n .. " " .. swl[n] end
  end
  if next(klab) == nil then
    -- a bank: key names only from its drum kits (a piano's keys keep their note names)
    local src = outs
    if bank then src = {}; for _, o in ipairs(outs) do if bank.drums > 0 and o._part == bank.drums then src[#src + 1] = o end end end
    klab = #src > 0 and drum_key_names(src, bank ~= nil) or {}
  end
  report.key_names = 0
  for _, n in ipairs(sorted_keys(klab)) do
    if klab[n] ~= "" then L[#L + 1] = "// label_key " .. n .. " " .. klab[n]; report.key_names = report.key_names + 1 end
  end
  -- a bank's kits each name their own keys (2026-11-05): "// key_name S P NOTE name" per kit, from that kit's own
  -- recordings (drum_key_names, the one rule; the kit is declared, so no pitched-instrument guess). "// label_key"
  -- above stays the file-wide union, for older Gumbos and ordinary kits. The player names the playing kit's pads from
  -- these, so another kit's keys never show as silent pads (a GM set's Standard kit showed 84 pads for its 61 keys).
  report.kit_key_names = 0
  if bank and bank.drums > 0 then
    for _, pg in ipairs(bank.progs) do
      if pg.part == bank.drums then
        local ko = {}
        for _, o in ipairs(outs) do
          if o._part == pg.part and (o._prog == nil or (o._prog[2] <= pg.lo and pg.lo <= o._prog[3])) then ko[#ko + 1] = o end
        end
        local kn = drum_key_names(ko, true)
        for _, n in ipairs(sorted_keys(kn)) do
          if kn[n] ~= "" then
            L[#L + 1] = "// key_name " .. pg.part .. " " .. pg.lo .. " " .. n .. " " .. kn[n]
            report.kit_key_names = report.kit_key_names + 1
          end
        end
      end
    end
  end
  for _, i in ipairs(sorted_keys(ctx.used_curves)) do
    local cv = { "// curve " .. i }
    for x = 0, 127 do cv[#cv + 1] = fmt(curve_at(ctx.curves, i, x / 127)) end
    L[#L + 1] = table.concat(cv, " ")
  end
  for _, o in ipairs(outs) do
    local parts = { "<region> sample=" .. (o.sample == "*silence" and "*silence" or rel_to(relocate(o.sample), out_dir)) }
    for _, f in ipairs(M.FIELDS) do
      local name = f[1]
      if not (name == "end" and o[name] == -2) then parts[#parts + 1] = name .. "=" .. fmt(o[name]) end
    end
    for _, p in ipairs(o._velcurve or {}) do parts[#parts + 1] = "amp_velcurve_" .. p[1] .. "=" .. fmt(p[2]) end
    for _, gt in ipairs(o._gates or {}) do parts[#parts + 1] = "locc" .. gt[1] .. "=" .. gt[2] .. " hicc" .. gt[1] .. "=" .. gt[3] end
    for _, md in ipairs(o._mods or {}) do parts[#parts + 1] = "mod=" .. md[1] .. "," .. md[2] .. "," .. fmt(md[3]) .. "," .. fmt(md[4]) end
    if o._prog then parts[#parts + 1] = "prog=" .. o._prog[1] .. "," .. o._prog[2] .. "," .. o._prog[3] end
    local sh = o._shape
    if sh then
      if sh.fil then parts[#parts + 1] = "fil=" .. sh.fil end
      if sh.feg then parts[#parts + 1] = "feg=" .. sh.feg end
      for _, l in ipairs(sh.lfo) do parts[#parts + 1] = "lfo=" .. l end
      if sh.vel then parts[#parts + 1] = "vel=" .. sh.vel end
      if sh.peg then parts[#parts + 1] = "peg=" .. sh.peg end
      if sh.keg then parts[#parts + 1] = "keg=" .. sh.keg end
      if sh.bend then parts[#parts + 1] = "bend=" .. sh.bend end
    end
    L[#L + 1] = table.concat(parts, " ")
  end
  L[#L + 1] = "// end"
  local body = table.concat(L, "\n") .. "\n"
  -- pad to a multiple of 4 bytes, so even a raw-float read (spec §0c) loses nothing
  local pad = (4 - (#body % 4)) % 4
  if pad > 0 then body = body .. string.rep(" ", pad) end
  local tmp = out_path .. ".tmp"
  local f = io.open(tmp, "wb")
  if not f then report.errors[#report.errors + 1] = "cannot write " .. tmp; return res end
  f:write(body); f:close()
  local chk = read_all(tmp)
  if chk ~= body then report.errors[#report.errors + 1] = "write check failed"; os.remove(tmp); return res end
  -- replace an earlier output without ever losing it: move it aside, move the new one in, put it back on failure
  local bak = nil
  if exists(out_path) then
    bak = out_path .. ".bak"; os.remove(bak)
    local okb, eb = os.rename(out_path, bak)
    if not okb then report.errors[#report.errors + 1] = "cannot move the old output aside: " .. tostring(eb); os.remove(tmp); return res end
  end
  local okr, err = os.rename(tmp, out_path)
  if not okr then
    if bak then os.rename(bak, out_path) end
    report.errors[#report.errors + 1] = "rename failed: " .. tostring(err); return res
  end
  if bak then os.remove(bak) end
  res.ok = #outs > 0
  res.regions = #outs
  res.bytes = #body
  return res
end

M.norm_path = norm_path   -- (for the tests)
return M
