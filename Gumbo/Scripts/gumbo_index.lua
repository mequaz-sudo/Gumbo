-- Copyright (c) 2026 EON Studios (Quaz). All rights reserved. Free to use: see Gumbo_LICENSE.md.
-- gumbo_index.lua -- Gumbo's instrument list (Data/EON_Gumbo/library.txt, the browser reads it): THE master copy of
-- its rules -- the family guess, the line format, the order. The offline library builder
-- (.dev_tests/gumbo_index_build.py, through lupa) and the Gumbo helper inside REAPER both load this file; nothing else
-- may re-implement them. Pure Lua 5.4, no reaper.* calls, no file access: callers find the files and hand over each
-- one's path and the start of its text.
--
-- The list (UTF-8 text, a .txt so a JSFX opens it in text mode -- spec §0c):
--     // gumbo-index 1
--     family|name|ram_mb|regions|absolute path        one line per instrument: families in TILE order (X.TILES),
--     // end                                           then by name (any case), then by path
-- Gumbo reads several lists in Data/EON_Gumbo, in this order (gb_face.jsfx-inc gbf_idx_load), each with its own
-- writer so no package ever touches another's list or the user's:
--     starter.txt      the free starter that comes with Gumbo (VSCO 2 CE Starter, 12 instruments)
--     pack1.txt        the full VSCO 2 CE orchestra, a free extra download (the 63 instruments not in the starter)
--     pack2..9.txt     free slots for later sound packs: claim one HERE before a package uses it
--     library.txt      the user's own imports (the helper, Add a library)
-- (the packages' lists come from .dev_tests/gumbo_library_build.py, which holds the starter's instrument list)
-- Families are the browser's tiles, X.TILES -- the SAME names in the same order as gb_face.jsfx-inc's gbf_fam_name
-- (Gumbo drops a line whose family is not a tile); .dev_tests/gumbo_index_test.py fails when the two drift.
--
-- API:  local X = dofile(".../gumbo_index.lua")
--       X.family(path)            -> the family guessed from the path
--       X.header(text)            -> regions, ram_mb read from a converted file's "// regions N of M; ..." line
--       X.entry(path, head)       -> { family, name, mb, regions, path } for one .gumbo.txt
--       X.build(entries)          -> the whole list text (sorted)
--       X.parse(text)             -> the entries of an existing list (X.build(X.parse(t)) == t for a list it wrote)
--       X.icon(name, path, family) -> the EON track icon for an instrument (a free icon's file name, no .png)
--       X.TILES (display order), X.FAMILIES (guess order), X.FORMAT_VERSION

local X = {}
X.FORMAT_VERSION = 1

-- the browser's tiles, in their order (= gb_face.jsfx-inc gbf_fam_name, checked by the test)
X.TILES = { "Drums", "808s", "Bass", "Keys", "E-Piano", "Pads", "Leads", "Strings", "Brass", "Winds", "Plucks", "Vox" }
-- the guess: first match wins, tested against the lower-cased path (folder names count: "gogodze" is a drum library).
-- Its order is the GUESS priority ("808" before "kit", "pianet" before "piano"), not the display order.
X.FAMILIES = {
  -- names that hold another family's word come first ("bassoon" is not a bass, "contrabass" is a string)
  { "Winds",   { "bassoon" } },
  { "Strings", { "contrabass" } },
  { "Bass",    { "upright bass", "upright_bass", "uprightbass" } },   -- before "upright" (a piano)
  { "Keys",    { "upright" } },
  { "Drums",   { "timpani" } },
  { "Plucks",  { "glockenspiel", "marimba", "xylophone", "tubular", "vibraphone", "celesta" } },   -- tuned percussion
  { "808s",    { "808" } },
  { "Drums",   { "drum", "kit", "kick", "snare", "tom", "hat", "perc", "gogodze" } },
  { "E-Piano", { "wurl", "rhodes", "e-piano", "epiano", "pianet", "cp80", "clav" } },
  { "Keys",    { "piano", "organ", "harpsi", "keys" } },
  { "Bass",    { "bass" } },
  { "Pads",    { "pad" } },
  { "Leads",   { "lead", "synth" } },
  { "Strings", { "string", "cello", "violin", "viola", "orchestra" } },
  { "Brass",   { "brass", "tuba", "trumpet", "trombone", "horn" } },
  { "Winds",   { "sax", "flute", "piccolo", "clarinet", "oboe", "wind" } },
  { "Plucks",  { "guitar", "harp", "banjo", "pluck", "zither" } },
  { "Vox",     { "vox", "vocal", "choir", "voice" } },
}
-- when nothing matches: "Other" (the owner's choice, 2026-10-30) -- Gumbo lists it under ALL INSTRUMENTS, no tile
-- (gb_face gbf_fam_name 12; helper plan step 4). It sorts after every tile.
X.OTHER = "Other"
X.FALLBACK = X.OTHER
local ORDER = {}
for i, name in ipairs(X.TILES) do ORDER[name] = i end

function X.family(path)
  local low = tostring(path):gsub("\\", "/"):lower()
  for _, f in ipairs(X.FAMILIES) do
    for _, k in ipairs(f[2]) do
      if low:find(k, 1, true) then return f[1] end
    end
  end
  return X.FALLBACK
end

function X.header(text)
  local regions, mb = tostring(text):match("regions (%d+) of %d+; sample files %d+; RAM when loaded ([%d.]+) MB")
  return tonumber(regions) or 0, tonumber(mb) or 0
end

-- the browser's name for a file name: words split where a library ran them together ("CelloEnsSusVib" ->
-- "Cello Section Sustain Vibrato"), the usual sample-library shorthand spelled out, "-KS" (every playing style on
-- keyswitches) and "-Quiet" said in words. Whole words only, so a name of the user's own keeps its spelling
-- ("alpha bass" stays as it is). WORDS and WHOLE are the tables to extend.
local WORDS = { Ens = "Section", Sus = "Sustain", Stac = "Staccato", Spic = "Spiccato", Pizz = "Pizzicato",
  Trem = "Tremolo", Vib = "Vibrato", VB = "Vibrato", NV = "Non-Vibrato", Exp = "Expressive", Perc = "Percussion",
  Contrabass = "Double Bass" }
local SOLO = { Violin = true, Viola = true, Cello = true }
local WHOLE = { VSUpright1 = "Upright Piano 2", ["GM-StylePerc"] = "GM Percussion" }
function X.pretty(name)
  name = tostring(name)
  if WHOLE[name] then return WHOLE[name] end
  local tail = ""
  local base = name:match("^(.-)%-[Kk][Ss]$")
  if base then name, tail = base, " (all styles)" end
  base = name:match("^(.-)%-[Qq]uiet$")
  if base then name, tail = base, " (quiet)" .. tail end
  local s = name:gsub("_", " ")
  s = s:gsub("(%l)(%u)", "%1 %2"):gsub("(%u)(%u%l)", "%1 %2")   -- digits stay with their word ("EP200")
  local out, words = {}, {}
  for w in s:gmatch("%S+") do words[#words + 1] = w end
  for i, w in ipairs(words) do
    local nxt = words[i + 1]
    if w == "S" and nxt and SOLO[nxt] then out[#out + 1] = "Solo"
    elseif w == "F" and nxt == "Horn" then out[#out + 1] = "French"
    else out[#out + 1] = WORDS[w] or w end
  end
  return table.concat(out, " ") .. tail
end

local SUFFIX = ".gumbo.txt"
function X.entry(path, head)
  path = tostring(path):gsub("\\", "/")
  local file = path:match("([^/]*)$")
  local name = file
  if file:lower():sub(-#SUFFIX) == SUFFIX then name = file:sub(1, #file - #SUFFIX) end
  local regions, mb = X.header(head or "")
  return { family = X.family(path), name = (X.pretty(name):gsub("|", "/")), mb = mb, regions = regions, path = path }
end

function X.build(entries)
  local rows = {}
  for _, e in ipairs(entries) do rows[#rows + 1] = e end
  table.sort(rows, function(a, b)
    local oa, ob = ORDER[a.family] or 99, ORDER[b.family] or 99
    if oa ~= ob then return oa < ob end
    local na, nb = a.name:lower(), b.name:lower()
    if na ~= nb then return na < nb end
    return a.path < b.path          -- a full order: the same list whatever order the files were found in
  end)
  local L = { string.format("// gumbo-index %d", X.FORMAT_VERSION) }
  for _, r in ipairs(rows) do
    L[#L + 1] = string.format("%s|%s|%.1f|%d|%s", r.family, r.name, r.mb, r.regions, r.path)
  end
  L[#L + 1] = "// end"
  return table.concat(L, "\n") .. "\n", rows
end

-- an existing list back into entries; lines that are not entries (the // lines, blanks) are skipped
function X.parse(text)
  local out = {}
  for line in (tostring(text or "") .. "\n"):gmatch("([^\n]*)\n") do
    line = line:gsub("\r$", "")
    if not line:match("^//") then
      local fam, name, mb, regions, path = line:match("^([^|]+)|([^|]*)|([^|]*)|([^|]*)|(.+)$")
      if fam then
        out[#out + 1] = { family = fam, name = name, mb = tonumber(mb) or 0, regions = math.floor(tonumber(regions) or 0),
                          path = path }
      end
    end
  end
  return out
end

-- ── the track icon for an instrument (2026-11-01; the Gumbo helper puts it on the track) ──────────────────────────
-- First keyword found in the lower-cased name, then path, wins; else the family's icon. Every icon named here is in the
-- FREE EON set (.dev_tests/rkfx_icons_draw.py FREE; gumbo_index_test.py checks), so anyone with ReaKit FX or Gumbo's
-- sound package has the file. Order matters as in X.FAMILIES ("bassoon" before "bass", "upright bass" before "upright").
X.ICON_WORDS = {
  { "bassoon", "bassoon" }, { "contrabass", "upright_bass" }, { "upright bass", "upright_bass" }, { "uprightbass", "upright_bass" },
  { "oboe", "oboe" }, { "clarinet", "clarinet" }, { "piccolo", "flute" }, { "flute", "flute" }, { "sax", "saxophone" },
  { "trombone", "trombone" }, { "tuba", "tuba" }, { "trumpet", "trumpet" }, { "horn", "brass" }, { "timpani", "timpani" },
  { "viola", "violin" }, { "violin", "violin" }, { "cello", "cello" }, { "harp", "harp" },
  { "marimba", "mallets" }, { "xylophone", "mallets" }, { "glockenspiel", "mallets" }, { "vibraphone", "mallets" },
  { "celesta", "mallets" }, { "tubular", "mallets" },
  { "organ", "organ" }, { "wurl", "electric_piano" }, { "rhodes", "electric_piano" }, { "e-piano", "electric_piano" },
  { "epiano", "electric_piano" }, { "pianet", "electric_piano" }, { "piano", "piano" }, { "upright", "piano" },
  { "choir", "choir" }, { "vox", "vocal" }, { "vocal", "vocal" }, { "voice", "vocal" }, { "guitar", "guitar" },
  { "808", "kick" }, { "kick", "kick" }, { "snare", "snare" }, { "kit", "drum_kit" }, { "drum", "drum_kit" },
  { "perc", "percussion" }, { "string", "strings" }, { "pad", "synth_pad" }, { "lead", "synth_lead" }, { "synth", "synth" },
  { "bass", "bass" },
}
X.FAMILY_ICON = { Drums = "drum_kit", ["808s"] = "kick", Bass = "bass", Keys = "piano", ["E-Piano"] = "electric_piano",
                  Pads = "synth_pad", Leads = "synth_lead", Strings = "strings", Brass = "brass", Winds = "flute",
                  Plucks = "guitar", Vox = "vocal", Other = "keys" }
function X.icon(name, path, family)
  for _, s in ipairs({ tostring(name or ""):lower(), tostring(path or ""):lower() }) do
    for _, w in ipairs(X.ICON_WORDS) do if s:find(w[1], 1, true) then return w[2] end end
  end
  return X.FAMILY_ICON[family] or "keys"
end

return X
