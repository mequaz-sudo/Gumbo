-- Copyright (c) 2026 EON Studios (Quaz). All rights reserved. Free to use: see Gumbo_LICENSE.md.
-- gumbo_sf2.lua -- a SoundFont 2 file into an SFZ bank Gumbo's converter (gumbo_sfz.lua) then reads like any other:
-- each sample written out as a mono WAV, one SFZ with a <global> per bank section (bank 0 melodic, bank 128 the drum
-- kits, then every variation bank; gumbo_bank= names the MIDI bank number), a <master loprog hiprog master_label> per
-- preset, a <region> per preset zone x instrument zone. A file with
-- one preset is written as an ordinary instrument (no programs). Pure Lua 5.4, no reaper.* calls; the Gumbo helper
-- and the offline tests load it.
--
-- Rules from the SoundFont 2.01 specification (E-mu, 1998; read 2026-11-02): RIFF sfbk with sdta/smpl (16-bit mono
-- sample data) and the pdta hydra (phdr pbag pmod pgen inst ibag imod igen shdr); zones from the bag indexes, a zone
-- with no instrument / sampleID generator last is the global zone; instrument generators are absolute (zone over
-- global over defaults), preset generators are added to them, key and velocity ranges intersect. Units: timecents
-- (2^(tc/1200) s), centibels, cents, 0.1 % pan. initialAttenuation is scaled by 0.4 as FluidSynth does (the GM sets
-- worth opening are voiced for it).
-- The filter, the modulation envelope and both LFOs (2026-11-03) become SFZ opcodes, played the way FluidSynth plays
-- them (Research .docs/research/Gumbo_Tone_Filter_Research_2026-11-03.md): a 2-pole low-pass at initialFilterFc, its
-- resonance cB/10 - 3.01 dB (FluidSynth's Q), and FluidSynth's level drop for a resonant filter (1/sqrt(Q), unity at
-- 0 cB) as volume; the mod envelope -> fileg_* (to the cutoff); the vibrato LFO -> lfo01 on the pitch, plus the
-- default modulator's mod wheel vibrato (+50 cents); the mod LFO -> lfo02 on the volume (a positive amount louder on
-- the swing up, as FluidSynth) and the cutoff. Velocity does not darken the filter by default (FluidSynth turns that
-- default modulator off; GeneralUser GS and MuseScore General are voiced without it).
-- The file's own modulators (2026-11-04, "the modulators" below): the velocity and key rules on the cutoff, Q, the
-- mod envelope's depth, attenuation (the velocity curve), pan, tuning and the envelope times are baked into the
-- regions -- straight lines where Gumbo has an opcode for the slope (fil_keytrack / fil_veltrack, fileg_vel2depth,
-- ampeg_vel2attack.., amp_velpow), and a zone is cut into key / velocity cells where a line does not fit.
-- Controllers (2026-11-04, "live" below): a controller on the attenuation becomes volume_onccN through a <curve> of the
-- source's shape; on the cutoff, cutoff_onccN (a straight line through the controller's ends, the cutoff written at
-- controller 0); on anything else it is fixed at the controller's starting value. Breath (CC2) starts at 127 with the
-- name Breath (FluidSynth starts it at 0, which would mute a breath-shaped sound for a keyboard player). In the GM sets
-- every breath-shaped preset sits in a variation bank (MuseScore General's "Expr." banks 17-51, GeneralUser's wah
-- guitar on CC21 in bank 11), kept since 2026-11-05 with every other variation bank.
-- Not carried (counted in the report): pressure and the wheel as sources, two live sources on one modulator,
-- modulators to the LFOs / pitch / sends, the mod LFO on the pitch (when the vibrato LFO takes the pitch), chorus /
-- reverb sends, sm24 (24-bit) data, ROM samples. Carried since 2026-11-05: the mod envelope on the pitch (generator 7,
-- pitcheg_*), the key scaling of the hold / decay times (39, 40, 31, 32: Gumbo's own ampeg_hold_keytrack /
-- ampeg_decay_keytrack / fileg_hold_keytrack / fileg_decay_keytrack, timecents a key), and SF3 -- MuseScore's
-- compressed SoundFont (sfSampleType & 0x10: a complete mono Ogg Vorbis stream at BYTES dwStart .. dwEnd - 1 of smpl,
-- the end exclusive as sf3convert writes it; dwStartloop / dwEndloop frames of the decoded sample; ifil major 3): the
-- stream is written out as it is, "<n> <name>.ogg", and Gumbo's loader plays it through REAPER's own reader (measured
-- 2026-11-05). Its length in frames comes from an optional `probe(path) -> frames, channels, rate` (the helper's,
-- through REAPER; the offline tests' through python) for the loop check, the end= generator and the RAM estimate;
-- with none the loops are trusted and end= is left out (counted).
--
-- API:  local S = dofile(".../gumbo_sf2.lua")
--       local res = S.extract(sf2_path, out_dir [, sub [, probe]])   -- writes out_dir/<name>.sfz and out_dir/<sub>/*.wav (.ogg from an SF3)
--         (sub defaults to "samples"; the caller makes out_dir/<sub> first: folders need REAPER's own call)
--         res = { ok, sfz = path, presets = n, regions = n, written = { wav names },
--                 report = { errors = {}, skipped = {}, ignored = {} } }
--       A damaged file never raises: any read past its data ends as res.ok = false with an error line, and
--       res.written still lists every WAV written before it (the caller removes them).

local S = {}

local function u8(s, i) return s:byte(i) end
local function u16(s, i) local a, b = s:byte(i, i + 1); return a + b * 256 end
local function s16(s, i) local v = u16(s, i); return v >= 32768 and v - 65536 or v end
local function u32(s, i) local a, b, c, d = s:byte(i, i + 3); return a + b * 256 + c * 65536 + d * 16777216 end
local function cstr(s, i, n) return (s:sub(i, i + n - 1):gsub("%z.*$", "")) end
local function le16(v) return string.char(v % 256, (v // 256) % 256) end
local function le32(v) return string.char(v % 256, (v // 256) % 256, (v // 65536) % 256, (v // 16777216) % 256) end

-- generator numbers used here
local G_START, G_END, G_SLOOP, G_ELOOP, G_START_C = 0, 1, 2, 3, 4
local G_END_C, G_PAN = 12, 17
local G_DELAY, G_ATT, G_HOLD, G_DEC, G_SUS, G_REL = 33, 34, 35, 36, 37, 38
local G_INST, G_KEYS, G_VELS, G_SLOOP_C, G_ATTEN, G_ELOOP_C = 41, 43, 44, 45, 48, 50
local G_COARSE, G_FINE, G_SAMPLE, G_MODES, G_SCALE, G_EXCL, G_ROOT = 51, 52, 53, 54, 56, 57, 58
-- generators carried; anything else met is counted as ignored
local CARRIED = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true, [12] = true, [17] = true, [33] = true,
  [34] = true, [35] = true, [36] = true, [37] = true, [38] = true, [41] = true, [43] = true, [44] = true, [45] = true,
  [48] = true, [50] = true, [51] = true, [52] = true, [53] = true, [54] = true, [56] = true, [57] = true, [58] = true,
  -- the filter, the mod envelope (to the cutoff), the LFOs (2026-11-03)
  [5] = true, [8] = true, [9] = true, [10] = true, [11] = true, [13] = true, [6] = true, [21] = true, [22] = true, [23] = true,
  [24] = true, [25] = true, [26] = true, [27] = true, [28] = true, [29] = true, [30] = true,
  [7] = true,                          -- the mod envelope on the pitch (2026-11-05): pitcheg_*
  [39] = true, [40] = true, [31] = true, [32] = true }   -- key-scaled hold / decay (2026-11-05): Gumbo's *_keytrack opcodes
local G_FC, G_Q, G_LFO2FC, G_ENV2FC, G_LFO2VOL, G_VIB2PITCH, G_LFO2PITCH = 8, 9, 10, 11, 13, 6, 5
local G_MLFO_DLY, G_MLFO_FRQ, G_VLFO_DLY, G_VLFO_FRQ = 21, 22, 23, 24
local G_MDLY, G_MATT, G_MHOLD, G_MDEC, G_MSUS, G_MREL = 25, 26, 27, 28, 29, 30
local GEN_NAME = { [8] = "filter", [9] = "filter", [5] = "lfo", [6] = "lfo", [10] = "lfo", [13] = "lfo", [21] = "lfo",
  [22] = "lfo", [23] = "lfo", [24] = "lfo", [11] = "mod_env", [25] = "mod_env", [26] = "mod_env",
  [27] = "mod_env", [28] = "mod_env", [29] = "mod_env", [30] = "mod_env", [15] = "chorus", [16] = "reverb" }
-- instrument defaults (spec 8.1.3)
local function defaults()
  return { [G_DELAY] = -12000, [G_ATT] = -12000, [G_HOLD] = -12000, [G_DEC] = -12000, [G_SUS] = 0, [G_REL] = -12000,
           [G_SCALE] = 100, [G_ROOT] = -1, [G_KEYS] = { 0, 127 }, [G_VELS] = { 0, 127 },
           [G_FC] = 13500, [G_MDLY] = -12000, [G_MATT] = -12000, [G_MHOLD] = -12000, [G_MDEC] = -12000,
           [G_MREL] = -12000, [G_MLFO_DLY] = -12000, [G_VLFO_DLY] = -12000 }
end

-- the RIFF tree: the chunks we need, as byte positions into s
local function chunks(s)
  if #s < 12 or s:sub(1, 4) ~= "RIFF" or s:sub(9, 12) ~= "sfbk" then return nil, "not a SoundFont (RIFF sfbk)" end
  local found, bad = {}, nil
  -- a chunk that runs past its parent (a cut-off or damaged file) stops the read (outside audit, 2026-11-05)
  local function walk(a, b)
    local p = a
    while not bad and p + 8 <= b + 1 do
      local id, n = s:sub(p, p + 3), u32(s, p + 4)
      if p + 8 + n - 1 > b then bad = id; break end
      if id == "LIST" then walk(p + 12, p + 8 + n - 1)
      else found[id] = { p + 8, n } end
      p = p + 8 + n + (n % 2)
    end
  end
  walk(13, #s)
  if bad then return nil, "damaged SoundFont: its " .. bad:gsub("%c", "?") .. " chunk runs past the end of the file" end
  for _, id in ipairs({ "smpl", "phdr", "pbag", "pgen", "inst", "ibag", "igen", "shdr" }) do
    if not found[id] then return nil, "missing " .. id .. " chunk" end
  end
  return found
end

local function records(s, c, size)
  local out = {}
  for i = 0, c[2] // size - 1 do out[#out + 1] = c[1] + i * size end
  return out
end

-- one zone's generators: { [oper] = amount } (ranges as {lo, hi}), and whether it ends in the terminal generator
local function zone_gens(s, gens, a, b, term)
  local z, has = {}, false
  for g = a, b - 1 do
    local p = gens[g + 1]
    if p then
      local op = u16(s, p)
      if op == G_KEYS or op == G_VELS then z[op] = { u8(s, p + 2), u8(s, p + 3) }
      else z[op] = (op == G_INST or op == G_SAMPLE or op == G_MODES) and u16(s, p + 2) or s16(s, p + 2) end
      if op == term then has = true end
    end
  end
  return z, has
end

-- one zone's modulator records (imod / pmod, 10 bytes: source, destination, amount, amount source, transform)
local function zone_mods(s, mods, m0, m1)
  local out = {}
  for m = m0, m1 - 1 do
    local mp = mods[m + 1]
    if mp then out[#out + 1] = { src = u16(s, mp), dest = u16(s, mp + 2), amt = s16(s, mp + 4), asrc = u16(s, mp + 6), trans = u16(s, mp + 8) } end
  end
  return out
end
-- a bag list into { global = zone or nil, zones = {...} }, each zone carrying its modulators in _mods
local function zones_of(s, bags, gens, first, last, term, mods)
  local out = { zones = {} }
  for bi = first, last - 1 do
    local b0, b1 = bags[bi + 1], bags[bi + 2]
    if b0 and b1 then
      local z, has = zone_gens(s, gens, u16(s, b0), u16(s, b1), term)
      z._mods = mods and zone_mods(s, mods, u16(s, b0 + 2), u16(s, b1 + 2)) or {}
      if has then out.zones[#out.zones + 1] = z
      elseif bi == first and not out.global then out.global = z end
    end
  end
  return out
end

-- ── the modulators (2026-11-04): a zone's velocity and key rules, baked into the regions ─────────────────────────
-- SF2.01 section 8.2 as FluidSynth plays it (fluid_mod.c, fluid_conv, gen_conv.c read 2026-11-04): a source's value
-- is raw / 128 (velocity, key), turned round for a negative direction (1 - 1/128 - value), spread to -1..1 when
-- bipolar; linear / concave / convex / switch; the amount x source x second source, added to the generator (cents,
-- centibels, timecents). The instrument's modulators replace an identical default (same destination and sources) by
-- amount, the preset's add to it; a zone's own replace its global zone's. One default matters per note: velocity ->
-- attenuation, concave, 960 cB (= (v/127)^2: what Gumbo plays anyway). Velocity -> cutoff with the default's shape is
-- 0 in FluidSynth whatever its amount ("S. Christian Collins' mod"); both GM sets are voiced for that.
-- A controller source reads the raw value the modulator carries in ccraw (0 for a live cutoff line's fixed part, the
-- controller's start for a folded one); pressure and the wheel are not baked: counted in the report.
local CC_START = { [2] = 127 }            -- breath: full, see the header
local CC_NAME = { [1] = "Mod wheel", [2] = "Breath", [4] = "Foot", [11] = "Expression" }
local CONCAVE, CONVEX = { [0] = 0, [127] = 1 }, { [0] = 0, [127] = 1 }
for i = 1, 126 do
  local x = (-400 / 960) * math.log(i / 127, 10)
  CONVEX[i] = 1 - x; CONCAVE[127 - i] = x
end
local function curve_tab(t, x)
  if x < 0 then return 0 end
  local i = math.floor(x); if i >= 127 then return t[127] end
  return t[i] + (t[i + 1] - t[i]) * (x - i)
end
-- a source word's value from its raw 0..127 (the word: index, CC flag, direction, polarity, type)
local function src_value(word, raw)
  if word & 0x7f == 0 and word & 0x80 == 0 then return 1 end
  local ty, bip, neg = (word >> 10) & 0x3f, (word >> 9) & 1, (word >> 8) & 1
  local norm = raw / 128
  local base = neg == 1 and (1 - 1 / 128 - norm) or norm
  local v = base
  if bip == 1 then v = (base == 127 / 128) and base or (-1 + 2 * base) end
  if ty == 0 then return v end
  if ty == 3 then
    if bip == 0 then return v >= 0.5 and 1 or 0 end
    return v >= 0 and 1 or -1
  end
  local t = ty == 1 and CONCAVE or CONVEX
  if v >= 0 then return math.min(curve_tab(t, 128 * v), 127 / 128) end
  return -curve_tab(t, -128 * v)
end
local function src_fixed(word)      -- a source fixed for the note's life: none, velocity, key
  if word & 0x80 ~= 0 then return false end
  local idx = word & 0x7f
  return idx == 0 or idx == 2 or idx == 3
end
local function is_cc(word) return word & 0x80 ~= 0 end
local function mod_eval(m, key, vel)
  local function sv(word)
    if is_cc(word) then return src_value(word, m.ccraw or 0) end
    local idx = word & 0x7f
    return src_value(word, idx == 2 and vel or (idx == 3 and key or 0))
  end
  local v = m.amt * sv(m.src) * sv(m.asrc)
  if m.trans == 2 then v = math.abs(v) end
  return v
end
local function mod_same(a, b) return a.dest == b.dest and a.src == b.src and a.asrc == b.asrc end
-- m into list: an identical one has its amount replaced (add = false) or added to; else m is appended
local function mod_merge(list, m, add)
  for _, x in ipairs(list) do
    if mod_same(x, m) then
      if add then x.amt = x.amt + m.amt else x.amt = m.amt end
      return
    end
  end
  list[#list + 1] = { src = m.src, dest = m.dest, amt = m.amt, asrc = m.asrc, trans = m.trans }
end
-- destinations baked: the cutoff, Q, the mod envelope's depth to the cutoff, attenuation, pan, tuning, and the
-- envelope times (amp: delay 33 attack 34 hold 35 decay 36 release 38; mod: 25 26 27 28 30)
local MOD_DEST = { [8] = true, [9] = true, [11] = true, [48] = true, [17] = true, [52] = true, [51] = true,
  [33] = true, [34] = true, [35] = true, [36] = true, [38] = true, [25] = true, [26] = true, [27] = true, [28] = true, [30] = true }
local MOD_VEL2 = { [34] = true, [36] = true, [38] = true, [26] = true, [28] = true, [30] = true }
local MOD_DEST_NAME = { [0] = "start", [4] = "start", [5] = "lfo_pitch", [6] = "lfo_pitch", [7] = "mod_env_pitch",
  [10] = "lfo_cutoff", [13] = "lfo_volume", [15] = "chorus", [16] = "reverb", [21] = "lfo", [22] = "lfo", [23] = "lfo",
  [24] = "lfo", [29] = "mod_env_sustain", [37] = "sustain", [56] = "scale_tuning" }

local function clean(name) return (name:gsub("[%c=<>|\"#]", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end
local function secs(tc) if tc <= -12000 then return 0 end; return 2 ^ (tc / 1200) end
local function fmt(v)
  if v == math.floor(v) then return string.format("%d", v) end
  return (string.format("%.4f", v):gsub("0+$", ""):gsub("%.$", ""))
end

local function extract(sf2_path, out_dir, sub, track, probe)
  local report = { errors = {}, skipped = {}, ignored = {} }
  local res = { ok = false, report = report, presets = 0, regions = 0 }
  local f = io.open(sf2_path, "rb")
  if not f then report.errors[#report.errors + 1] = "cannot read " .. sf2_path; return res end
  local s = f:read("a"); f:close()
  local c, err = chunks(s)
  if not c then report.errors[#report.errors + 1] = err; return res end
  local phdr, pbag, pgen = records(s, c.phdr, 38), records(s, c.pbag, 4), records(s, c.pgen, 4)
  local inst, ibag, igen = records(s, c.inst, 22), records(s, c.ibag, 4), records(s, c.igen, 4)
  local shdr = records(s, c.shdr, 46)
  local imod = c.imod and records(s, c.imod, 10) or nil
  local pmod = c.pmod and records(s, c.pmod, 10) or nil
  local smpl0, smpln = c.smpl[1], c.smpl[2] // 2          -- 16-bit sample points
  local smplb = c.smpl[2]                                 -- ... and bytes (an SF3 stream's offsets)
  local function skip(why) report.skipped[why] = (report.skipped[why] or 0) + 1 end
  local function ignore(op)
    local n = type(op) == "string" and op or (GEN_NAME[op] or ("gen" .. op))
    report.ignored[n] = (report.ignored[n] or 0) + 1
  end

  -- the presets (the last record is the terminal EOP), sorted drums last, by bank and program
  local presets = {}
  for i = 1, #phdr - 1 do
    local p = phdr[i]
    presets[#presets + 1] = { name = clean(cstr(s, p, 20)), prog = u16(s, p + 20), bank = u16(s, p + 22),
                              bag = u16(s, p + 24), bag_end = u16(s, phdr[i + 1] + 24) }
  end
  -- every bank (2026-11-05, the owner: all variation banks). A variation preset that is an exact copy of the main
  -- bank's same program is left out: bank select falls back to that program anyway (gb_voice). A variation bank whose
  -- every preset copies bank 128's same kit is left out too, and its number plays the kits ("// bank" lines:
  -- GeneralUser's bank 120). "Exact copy" = the same zones, generator for generator and modulator for modulator.
  local function sig_of(p)
    local b0, b1 = pbag[p.bag + 1], pbag[p.bag_end + 1]
    if not b0 or not b1 then return nil end
    local g0, g1, m0, m1 = u16(s, b0), u16(s, b1), u16(s, b0 + 2), u16(s, b1 + 2)
    return s:sub(c.pgen[1] + g0 * 4, c.pgen[1] + g1 * 4 - 1) .. "|" ..
           (c.pmod and s:sub(c.pmod[1] + m0 * 10, c.pmod[1] + m1 * 10 - 1) or "")
  end
  local main_sig, kit_copies, bank_size = {}, {}, {}
  for _, p in ipairs(presets) do
    if p.bank == 0 or p.bank == 128 then main_sig[p.bank .. ":" .. p.prog] = sig_of(p) end
  end
  for _, p in ipairs(presets) do
    if p.bank ~= 0 and p.bank ~= 128 then
      p.sig = sig_of(p)
      bank_size[p.bank] = (bank_size[p.bank] or 0) + 1
      if p.sig and p.sig == main_sig["128:" .. p.prog] then kit_copies[p.bank] = (kit_copies[p.bank] or 0) + 1 end
    end
  end
  local kit_alias = {}               -- variation banks that are copies of the kits: their numbers play bank 128
  for b, n in pairs(bank_size) do if kit_copies[b] == n then kit_alias[#kit_alias + 1] = b end end
  table.sort(kit_alias)
  local keep = {}
  for _, p in ipairs(presets) do
    if p.bank == 0 or p.bank == 128 then keep[#keep + 1] = p
    elseif kit_copies[p.bank] == bank_size[p.bank] then skip("variation_kit_copy")
    elseif p.sig and p.sig == main_sig["0:" .. p.prog] then skip("variation_same_as_main")
    else keep[#keep + 1] = p end
  end
  -- bank 0, then the kits, then the variation banks (an older Gumbo, whose table fills first, keeps the kits)
  local function rank(b) return b == 0 and 0 or (b == 128 and 1 or 2) end
  table.sort(keep, function(a, b)
    if a.bank ~= b.bank then
      if rank(a.bank) ~= rank(b.bank) then return rank(a.bank) < rank(b.bank) end
      return a.bank < b.bank
    end
    return a.prog < b.prog
  end)
  local banked = #keep > 1

  local samples_dir = out_dir:gsub("[/\\]+$", "") .. "/" .. sub
  local written, failed_dir = {}, false
  local sf3f = {}                      -- a compressed sample's frames (-1 = unknown): its offsets are bytes, its loops frames
  local function wav_of(si)
    if written[si] ~= nil then return written[si] end
    local h = si and shdr[si + 1]
    if not h or si >= #shdr - 1 then skip("bad_sample_index"); written[si or -1] = false; return false end
    local stype = u16(s, h + 44)
    if stype & 0x8000 ~= 0 then skip("rom_sample"); written[si] = false; return false end
    local a, b = u32(s, h + 20), u32(s, h + 24)
    local base = string.format("%04d %s", si, clean(cstr(s, h, 20)):gsub("[/\\:%*%?]", " "))
    if stype & 0x10 ~= 0 then
      -- SF3 (2026-11-05): one complete Ogg Vorbis stream at bytes a .. b - 1 of smpl, written out as it is
      if b <= a or b > smplb then skip("bad_sample_bounds"); written[si] = false; return false end
      local data = s:sub(smpl0 + a, smpl0 + b - 1)
      if data:sub(1, 4) ~= "OggS" then skip("sf3_not_ogg"); written[si] = false; return false end   -- the flag means compressed, not Vorbis
      local name = base .. ".ogg"
      local wf = io.open(samples_dir .. "/" .. name, "wb")
      if not wf then failed_dir = true; written[si] = false; return false end
      wf:write(data); wf:close()
      written[si] = name; track[#track + 1] = name
      local frames = probe and probe(samples_dir .. "/" .. name) or nil
      sf3f[si] = (type(frames) == "number" and frames > 0) and math.floor(frames) or -1
      if sf3f[si] < 0 then report.sf3_unprobed = (report.sf3_unprobed or 0) + 1 end
      return name
    end
    if b <= a or b > smpln then skip("bad_sample_bounds"); written[si] = false; return false end
    local rate = u32(s, h + 36)
    local name = base .. ".wav"
    local data = s:sub(smpl0 + a * 2, smpl0 + b * 2 - 1)
    local wf = io.open(samples_dir .. "/" .. name, "wb")
    if not wf then failed_dir = true; written[si] = false; return false end
    wf:write("RIFF", le32(36 + #data), "WAVE", "fmt ", le32(16), le16(1), le16(1), le32(rate), le32(rate * 2), le16(2),
             le16(16), "data", le32(#data), data)
    wf:close()
    written[si] = name; track[#track + 1] = name
    return name
  end

  local L = {}
  local base = clean((sf2_path:match("([^/\\]+)$") or "bank"):gsub("%.[Ss][Ff][23]$", ""))
  L[#L + 1] = "// made by Gumbo from " .. (sf2_path:gsub("\\", "/"))
  L[#L + 1] = "<control> default_path=" .. sub .. "/"
  local curve_of, ncurve, curve_lines, used_cc = {}, 0, {}, {}   -- the live controllers' curves (one per shape), the CCs used
  local section = nil
  for _, p in ipairs(keep) do
    if banked and section ~= p.bank then
      section = p.bank
      -- gumbo_bank = the MIDI bank number(s) the section answers to (the converter's "// bank" lines)
      local nums = tostring(p.bank)
      if p.bank == 128 then for _, b in ipairs(kit_alias) do nums = nums .. "," .. b end end
      L[#L + 1] = "<global> gumbo_bank=" .. nums .. " global_label=" ..
                  (p.bank == 128 and "Drums" or p.bank == 0 and "Melodic" or ("Bank " .. p.bank))
    end
    L[#L + 1] = banked and string.format("<master> loprog=%d hiprog=%d master_label=%s", p.prog, p.prog, p.name ~= "" and p.name or ("Program " .. (p.prog + 1)))
                       or ("<master> master_label=" .. p.name)
    res.presets = res.presets + 1
    local pz = zones_of(s, pbag, pgen, p.bag, p.bag_end, G_INST, pmod)
    for _, pzone in ipairs(pz.zones) do
      -- preset level: global, then the zone over it (additive amounts)
      local pg = {}
      for k, v in pairs(pz.global or {}) do pg[k] = v end
      for k, v in pairs(pzone) do pg[k] = v end
      local ii = pg[G_INST]
      local ih = inst[ii + 1]
      if not ih or ii >= #inst - 1 then skip("bad_instrument_index")
      else
        local iz = zones_of(s, ibag, igen, u16(s, ih + 20), u16(s, inst[ii + 2] + 20), G_SAMPLE, imod)
        for _, izone in ipairs(iz.zones) do
          local g = defaults()
          for k, v in pairs(iz.global or {}) do g[k] = v end
          for k, v in pairs(izone) do g[k] = v end
          for k in pairs(g) do if not CARRIED[k] and k ~= "_mods" then ignore(k) end end
          for k in pairs(pg) do if not CARRIED[k] and k ~= "_mods" then ignore(k) end end
          -- ranges intersect; the rest adds (sample addresses, modes, class, root key are instrument-only)
          local kr, vr = g[G_KEYS], g[G_VELS]
          local pk, pv = pg[G_KEYS] or { 0, 127 }, pg[G_VELS] or { 0, 127 }
          local klo, khi = math.max(kr[1], pk[1]), math.min(kr[2], pk[2])
          local vlo, vhi = math.max(vr[1], pv[1], 1), math.min(vr[2], pv[2])
          local function add(op) return (g[op] or 0) + (pg[op] or 0) end
          local si = g[G_SAMPLE]
          if klo > khi or vlo > vhi then skip("empty_range")
          else
            local name = wav_of(si)
            if name then
              local h = shdr[si + 1]
              local a, b = u32(s, h + 20), u32(s, h + 24)
              local la, lb = u32(s, h + 28), u32(s, h + 32)
              -- an SF3 stream: its offsets are bytes (meaningless here); the loops are frames of the decoded sample,
              -- so the sample starts at 0 and ends at the probed length (unknown: no end, every loop trusted)
              if sf3f[si] then a = 0; b = sf3f[si] >= 0 and sf3f[si] or math.huge end
              local opitch, pcorr = u8(s, h + 40), u8(s, h + 41)
              if pcorr >= 128 then pcorr = pcorr - 256 end
              local root = (g[G_ROOT] and g[G_ROOT] >= 0) and g[G_ROOT] or (opitch <= 127 and opitch or 60)
              local so = (g[G_START] or 0) + (g[G_START_C] or 0) * 32768
              local eo = (g[G_END] or 0) + (g[G_END_C] or 0) * 32768
              local ls = la - a + (g[G_SLOOP] or 0) + (g[G_SLOOP_C] or 0) * 32768
              local le = lb - a + (g[G_ELOOP] or 0) + (g[G_ELOOP_C] or 0) * 32768 - 1
              local len = b - a
              local mode = (g[G_MODES] or 0) & 3
              local lm = (mode == 1 and "loop_continuous") or (mode == 3 and "loop_sustain") or "no_loop"
              if lm ~= "no_loop" and not (ls >= 0 and le > ls and le < len) then lm = "no_loop"; skip("bad_loop_kept_unlooped") end
              local sus_cb = math.max(0, math.min(1440, add(G_SUS)))
              local fc_g, qcb_g = add(G_FC), add(G_Q)
              local env2fc_g, lfo2fc = add(G_ENV2FC), add(G_LFO2FC)
              local atten_g = 0.4 * math.max(0, add(G_ATTEN))        -- cB x 0.4 (FluidSynth: the generator only)
              local tune_g, pan_g = add(G_FINE) + pcorr, add(G_PAN)
              local tgen = { [33] = add(G_DELAY), [34] = add(G_ATT), [35] = add(G_HOLD), [36] = add(G_DEC), [38] = add(G_REL),
                             [25] = add(G_MDLY), [26] = add(G_MATT), [27] = add(G_MHOLD), [28] = add(G_MDEC), [30] = add(G_MREL) }
              -- the modulators of this zone pair: the default, the instrument's over it, the preset's added
              local ml = { { src = 0x0502, dest = 48, amt = 960, asrc = 0, trans = 0 } }
              local function level(glob, zone, padd)
                local lv = {}
                for _, m in ipairs(glob and glob._mods or {}) do mod_merge(lv, m, false) end
                for _, m in ipairs(zone._mods or {}) do mod_merge(lv, m, false) end
                for _, m in ipairs(lv) do if not padd or m.amt ~= 0 then mod_merge(ml, m, padd) end end
              end
              level(iz.global, izone, false); level(pz.global, pzone, true)
              local byd, live = {}, {}        -- live: controller-driven, to the attenuation (48) or the cutoff (8)
              for _, m in ipairs(ml) do
                local cw = is_cc(m.src) and m.src or (is_cc(m.asrc) and m.asrc or nil)   -- the controller word, if one
                local ow = cw == m.src and m.asrc or m.src                               -- the other source
                if m.amt == 0 or (m.dest == 8 and m.src == 0x0102 and m.asrc == 0x0C02) then   -- (the second: 0 in FluidSynth)
                elseif not MOD_DEST[m.dest] then ignore("mod_to_" .. (MOD_DEST_NAME[m.dest] or (GEN_NAME[m.dest] or ("gen" .. m.dest))))
                elseif not src_fixed(ow) then
                  local i = ow & 0x7f
                  ignore(is_cc(ow) and ("mod_cc" .. i) or (i == 13 and "mod_pressure" or (i == 10 and "mod_poly_pressure" or "mod_pitch_wheel")))
                elseif cw and m.trans ~= 2 and (m.dest == 48 or m.dest == 8) then
                  m.cw, m.ow, m.cc = cw, ow, cw & 0x7f
                  live[#live + 1] = m
                  if m.dest == 8 then m.ccraw = 0; byd[8] = byd[8] or {}; table.insert(byd[8], m) end   -- the line's foot
                elseif cw then
                  m.ccraw = CC_START[cw & 0x7f] or 0
                  report.mod_cc_fixed = (report.mod_cc_fixed or 0) + 1
                  byd[m.dest] = byd[m.dest] or {}; table.insert(byd[m.dest], m)
                else byd[m.dest] = byd[m.dest] or {}; table.insert(byd[m.dest], m) end
              end
              -- the live controllers' tokens for a cell: the other source at the cell's middle; a shape other than a
              -- straight rising line gets a <curve> of its own (one per shape in the bank); the cutoff takes one
              -- controller, the straight line through its ends
              local function live_tokens(P, r, filtered)
                local vol, fc, fcn = {}, 0, nil
                for _, m in ipairs(live) do
                  local other = src_value(m.ow, (m.ow & 0x7f) == 2 and P.vm or ((m.ow & 0x7f) == 3 and P.km or 0))
                  if m.dest == 48 then
                    local shape = m.cw & 0xff00
                    local ci = 0
                    if shape ~= 0 then
                      if not curve_of[shape] then
                        ncurve = ncurve + 1; curve_of[shape] = 6 + ncurve
                        local cv = { "<curve> curve_index=" .. (6 + ncurve) }
                        for x = 0, 127 do cv[#cv + 1] = string.format("v%03d=%s", x, fmt(src_value(m.cw, x))) end
                        curve_lines[#curve_lines + 1] = table.concat(cv, " ")
                      end
                      ci = curve_of[shape]
                    end
                    local t = vol[m.cc]
                    if t and t[2] ~= ci then report.mod_cc_merged = (report.mod_cc_merged or 0) + 1 end
                    vol[m.cc] = { (t and t[1] or 0) - m.amt * other / 10, t and t[2] or ci }
                  else
                    local sl = m.amt * other * (src_value(m.cw, 127) - src_value(m.cw, 0))
                    if (m.cw & 0xfc00) ~= 0 then report.mod_cc_approx = (report.mod_cc_approx or 0) + 1 end
                    if fcn == nil or m.cc == fcn then fcn = m.cc; fc = fc + sl
                    elseif math.abs(sl) > math.abs(fc) then ignore("mod_cc" .. fcn); fcn = m.cc; fc = sl
                    else ignore("mod_cc" .. m.cc) end
                  end
                end
                for cc, t in pairs(vol) do
                  r[#r + 1] = "volume_oncc" .. cc .. "=" .. fmt(t[1])
                  if t[2] ~= 0 then r[#r + 1] = "volume_curvecc" .. cc .. "=" .. t[2] end
                  used_cc[cc] = true; report.mod_cc_live = (report.mod_cc_live or 0) + 1
                end
                if fcn and fc ~= 0 and filtered then
                  r[#r + 1] = "cutoff_oncc" .. fcn .. "=" .. fmt(fc)
                  used_cc[fcn] = true; report.mod_cc_live = (report.mod_cc_live or 0) + 1
                end
              end
              local function tot(dest, k, v)
                local l = byd[dest]; if not l then return 0 end
                local t = 0
                for _, m in ipairs(l) do t = t + mod_eval(m, k, v) end
                return t
              end
              local function velmod(m) return (m.src & 0x7f) == 2 or (m.asrc & 0x7f) == 2 end
              local function att_fixed(k, v)
                local t = 0
                for _, m in ipairs(byd[48] or {}) do if not velmod(m) then t = t + mod_eval(m, k, v) end end
                return t
              end
              -- the region's picture of a key x velocity cell: the cutoff as base + keytrack + veltrack (straight
              -- lines through the cell's edges), the envelope depth as base + vel2depth, each time as base + vel2
              -- (seconds, sfizz's form), the rest at the cell's middle
              local function model(ka, kb, va, vb)
                local km, vm = (ka + kb) // 2, (va + vb) // 2
                local P = { ka = ka, kb = kb, va = va, vb = vb, km = km, vm = vm, t = {} }
                local function f(k, v) return fc_g + tot(8, k, v) end
                P.fc0 = f(km, va)
                P.fkt = kb > ka and (f(kb, va) - f(ka, va)) / (kb - ka) or 0
                P.fvt = vb > va and (f(km, vb) - f(km, va)) / (vb - va) or 0
                P.q = qcb_g + tot(9, km, vm)
                P.d0 = env2fc_g + tot(11, km, va)
                P.dvt = vb > va and (tot(11, km, vb) - tot(11, km, va)) / (vb - va) or 0
                P.pan = tot(17, km, vm); P.tune = tot(52, km, vm) + 100 * tot(51, km, vm); P.att = att_fixed(km, vm)
                for st, tc in pairs(tgen) do
                  if MOD_VEL2[st] and vb > va then
                    local t0, t1 = secs(tc + tot(st, km, va)), secs(tc + tot(st, km, vb))
                    local sl = (t1 - t0) / (vb - va)
                    P.t[st] = { t0 - sl * va, sl }
                  else P.t[st] = { secs(tc + tot(st, km, vm)), 0 } end
                end
                -- the attenuation's velocity part: the default's family (concave velocity, 1 source) is a power of
                -- v/127 -- 960 cB = the square; anything else becomes amp_velcurve points
                local velm, pw, family = {}, 0, true
                for _, m in ipairs(byd[48] or {}) do
                  if velmod(m) then
                    velm[#velm + 1] = m
                    if m.src == 0x0502 and m.asrc == 0 then pw = pw + m.amt else family = false end
                  end
                end
                if family and pw >= 0 then P.vpow = pw / 480
                else
                  P.vcurve = {}
                  for _, v in ipairs({ 1, 8, 16, 24, 32, 48, 64, 80, 96, 112, 127 }) do
                    local at = 0
                    for _, m in ipairs(velm) do at = at + mod_eval(m, km, v) end
                    P.vcurve[#P.vcurve + 1] = { v, math.max(0, math.min(1, 10 ^ (-at / 200))) }
                  end
                end
                return P
              end
              -- the picture's misses at one point, each in units of its tolerance (1 = at the limit): 50 cents on the
              -- cutoff and the depth, 3 dB on Q (as clamped), 1 dB on level, 10 % on pan, 10 cents, 12 % on a time
              local function errs(P, k, v)
                local e = {}
                if byd[8] then e[#e + 1] = (P.fc0 + P.fkt * (k - P.km) + P.fvt * (v - P.va) - fc_g - tot(8, k, v)) / 50 end
                if byd[11] then e[#e + 1] = (P.d0 + P.dvt * (v - P.va) - env2fc_g - tot(11, k, v)) / 50 end
                if byd[9] then e[#e + 1] = (math.max(0, math.min(960, P.q)) - math.max(0, math.min(960, qcb_g + tot(9, k, v)))) / 30 end
                if byd[48] then e[#e + 1] = (P.att - att_fixed(k, v)) / 10 end
                if byd[17] then e[#e + 1] = (P.pan - tot(17, k, v)) / 100 end
                if byd[52] or byd[51] then e[#e + 1] = (P.tune - tot(52, k, v) - 100 * tot(51, k, v)) / 10 end
                for st, tc in pairs(tgen) do
                  if byd[st] then
                    local want = secs(tc + tot(st, k, v))
                    e[#e + 1] = (P.t[st][1] + P.t[st][2] * v - want) / math.max(want, 0.01) / 0.12
                  end
                end
                return e
              end
              -- the worst miss over sample points; with kref, only the part that changes with the key (the miss at
              -- (k, v) less the miss at (kref, v)), so a velocity-only miss never cuts keys
              local function miss(P, keys, vels, kref)
                local worst = 0
                for _, v in ipairs(vels) do
                  local ref = kref and errs(P, kref, v) or nil
                  for _, k in ipairs(keys) do
                    local e = errs(P, k, v)
                    for i = 1, #e do worst = math.max(worst, math.abs(e[i] - (ref and ref[i] or 0))) end
                  end
                end
                return worst
              end
              -- the cells: one, split by key or by velocity until the picture fits (at most 48 regions a zone)
              local cells = {}
              local function cut(ka, kb, va, vb, depth)
                local P = model(ka, kb, va, vb)
                if next(byd) and depth < 6 and #cells < 40 then
                  local ks, vs = { ka, P.km, kb }, {}
                  if kb - ka >= 8 then ks = { ka, ka + (kb - ka) // 4, P.km, ka + 3 * (kb - ka) // 4, kb } end
                  local step = math.max(1, (vb - va) // 16)
                  for v = va, vb, step do vs[#vs + 1] = v end
                  if vs[#vs] ~= vb then vs[#vs + 1] = vb end
                  local ek, ev = miss(P, ks, { va, P.vm, vb }, P.km), miss(P, { P.km }, vs)
                  if ek > 1 and kb > ka and ek >= ev then
                    local m = (ka + kb) // 2
                    cut(ka, m, va, vb, depth + 1); cut(m + 1, kb, va, vb, depth + 1); return
                  elseif ev > 1 and vb - va >= 3 then
                    local m = (va + vb) // 2
                    cut(ka, kb, va, m, depth + 1); cut(ka, kb, m + 1, vb, depth + 1); return
                  end
                end
                cells[#cells + 1] = P
              end
              cut(klo, khi, vlo, vhi, 0)
              if #cells > 1 then report.mod_split = (report.mod_split or 0) + #cells - 1 end
              local function hz(c) return 8.175799 * 2 ^ (c / 1200) end
              for _, P in ipairs(cells) do
                -- the filter: on when it does anything (13500 cents with no resonance and nothing moving it is
                -- inaudible: FluidSynth runs it anyway, Gumbo saves the cost); the cell's lowest cutoff decides
                local fc_lo = math.min(P.fc0 + P.fkt * (P.ka - P.km), P.fc0 + P.fkt * (P.kb - P.km),
                                       P.fc0 + P.fkt * (P.ka - P.km) + P.fvt * (P.vb - P.va), P.fc0 + P.fkt * (P.kb - P.km) + P.fvt * (P.vb - P.va))
                local qcb = math.max(0, math.min(960, P.q))
                local depth, vdepth = P.d0 - P.dvt * P.va, P.dvt * 127
                local filtered = fc_lo < 13500 or qcb > 0 or depth ~= 0 or vdepth ~= 0 or lfo2fc ~= 0
                local fres = qcb / 10 - 3.01
                local vol = -(atten_g + P.att) / 10
                if filtered then vol = vol - 10 * math.log(10 ^ (fres / 20) / 10 ^ (-3.01 / 20), 10) end
                local function tm(st) return P.t[st][1], P.t[st][2] * 127 end
                local att0, attv = tm(34); local dec0, decv = tm(36); local rel0, relv = tm(38)
                local r = { "<region> sample=" .. name,
                  "lokey=" .. P.ka, "hikey=" .. P.kb, "lovel=" .. P.va, "hivel=" .. P.vb, "pitch_keycenter=" .. root,
                  "pitch_keytrack=" .. fmt(add(G_SCALE)), "transpose=" .. fmt(add(G_COARSE)),
                  "tune=" .. fmt(tune_g + P.tune),
                  "volume=" .. fmt(vol),     -- dB, less a resonant filter's drop
                  "pan=" .. fmt(math.max(-100, math.min(100, (pan_g + P.pan) / 5))),
                  "ampeg_delay=" .. fmt(P.t[33][1]), "ampeg_attack=" .. fmt(att0),
                  "ampeg_hold=" .. fmt(P.t[35][1]), "ampeg_decay=" .. fmt(dec0),
                  "ampeg_sustain=" .. fmt(100 * 10 ^ (-sus_cb / 200)), "ampeg_release=" .. fmt(relv == 0 and math.max(0.001, rel0) or rel0),
                  "loop_mode=" .. lm }
                if attv ~= 0 then r[#r + 1] = "ampeg_vel2attack=" .. fmt(attv) end
                if decv ~= 0 then r[#r + 1] = "ampeg_vel2decay=" .. fmt(decv) end
                if relv ~= 0 then r[#r + 1] = "ampeg_vel2release=" .. fmt(relv) end
                -- key-scaled hold and decay (generators 39 / 40; 2026-11-05): Gumbo's own opcodes, timecents a key as
                -- the SoundFont has them (FluidSynth: the time x 2^(k x (60 - key) / 1200))
                local kah, kad = add(39), add(40)
                if kah ~= 0 then r[#r + 1] = "ampeg_hold_keytrack=" .. fmt(kah) end
                if kad ~= 0 then r[#r + 1] = "ampeg_decay_keytrack=" .. fmt(kad) end
                if P.vpow then
                  if P.vpow == 0 then r[#r + 1] = "amp_veltrack=0"
                  elseif P.vpow ~= 2 then r[#r + 1] = "amp_velpow=" .. fmt(P.vpow) end
                else
                  for _, pt in ipairs(P.vcurve) do r[#r + 1] = "amp_velcurve_" .. pt[1] .. "=" .. fmt(pt[2]) end
                end
                if lm ~= "no_loop" then r[#r + 1] = "loop_start=" .. ls; r[#r + 1] = "loop_end=" .. le end
                if so > 0 and so < len then r[#r + 1] = "offset=" .. so end
                if eo < 0 and len ~= math.huge and len + eo > so then r[#r + 1] = "end=" .. (len + eo - 1) end
                if eo < 0 and len == math.huge then ignore("sf3_end_unprobed") end
                if filtered then
                  r[#r + 1] = "fil_type=lpf_2p"
                  r[#r + 1] = "cutoff=" .. fmt(hz(P.fc0 - P.fvt * P.va)); r[#r + 1] = "resonance=" .. fmt(fres)
                  if P.fkt ~= 0 then r[#r + 1] = "fil_keytrack=" .. fmt(P.fkt); r[#r + 1] = "fil_keycenter=" .. P.km end
                  if P.fvt ~= 0 then r[#r + 1] = "fil_veltrack=" .. fmt(P.fvt * 127) end
                  if depth ~= 0 or vdepth ~= 0 then
                    local ma0, mav = tm(26); local md0, mdv = tm(28); local mr0, mrv = tm(30)
                    r[#r + 1] = "fileg_depth=" .. fmt(depth)
                    if vdepth ~= 0 then r[#r + 1] = "fileg_vel2depth=" .. fmt(vdepth) end
                    r[#r + 1] = "fileg_delay=" .. fmt(P.t[25][1]); r[#r + 1] = "fileg_attack=" .. fmt(ma0)
                    r[#r + 1] = "fileg_hold=" .. fmt(P.t[27][1]); r[#r + 1] = "fileg_decay=" .. fmt(md0)
                    r[#r + 1] = "fileg_sustain=" .. fmt(math.max(0, math.min(100, 100 - add(G_MSUS) / 10)))
                    r[#r + 1] = "fileg_release=" .. fmt(mrv == 0 and math.max(0.001, mr0) or mr0)
                    if mav ~= 0 then r[#r + 1] = "fileg_vel2attack=" .. fmt(mav) end
                    if mdv ~= 0 then r[#r + 1] = "fileg_vel2decay=" .. fmt(mdv) end
                    if mrv ~= 0 then r[#r + 1] = "fileg_vel2release=" .. fmt(mrv) end
                  end
                end
                -- the mod envelope on the pitch (generator 7, cents at its peak; 2026-11-05): the same envelope as the
                -- filter's, written as SFZ's pitcheg_* -- with or without a filter
                local penv = add(7)
                if penv ~= 0 then
                  local ma0, mav = tm(26); local md0, mdv = tm(28); local mr0, mrv = tm(30)
                  r[#r + 1] = "pitcheg_depth=" .. fmt(penv)
                  r[#r + 1] = "pitcheg_delay=" .. fmt(P.t[25][1]); r[#r + 1] = "pitcheg_attack=" .. fmt(ma0)
                  r[#r + 1] = "pitcheg_hold=" .. fmt(P.t[27][1]); r[#r + 1] = "pitcheg_decay=" .. fmt(md0)
                  r[#r + 1] = "pitcheg_sustain=" .. fmt(math.max(0, math.min(100, 100 - add(G_MSUS) / 10)))
                  r[#r + 1] = "pitcheg_release=" .. fmt(mrv == 0 and math.max(0.001, mr0) or mr0)
                  if mav ~= 0 then r[#r + 1] = "pitcheg_vel2attack=" .. fmt(mav) end
                  if mdv ~= 0 then r[#r + 1] = "pitcheg_vel2decay=" .. fmt(mdv) end
                  if mrv ~= 0 then r[#r + 1] = "pitcheg_vel2release=" .. fmt(mrv) end
                end
                -- the mod envelope's key scaling (generators 31 / 32), when that envelope drives the cutoff or the pitch
                if (filtered and (depth ~= 0 or vdepth ~= 0)) or penv ~= 0 then
                  local kfh, kfd = add(31), add(32)
                  if kfh ~= 0 then r[#r + 1] = "fileg_hold_keytrack=" .. fmt(kfh) end
                  if kfd ~= 0 then r[#r + 1] = "fileg_decay_keytrack=" .. fmt(kfd) end
                end
                -- the LFOs: frequency in absolute cents (0 = 8.176 Hz), delay in timecents; both triangles (lfoN_wave 0)
                local vib, mpitch = add(G_VIB2PITCH), add(G_LFO2PITCH)
                if vib == 0 and mpitch ~= 0 then
                  -- vibrato drawn on the mod LFO: it takes the pitch LFO (the mod wheel's vibrato rides on it)
                  r[#r + 1] = "lfo01_freq=" .. fmt(hz(add(G_MLFO_FRQ))); r[#r + 1] = "lfo01_delay=" .. fmt(secs(add(G_MLFO_DLY)))
                  r[#r + 1] = "lfo01_pitch=" .. fmt(mpitch)
                else
                  r[#r + 1] = "lfo01_freq=" .. fmt(hz(add(G_VLFO_FRQ))); r[#r + 1] = "lfo01_delay=" .. fmt(secs(add(G_VLFO_DLY)))
                  if vib ~= 0 then r[#r + 1] = "lfo01_pitch=" .. fmt(vib) end
                  if mpitch ~= 0 then ignore(G_LFO2PITCH) end
                end
                r[#r + 1] = "lfo01_pitch_oncc1=50"            -- the default modulator: the mod wheel's vibrato
                local mvol, mfc = add(G_LFO2VOL) / 10, filtered and lfo2fc or 0   -- (+ cB = louder on the swing up: FluidSynth)
                if mvol ~= 0 or mfc ~= 0 then
                  r[#r + 1] = "lfo02_freq=" .. fmt(hz(add(G_MLFO_FRQ))); r[#r + 1] = "lfo02_delay=" .. fmt(secs(add(G_MLFO_DLY)))
                  if mvol ~= 0 then r[#r + 1] = "lfo02_volume=" .. fmt(mvol) end
                  if mfc ~= 0 then r[#r + 1] = "lfo02_cutoff=" .. fmt(mfc) end
                end
                local ex = g[G_EXCL] or 0
                if ex > 0 then r[#r + 1] = "group=" .. ex; r[#r + 1] = "off_by=" .. ex end
                if #live > 0 then live_tokens(P, r, filtered) end
                L[#L + 1] = table.concat(r, " ")
                res.regions = res.regions + 1
              end
            end
          end
        end
      end
    end
  end
  if failed_dir then report.errors[#report.errors + 1] = "cannot write the samples into " .. samples_dir; return res end
  if res.regions == 0 then report.errors[#report.errors + 1] = "no playable zones"; return res end
  -- the live controllers: their starting values and names on the <control> line, their curves after it
  local ccs = {}
  for cc in pairs(used_cc) do ccs[#ccs + 1] = cc end
  table.sort(ccs)
  for _, cc in ipairs(ccs) do
    if CC_START[cc] then L[2] = L[2] .. " set_cc" .. cc .. "=" .. CC_START[cc] end
    L[2] = L[2] .. " label_cc" .. cc .. "=" .. (CC_NAME[cc] or ("CC " .. cc))
  end
  for i = #curve_lines, 1, -1 do table.insert(L, 3, curve_lines[i]) end
  local sfz = out_dir:gsub("[/\\]+$", "") .. "/" .. base .. ".sfz"
  local of = io.open(sfz, "wb")
  if not of then report.errors[#report.errors + 1] = "cannot write " .. sfz; return res end
  of:write(table.concat(L, "\n"), "\n"); of:close()
  res.ok, res.sfz = true, sfz
  return res
end

function S.extract(sf2_path, out_dir, sub, probe)
  local track = {}
  local ok, res = pcall(extract, sf2_path, out_dir, sub or "samples", track, probe)
  if not ok then
    res = { ok = false, presets = 0, regions = 0,
            report = { errors = { "damaged SoundFont: " .. tostring(res) }, skipped = {}, ignored = {} } }
  end
  res.written = track                  -- every sample file written, whatever happened
  return res
end

return S
