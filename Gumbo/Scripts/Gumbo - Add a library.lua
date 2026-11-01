-- Copyright (c) 2026 EON Studios (Quaz). All rights reserved. Free to use: see Gumbo_LICENSE.md.
-- Gumbo - Add a library: pick any .sfz inside an SFZ library. Every instrument in that file's folder and the folders
-- below it is converted into Gumbo's import folder (REAPER's Data/EON_Gumbo/Imported; the samples stay where they
-- are) and added to Gumbo's browser, which open Gumbos pick up by themselves. A file another one pulls in with
-- #include is a piece, not an instrument (gumbo_sfz.lua's rule). One instrument per pass, so REAPER stays usable
-- while a big library converts; the console says what happened. Works with or without the Gumbo helper running.
-- EON Studios, 2026.
local r = reaper
local _, own = r.get_action_context()
local dir = own:match("^(.*)[\\/]") or "."
local G = dofile(dir .. "/gumbo_sfz.lua")
local X = dofile(dir .. "/gumbo_index.lua")
local C = dofile(dir .. "/gumbo_helper_core.lua")

local ok, pick = r.GetUserFileNameForRead("", "Gumbo: pick any .sfz inside the library to add", "sfz")
if not ok or not pick or pick == "" then return end
pick = pick:gsub("\\", "/")
local lib = pick:match("^(.*)/[^/]+$") or "."

r.gmem_attach("Swing_Media_Transfer")
local res = r.GetResourcePath():gsub("\\", "/")
local LIST = res .. "/Data/EON_Gumbo/library.txt"
local IMPORTS = res .. "/Data/EON_Gumbo/Imported"

local function each_file(root, fn)
  local function walk(d)
    r.EnumerateFiles(d, -1)
    local i = 0
    while true do
      local f = r.EnumerateFiles(d, i)
      if not f then break end
      fn(d .. "/" .. f)
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
end

-- the library's .sfz / .inc / .sfzh files, read for their #include lines; the converter decides which are instruments
local files = {}
each_file(lib, function(p)
  local low = p:lower()
  if low:match("%.sfz$") or low:match("%.inc$") or low:match("%.sfzh$") then
    local f = io.open(p, "rb")
    local text = f and f:read("a") or ""
    if f then f:close() end
    files[#files + 1] = { path = p, text = text }
  end
end)
local todo = G.instrument_files(files, lib)
if #todo == 0 then
  r.MB("No SFZ instrument was found in\n" .. lib, "Gumbo - Add a library", 0)
  return
end
-- say what it found before converting anything: a .sfz picked loose in a big folder (Downloads) would take it all
if r.MB(("Add %d instrument(s) from\n%s\n\nto Gumbo's browser?"):format(#todo, lib), "Gumbo - Add a library", 4) ~= 6 then
  return
end
local ENV = {
  mkdir = function(d) r.RecursiveCreateDirectory(d, 0) end,
  find_imports = function(root)
    local out = {}
    each_file(root, function(p) if p:lower():sub(-10) == ".gumbo.txt" and not p:match("/%.[^/]*$") then out[#out + 1] = p end end)
    return out
  end,
}

r.ShowConsoleMsg(("Gumbo: adding %d instrument(s) from %s\n"):format(#todo, lib))
local i, added, failed = 0, 0, {}
local function step()
  i = i + 1
  if i <= #todo then
    -- a converter error is one failed instrument, not a stop; a failed one leaves no folder behind
    local okc, ok, _, _, _, why = pcall(C.convert_into, G, ENV, todo[i], IMPORTS)
    if okc and ok then added = added + 1
    else failed[#failed + 1] = todo[i]:match("([^/]+)$") .. " (" .. C.why_text(okc and why or C.WHY_NOTHING) .. ")" end
    r.defer(step)
    return
  end
  -- all converted: the browser list once, then the open Gumbos reload it
  local st = C.relist(X, ENV, IMPORTS, LIST)
  if st == C.ST_DONE then r.gmem_write(C.BAND + C.LIBGEN, r.gmem_read(C.BAND + C.LIBGEN) + 1) end
  local msg = ("Gumbo: %d of %d instrument(s) added to the browser."):format(added, #todo)
  if #failed > 0 then msg = msg .. " Could not convert: " .. table.concat(failed, ", ") .. "." end
  if st ~= C.ST_DONE then msg = msg .. " The browser list could not be written (" .. LIST .. ")." end
  r.ShowConsoleMsg(msg .. "\n")
end
step()
