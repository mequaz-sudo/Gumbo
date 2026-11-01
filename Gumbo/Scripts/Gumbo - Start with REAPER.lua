-- Copyright (c) 2026 EON Studios (Quaz). All rights reserved. Free to use: see Gumbo_LICENSE.md.
-- Gumbo - Start with REAPER: run once and the Gumbo helper goes into Scripts/__startup.lua (the file REAPER runs at
-- start-up) and starts now; run again and it comes out. The toolbar button shows the state. Nothing else in
-- __startup.lua is touched: the block sits between two marker lines and is added or removed whole; a file that held
-- only the block is deleted. At start-up the block registers "Gumbo helper.lua" as an action (a no-op when it already
-- is one) and runs it by its command id, so it runs on the real action path: its toggle lights and running the action
-- stops it as usual. GainKit Plus's start action, the same writer (.dev_tests/startup_gkplus_test.py runs its checks
-- on both). EON Studios, 2026.
local r = reaper
local _, own, sec, cmd = r.get_action_context()
local sep = own:find("\\", 1, true) and "\\" or "/"
local dir = own:match("^(.*)[\\/]") or "."
local HELPER = dir .. sep .. "Gumbo helper.lua"
local STARTUP = r.GetResourcePath() .. sep .. "Scripts" .. sep .. "__startup.lua"
local OPEN  = "-- >>> Gumbo helper: start with REAPER (the action \"Gumbo - Start with REAPER\" adds and removes this block) >>>"
local CLOSE = "-- <<< Gumbo helper <<<"
local EXT = "EON_GumboHelper"                        -- the helper's own heartbeat keys (alive / stop), and quiet
local write_kept                                     -- where the original sits when a swap could not put it back

local function read(p) local fh = io.open(p, "rb"); if not fh then return nil end; local s = fh:read("*a"); fh:close(); return s end
-- Is there something at p? os.rename onto itself succeeds only for an existing path (a file or a folder), readable or
-- not, without touching it.
local function exists(p) return os.rename(p, p) and true or false end
-- A name beside p that nothing else uses: the process's own, and only taken when it is free, so a user's own
-- __startup.lua.tmp or .bak is never overwritten or removed.
local function spare(p, tag)
  for i = 0, 99 do
    local n = string.format("%s.gumbo-%s-%d-%d", p, tag, math.floor(os.time()), i)
    if not exists(n) then return n end
  end
end
-- The whole new text goes to a temporary file first, checked; only then does it take the original's place, so a full
-- disk or a crash mid-write cannot leave __startup.lua blank. os.rename cannot replace a file on Windows, so the
-- original steps aside for the instant of the swap and comes back if the swap fails.
local function write(p, s)
  local tmp, bak = spare(p, "tmp"), spare(p, "bak")
  if not tmp or not bak then return false end
  local fh = io.open(tmp, "wb")
  if not fh then return false end
  local okw = fh:write(s)
  local okc = fh:close()
  if not okw or not okc or read(tmp) ~= s then os.remove(tmp); return false end
  local had = exists(p)
  if had and not os.rename(p, bak) then os.remove(tmp); return false end
  if os.rename(tmp, p) then if had then os.remove(bak) end; return true end
  if had and not os.rename(bak, p) then write_kept = bak end   -- the original is intact under this name
  os.remove(tmp)
  return false
end

local function block()
  return table.concat({
    OPEN,
    "do",
    -- %q: a path holding ]] would end a long-bracket string early
    string.format("  local helper, me = %q, %q", HELPER, own),
    "  local fh = io.open(helper, \"r\")                    -- uninstalled since? then this block does nothing",
    "  if fh then",
    "    fh:close()",
    "    local ok, c = pcall(reaper.AddRemoveReaScript, true, 0, helper, true)",
    "    if ok and c and c > 0 then reaper.Main_OnCommand(c, 0) end",
    "    local ok2, c2 = pcall(reaper.AddRemoveReaScript, true, 0, me, true)",
    "    if ok2 and c2 and c2 > 0 then reaper.SetToggleCommandState(0, c2, 1); reaper.RefreshToolbar2(0, c2) end",
    "  end",
    "end",
    CLOSE,
    "" }, "\n")
end

-- The helper running now? -- so "start now" never stops it. Its toggle state goes on at its start and off in its
-- atexit; when REAPER has no state for the action yet (-1), its heartbeat decides, read the way the helper reads it:
-- fresh, and newer than the last stop request.
local function helper_running(c)
  local ts = r.GetToggleCommandState(c)
  if ts == 1 then return true end
  if ts == 0 then return false end
  local hb = tonumber(r.GetExtState(EXT, "alive")) or 0
  local st = tonumber(r.GetExtState(EXT, "stop")) or 0
  return hb > st and r.time_precise() - hb < 1.0
end

local quiet = r.GetExtState(EXT, "quiet") == "1"     -- a probe gets no dialog (a modal box blocks the caller)
local s = read(STARTUP)
if not s and exists(STARTUP) then
  -- the file is there but could not be read (permissions, a lock): treating it as empty would write a file holding
  -- only this block over it. Nothing is touched.
  if not quiet then r.MB("Scripts/__startup.lua could not be read, so it was left alone.", "Gumbo", 0) end
  return
end
-- a start-up file the user made read-only is theirs to keep that way: left alone, not swapped for a writable copy
-- (Floatter's writer does the same; opening it for appending writes nothing)
if s then
  local fa = io.open(STARTUP, "ab")
  if not fa then
    if not quiet then r.MB("Scripts/__startup.lua is read-only, so it was left alone.", "Gumbo", 0) end
    return
  end
  fa:close()
end
s = s or ""
local a = s:find(OPEN, 1, true)
local on, ok
if a and not s:find(CLOSE, a, true) then
  -- the opening marker without its closing one: someone edited the block. Removing "to the end of the file" could take
  -- their lines with it, so nothing is touched.
  if not quiet then
    r.MB("The Gumbo helper block in Scripts/__startup.lua has lost its closing line, so it was left alone. Remove the block by hand, then run this action again.", "Gumbo", 0)
  end
  return
end
if a then
  local b = s:find(CLOSE, a, true)
  local e = s:find("\n", b, true) or #s                         -- through the end of the CLOSE line
  local out = s:sub(1, a - 1) .. s:sub(e + 1)
  if out:match("^%s*$") then ok = os.remove(STARTUP) and true or false else ok = write(STARTUP, out) end
  on = false
else
  local out = s
  if #out > 0 and out:sub(-1) ~= "\n" then out = out .. "\n" end
  ok = write(STARTUP, out .. block())
  on = true
  if ok then
    local okc, c = pcall(r.AddRemoveReaScript, true, 0, HELPER, true)
    if okc and c and c > 0 and not helper_running(c) then r.Main_OnCommand(c, 0) end
  end
end

-- the button shows the state that actually landed: an I/O failure leaves it as it was
if ok and sec and cmd and cmd > 0 then r.SetToggleCommandState(sec, cmd, on and 1 or 0); r.RefreshToolbar2(sec, cmd) end
if quiet then return end
if not ok then
  r.MB("Could not write " .. STARTUP .. (write_kept and (string.char(10, 10) .. "Your original is intact as " .. write_kept .. " -- rename it back by hand.") or ""), "Gumbo", 0)
elseif on then
  r.MB("The Gumbo helper starts with REAPER from now on (and is running now), so .sfz files open in Gumbo. Run this action again to take it out of Scripts/__startup.lua.", "Gumbo", 0)
else
  r.MB("The Gumbo helper no longer starts with REAPER. The copy running now keeps running until you stop it.", "Gumbo", 0)
end
