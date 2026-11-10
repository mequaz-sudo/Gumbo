-- ReaKit FX -- MIXER SLOT in its own file (2026-11-05; the user: "the mixer scroll thing ... it just needs somewhere
-- convinet to be" -> on every dock tab's bar, and as actions for keys and toolbars). Not an action: the dock
-- ("ReaKit FX - Dock following the selected track.lua", every one-plugin tab too) loads it once with loadfile, and so
-- do "ReaKit FX - Mixer slot next.lua" / "... previous.lua" / "... top.lua" (no dock needed). It takes one table
-- (r, dbg, sc() = the display scale, live) and sets and returns the global SLOT. The slot shown last is shared through
-- the full dock's ExtState (slot_n), so a key, a toolbar button and every dock step from the same place.
-- EON Free Licence 1.0, EON Studios, 2026.
local D = ...
local r = D.r
local dbg = D.dbg or function() end
local sc = 1                           -- the display scale, taken from D.sc() at each run (the steps along a strip)
local MAIN = r.GetMainHwnd()
local function in_this_reaper(h)       -- (as the dock's own: a window under this REAPER's main window)
  local p = h
  for _ = 1, 32 do
    if p == MAIN then return true end
    local up = r.JS_Window_GetParent(p)
    if not up then break end
    p = up
  end
  return p == MAIN or r.JS_Window_GetRelated(p, "OWNER") == MAIN
end

-- ── SLOT: the same effect row on every mixer strip (the user, 2026-10-07: "can we scroll our mixer by fx slot how
-- users can scroll in reason's daw") ──────────────────────────────────────────────────────────────────────────────
-- REAPER has no call that scrolls a strip's FX list. What it has (measured 2026-10-06..08, slotresearch*_probe.lua;
-- the handoff's "Scroll by FX slot" sections): the list scrolls one effect per WM_MOUSEWHEEL message to the strips'
-- window (REAPERMCPDisplay) while the REAL pointer is over that strip's FX area (the message's own coordinates are
-- ignored), the delta in wParam's HIGH word; GetThingFromPoint over an embedded face answers "mcp.fxembed N" with
-- N = the FX index, so a strip's scroll reads back. SLOT.go(n): for every strip on screen, the pointer is parked at
-- the top-left corner of its FX area (a spot that moves no parameter), <its FX count> "up" messages then n - 1
-- "down" ones are SENT (synchronous: the next strip follows in the same tick), and the pointer goes back where it
-- was. Strips and rows come from REAPER's own hit-tests (GetTrackFromPoint along x, GetThingFromPoint down each
-- strip), never from a theme's numbers; a list of plain (not embedded) rows scrolls the same way but reads back
-- as "?". Strips the mixer has scrolled away are PAGED to (SetMixerScroll, a forced repaint so the page is laid
-- out at once, the view put back at the end): every track the mixer shows gets the row, not only the visible ones.
-- The bar's SLOT button: a click lists the slots (as many as the longest chain in the mixer has), the wheel over
-- it steps. SLOT is a global on purpose (the 200-local limit, see TINT).
-- Tests: slot_req = "<n>" | "step:<d>" | "menu:<pick>"; published slot = the last run's report.
SLOT = { n = 1, max = 2, last = "", pub = nil }
function SLOT.displays()                                          -- the mixer's strip windows (the tracks', the master's)
  if not (r.JS_WindowMessage_Send and r.JS_Mouse_SetPosition and r.GetThingFromPoint and r.JS_Window_ListAllTop) then
    return nil, "needs js_ReaScriptAPI and a newer REAPER"
  end
  if r.GetToggleCommandState(40078) ~= 1 then return nil, "the mixer is not open" end
  -- by CLASS, not by the window's title (a localized REAPER names the mixer otherwise): the strip windows under the
  -- main window (a docked mixer) and under every top-level window the main window owns (a floating one)
  local roots = { MAIN }
  local _, tops = r.JS_Window_ListAllTop()
  for a in (tops or ""):gmatch("[^,]+") do
    local h = r.JS_Window_HandleFromAddress(tonumber(a))
    if h and h ~= MAIN and r.JS_Window_IsVisible(h) and r.JS_Window_GetRelated(h, "OWNER") == MAIN then roots[#roots + 1] = h end
  end
  local out = {}
  for _, root in ipairs(roots) do
    local arr = r.new_array({}, 512)
    local got = r.JS_Window_ArrayAllChild(root, arr)             -- too small: a NEGATIVE count and nothing filled
    if got and got < 0 then arr = r.new_array({}, -got + 16); r.JS_Window_ArrayAllChild(root, arr) end   -- (measured 2026-10-08)
    for _, ad in ipairs(arr.table()) do
      local c = ad ~= 0 and r.JS_Window_HandleFromAddress(ad)
      if c and r.JS_Window_GetClassName(c) == "REAPERMCPDisplay" and r.JS_Window_IsVisible(c) then
        local _, L, T, R, B = r.JS_Window_GetRect(c)
        if R - L > 40 and B - T > 80 then out[#out + 1] = { h = c, L = L, T = T, R = R, B = B } end
      end
    end
  end
  if #out > 0 then return out end
  return nil, "no mixer strips on screen"
end
function SLOT.strips(d)                                           -- one window's strips, left to right: track, edges
  local step = math.max(4, math.floor(6 * sc))                    -- a strip is 50+ px wide; its edges +-6 px are fine
  for _, f in ipairs({ 0.72, 0.5, 0.9 }) do                       -- a row every strip answers on (the fader's); three tries
    local out, prev, ptr, start = {}, nil, nil, 0
    local y = d.T + math.floor((d.B - d.T) * f)
    for x = d.L + 1, d.R - 1, step do
      local tr = r.GetTrackFromPoint(x, y)
      local key = tr and r.GetTrackGUID(tr) or ""
      if key ~= prev then
        if prev and prev ~= "" then out[#out + 1] = { tr = ptr, x0 = start, x1 = x - 1 } end
        prev, ptr, start = key, tr, x
      end
    end
    if prev and prev ~= "" then out[#out + 1] = { tr = ptr, x0 = start, x1 = d.R - 1 } end
    if #out > 0 then return out end
  end
  return {}
end
function SLOT.fxrow(x, y, want_tr)                                -- an FX LIST row at a point (of want_tr when given), or nil
  -- "mcp.fxembed N" (an embedded face) and "mcp.fxlist N fx:M" (a plain row) are the list; "mcp.fx" alone is the
  -- FX BUTTON of a layout with no list (I Logic V2 at this size, 2026-10-08: a wheel burst there scrolled the whole
  -- mixer sideways), "mcp.fxparm" the parameter knobs: neither scrolls a list. The row must belong to the strip being
  -- done: a mixer showing tracks in several rows puts another track's strip in the same column (self-audit 2026-10-08)
  local tr, info = r.GetThingFromPoint(x, y)
  if tr and info and (not want_tr or tr == want_tr) and (info:find("^mcp%.fxembed") or info:find("^mcp%.fxlist")) then return info end
end
function SLOT.fxtop(d, s)                                         -- the top of a strip's FX area: its y and the row's name
  local x = math.floor((s.x0 + s.x1) / 2)
  local step = math.max(4, math.floor(8 * sc))                    -- a plain FX row is 16+ px tall: 8 px cannot skip one; the
                                                                  -- walk-up below finds the first pixel (the scan was the cost)
  for y = d.T + 2, d.B - 2, step do
    local info = SLOT.fxrow(x, y, s.tr)
    if info then
      local y0 = y
      while y0 > d.T + 1 and SLOT.fxrow(x, y0 - 1, s.tr) do y0 = y0 - 1 end   -- up to the area's first pixel
      return y0, info
    end
  end
end
function SLOT.cover(d, s, top)                                    -- a window over the strip right above its FX area's found top
  -- (the user's run, 2026-10-08: four strips whose FX area read 232 px lower, a window over their upper part; the
  -- scroll under it works, but the read-back at the lower spot reads a lower face). nil = nothing over it
  if not (r.JS_Window_FromPoint and top) then return nil end
  local y = top - math.max(2, math.floor(2 * sc))
  if y <= d.T then return nil end
  local wnd = r.JS_Window_FromPoint(math.floor((s.x0 + s.x1) / 2), y)
  if not wnd or wnd == d.h or r.JS_Window_IsChild(d.h, wnd) then return nil end
  return wnd
end
function SLOT.cover_any(d, s)                                     -- a window over ANY part of the strip (its whole FX area may be
  -- under it: no FX row visible at all; Codex delta review 2026-10-08), down its middle, coarse steps; nil = none
  if not r.JS_Window_FromPoint then return nil end
  local cx, step = math.floor((s.x0 + s.x1) / 2), math.max(6, math.floor(10 * sc))
  for y = d.T + 2, d.B - 2, step do
    local wnd = r.JS_Window_FromPoint(cx, y)
    if wnd and wnd ~= d.h and not r.JS_Window_IsChild(d.h, wnd) then return wnd end
  end
  return nil
end
function SLOT.cover_name(wnd)                                     -- for the report: a REAPER window by its title, others by class
  local root = wnd                                                -- up to its top-level window (WS_CHILD off); the extension
  for _ = 1, 32 do                                                -- has no GetRoot
    local st = r.JS_Window_GetLong(root, "STYLE")
    if not st or (math.floor(st) & 0x40000000) == 0 then break end
    local p = r.JS_Window_GetParent(root)
    if not p then break end
    root = p
  end
  local cls = r.JS_Window_GetClassName(root) or "?"
  local mine = root == MAIN or in_this_reaper(root)
  return mine and ("REAPER's '" .. (r.JS_Window_GetTitle(root) or "") .. "'") or ("another program's window (" .. cls .. ")")
end
function SLOT.scroll(d, s, n, top, once)                          -- one strip: to the top, then n - 1 down; the top row read back
                                                                  -- once: one round, nothing judged (a strip under a window)
  local py = top + math.floor(3 * sc)
  local cx = math.floor((s.x0 + s.x1) / 2)                        -- read back mid-strip: the corner misread once in five
  -- the parking spot must BE a list row (a wheel anywhere else is the mixer's own: sideways scroll): the corner,
  -- else mid-strip, else this strip is left alone
  local px = s.x0 + math.floor(4 * sc)
  if not SLOT.fxrow(px, py, s.tr) then px = cx end
  if not SLOT.fxrow(px, py, s.tr) then
    local t = r.GetThingFromPoint(cx, py)                         -- another strip there: the page moved since the scan
    if t and t ~= s.tr then return nil, "another strip at the spot", false, false, false, true end
    return nil, "no list row at the spot", false, true
  end
  local lx, ly = px & 0xFFFF, py & 0xFFFF
  local count = r.TrackFX_GetCount(s.tr)
  local want = math.min(n, count) - 1
  local k, info, atend, valid, moved
  local function read()                                           -- the top row mid-strip: its index (embedded), its name, and
    local tr, inf = r.GetThingFromPoint(cx, py)                   -- whether a LIST row OF THIS STRIP was read at all (a window
    local ok = tr == s.tr and inf and (inf:find("^mcp%.fxembed") or inf:find("^mcp%.fxlist")) and true or false   -- over it: no)
    -- ANOTHER track's strip under the spot now: the page moved while this strip was being done (a real-mouse run,
    -- 2026-10-08: Tom Lo's burst landed on Snare); the caller scans the page again and finds it in its new place
    moved = tr ~= nil and tr ~= s.tr
    return ok and tonumber(inf:match("^mcp%.fxembed (%d+)")) or nil, inf, ok
  end
  -- a mouse in motion pulls the pointer off its spot in the middle of a burst (the sandbox: one strip in ~30 did not
  -- move while 144 strip-scrolls with nobody at the mouse all did): read back, park and send again, three tries
  for _ = 1, 3 do
    r.JS_Mouse_SetPosition(px, py)
    for _ = 1, count do r.JS_WindowMessage_Send(d.h, "WM_MOUSEWHEEL", 0, 120, lx, ly) end
    for _ = 2, n do r.JS_WindowMessage_Send(d.h, "WM_MOUSEWHEEL", 0, -120, lx, ly) end
    k, info, valid = read()
    if once or moved then break end                                -- (moved: the burst went to another strip, which wants the
                                                                   -- same row: harmless; this one is done again by the caller)
    if valid and not k then break end                              -- a plain row on top: nothing to check
    if k == want then break end
    if k and k < want then
      -- short of it. Either the list stops because its end is in view (a tall mixer shows the rest of the chain
      -- below the top row; measured 2026-10-08: a 1040-tall mixer tops out at index 3 of 7), or the burst was
      -- broken: the mouse moved the pointer off the spot, or another window covers the strip there (REAPER's
      -- hit-test then names no track). The pointer still on the spot and REAPER naming this track there = the
      -- end, as far as that list goes; anything else = another round
      local qx, qy = r.GetMousePosition()
      if qx == px and qy == py and r.GetThingFromPoint(px, py) == s.tr then atend = true; break end
    end
  end
  return k, info, atend, false, valid, moved
end
function SLOT.shown()                                             -- the tracks the mixer shows, in order (the master apart)
  local t = {}
  for i = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, i)
    if r.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER") == 1 then t[#t + 1] = tr end
  end
  return t
end
function SLOT.longest()                                           -- the longest chain among the mixer's tracks (+ the master)
  local m = r.TrackFX_GetCount(r.GetMasterTrack(0))
  for _, tr in ipairs(SLOT.shown()) do m = math.max(m, r.TrackFX_GetCount(tr)) end
  return m
end
function SLOT.run(disps, n)
  local t_start, t_scan, t_wheel, t_paint = r.time_precise(), 0, 0, 0
  local done, missed, norow, tops, strips, pages = 0, 0, 0, {}, 0, 1   -- done: as asked (or as far as the list goes);
  local seen, lines, bad = {}, {}, {}                             -- missed: a list that did not land or could not be
  local covered, hidden, deferred = 0, {}, {}                     -- covered: scrolled under a window, not checked
  local covered_g, edge_covered = {}, false                       -- edge_covered: a page's first strip was still under a
                                                                  -- window at the left edge: paging cannot help, no more waiting
  local left0 = r.GetMixerScroll()                                -- the view to put back; nil = the mixer cannot page
  local master = r.GetMasterTrack(0)
  local function page(final, only, last)                          -- read back; norow: a strip with FX but no list row.
                                                                  -- only: this track alone (the page's own first strip);
                                                                  -- last: the page's last scan (a strip whose page moves
                                                                  -- under it is then judged where it stands)
    local did, blank, relayout = 0, 0, false                      -- Every strip on screen not done yet. A strip with FX
    for _, d in ipairs(disps) do                                  -- but no rows yet (never painted) is left for a second
      local t0 = r.time_precise()                                 -- pass after the page's paint (blank counts them);
      local list = SLOT.strips(d)                                 -- final: counted as "no rows" instead
      t_scan = t_scan + r.time_precise() - t0
      for _, s in ipairs(list) do
        local g = r.GetTrackGUID(s.tr)
        if not seen[g] and (not only or g == only) then
          local count = r.TrackFX_GetCount(s.tr)
          t0 = r.time_precise()
          local top, row
          if count > 0 then top, row = SLOT.fxtop(d, s) end
          t_scan = t_scan + r.time_precise() - t0
          local cover = (count > 0 and top) and SLOT.cover(d, s, top) or nil
          if count > 0 and not top and final then cover = SLOT.cover_any(d, s) end   -- no row even after the paint: a window
          -- over the whole FX area? Or a strip cut off by the window's edge (only a sliver shows, no row in it: the big-
          -- project test, 2026-10-08, lost the cut-off strip of every page as "no rows")
          local cut = count > 0 and not top and final and (s.x0 <= d.L + 2 or s.x1 >= d.R - 2)
          if count > 0 and not top and not final then
            blank = blank + 1
          elseif cut and not cover and left0 and s.tr ~= master and g ~= only then
            deferred[g] = true                                    -- its own page shows it whole at the left edge
          elseif cover and left0 and s.tr ~= master and g ~= only and not edge_covered then
            -- a window over its upper part: left for its own page, which brings it to the left edge, out from under
            -- it (the paging below takes the first track not done, and does that one with `only` even if it is still
            -- covered there); the master never moves: done as it stands; no paging: done as it stands
            deferred[g] = true
          elseif count == 0 then
            seen[g] = true; did = did + 1; strips = strips + 1      -- no FX: nothing to scroll
          else
            local _, nm = r.GetSetMediaTrackInfo_String(s.tr, "P_NAME", "", false)
            if nm == "" then nm = s.tr == master and "MASTER" or "(unnamed)" end
            local mark, info, atend, kind = "-", nil, false, nil
            if not top and cover then kind = "w"                  -- its FX area under a window, nothing to park on: not moved
            elseif not top then kind = "norow"
            else
              if SLOT.test_move and nm == SLOT.test_move then     -- tests only (slot_req "move:"): the page shifted by one
                SLOT.test_move = nil                              -- strip right before this strip's burst, as a moving page
                local lt = r.GetMixerScroll()                     -- would (slotmove_probe.lua): one strip back, else on
                local ix = lt and math.floor(r.GetMediaTrackInfo_Value(lt, "IP_TRACKNUMBER"))
                local to = ix and (ix >= 2 and r.GetTrack(0, ix - 2) or r.GetTrack(0, ix))
                if to then r.SetMixerScroll(to) end
              end
              t0 = r.time_precise()
              local k, inf, ae, nospot, valid, mv = SLOT.scroll(d, s, n, top, cover ~= nil)
              t_wheel = t_wheel + r.time_precise() - t0
              info, atend = inf, ae
              if mv and not last then kind = "moved"              -- another strip under the spot now: scanned again below
              elseif nospot then kind = "norow"
              elseif cover then kind = "c"                         -- scrolled, its top out of sight
              elseif not valid then kind = "x"                     -- no list row of its own readable after the burst
              elseif k and k ~= math.min(n, count) - 1 and not atend then kind = "k"; mark = tostring(k)
              else kind = "done"; mark = (k and tostring(k) or "?") .. (atend and "e" or "") end   -- "3e": as far as that list goes
            end
            if kind == "moved" then
              relayout = true
              dbg("   slot: " .. nm .. ": the page moved under it; scanned again")
            else
              seen[g] = true; did = did + 1; strips = strips + 1
              if kind == "w" then missed = missed + 1; bad[#bad + 1] = nm; mark = "w"; covered_g[g] = true
              elseif kind == "norow" then norow = norow + 1; bad[#bad + 1] = nm
              elseif kind == "c" then covered = covered + 1; hidden[#hidden + 1] = nm; mark = "c"; covered_g[g] = true
              elseif kind == "x" then missed = missed + 1; bad[#bad + 1] = nm; mark = "x"
              elseif kind == "k" then missed = missed + 1; bad[#bad + 1] = nm
              else done = done + 1 end
              tops[#tops + 1] = mark
              lines[#lines + 1] = string.format("%s: x %d..%d, %d fx, area top y %s (%s) -> %s%s = %s%s", nm, s.x0, s.x1, count,
                                                tostring(top), tostring(row), tostring(info), atend and " (the end)" or "", mark,
                                                cover and ("; under " .. SLOT.cover_name(cover)) or "")
              dbg("   slot: " .. lines[#lines])
            end
          end
        end
      end
    end
    return did, blank, relayout
  end
  local dc                                                        -- the off-screen bitmap's DC (below), nil = none
  local function paint()                                          -- the page laid out into the bitmap, the screen untouched
    local t0 = r.time_precise()
    for _, d in ipairs(disps) do
      if dc then r.JS_WindowMessage_Send(d.h, "WM_PAINT", dc, 0, 0, 0)
      elseif r.JS_Window_InvalidateRect and r.JS_Window_Update then
        r.JS_Window_InvalidateRect(d.h, 0, 0, d.R - d.L, d.B - d.T, true); r.JS_Window_Update(d.h)
      end
    end
    t_paint = t_paint + r.time_precise() - t0
  end
  -- a strip the mixer never painted has no FX rows yet, and REAPER lays a page out only while painting it
  -- (slotpage_probe.lua: "[mcp]" right after SetMixerScroll). A forced repaint on screen lays it out but shows
  -- every page (the user, 2026-10-08: "it kinda jitters"), so a page that needs it is painted into a bitmap of our
  -- own instead: WM_PAINT sent with that bitmap's DC (slotpage2_probe.lua: the rows appear, the screen's pixels do
  -- not change). Without the LICE calls, the on-screen repaint stays as the fallback. Only a page with strips that
  -- have FX but no rows gets the paint (the user: every wheel notch stalled REAPER for ~100 ms).
  if r.JS_LICE_CreateBitmap and r.JS_LICE_GetDC and r.JS_Window_AddressFromHandle then
    local w, h = 1, 1
    for _, d in ipairs(disps) do w, h = math.max(w, d.R - d.L), math.max(h, d.B - d.T) end
    SLOT.bmp = r.JS_LICE_CreateBitmap(true, w, h)                  -- freed by SLOT.go, whatever happens below
    local hdc = SLOT.bmp and r.JS_LICE_GetDC(SLOT.bmp)
    dc = hdc and r.JS_Window_AddressFromHandle(hdc)
  end
  local function do_page()                                        -- the page now in the mixer: every strip not done yet,
    for attempt = 1, 4 do                                         -- painted off screen when it holds never-painted strips,
      local last = attempt == 4 or SLOT.test_norescan             -- and scanned again while it moves under the run (a
      local _, blank, mv = page(false, nil, last)                 -- self-audit run, 2026-10-08: the page moved by one
      if blank > 0 then                                           -- strip mid-run); the fourth scan judges strips where
        paint()                                                   -- they stand
        local _, _, mv2 = page(true, nil, last)
        mv = mv or mv2
      end
      if not mv then return end
    end
  end
  do_page()                                                       -- the page on screen first
  -- then the mixer turned page by page for the tracks it shows but has scrolled away (the user, 2026-10-08:
  -- "paging"): the first such track made the leftmost strip (SetMixerScroll), its page done, until none is left;
  -- the view put back (SLOT.go). Tracks the mixer hides stay out: nothing can show them. A strip left for later
  -- (a window over it) is such a track too: its page brings it to the left edge.
  if left0 then
    local shown = SLOT.shown()
    -- every turn below ends with its first track done (or named as never on screen), so the shown tracks bound it;
    -- a fixed cap of 64 left the rest of a big project quietly undone (Codex delta review 2026-10-08)
    for _ = 1, #shown + 1 do
      local nxt
      for _, tr in ipairs(shown) do if not seen[r.GetTrackGUID(tr)] then nxt = tr; break end end
      if not nxt then break end
      r.SetMixerScroll(nxt)
      pages = pages + 1
      local gn = r.GetTrackGUID(nxt)
      do_page()
      if not seen[gn] then page(true, gn, true) end               -- the page's first strip: at the left edge now; done as it
      if covered_g[gn] then edge_covered = true; page(true, nil, true) end   -- (still covered there: the rest as they stand)
      if not seen[gn] then                                        -- stands, under a window or not. Still not done: it never
        seen[gn] = true                                           -- came on screen (counted, named: never skipped quietly; the
        if r.TrackFX_GetCount(nxt) > 0 then                       -- self-test 2026-10-08 found one skipped); a track with no FX
          missed = missed + 1                                     -- has nothing to scroll: no word about it
          local _, nm = r.GetSetMediaTrackInfo_String(nxt, "P_NAME", "", false)
          bad[#bad + 1] = nm ~= "" and nm or "(unnamed)"; tops[#tops + 1] = "n"
          lines[#lines + 1] = (nm ~= "" and nm or "(unnamed)") .. ": never came on screen = n"
        end
      end
    end
    for _, tr in ipairs(shown) do                                 -- (none can be left; if one is, it is counted, not lost)
      local g = r.GetTrackGUID(tr)
      if not seen[g] then
        seen[g] = true
        if r.TrackFX_GetCount(tr) > 0 then
          missed = missed + 1
          local _, nm = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
          bad[#bad + 1] = nm ~= "" and nm or "(unnamed)"; tops[#tops + 1] = "n"
          lines[#lines + 1] = (nm ~= "" and nm or "(unnamed)") .. ": not reached = n"
        end
      end
    end
    if r.GetMixerScroll() ~= left0 then r.SetMixerScroll(left0) end
  end
  SLOT.n, SLOT.max = n, math.max(2, math.min(SLOT.longest(), 32))
  local ms = function(t) return math.floor(t * 1000 + 0.5) end
  SLOT.last = string.format("slot %d: %d strips on %d pages, %d scrolled, %d missed, %d no rows, %d behind a window, %d ms (scan %d, wheel %d, paint %d); tops %s",
                            n, strips, pages, done, missed, norow, covered, ms(r.time_precise() - t_start), ms(t_scan), ms(t_wheel), ms(t_paint), table.concat(tops, ","))
  dbg(SLOT.last)
  -- the word on the bar (draw_bar): quiet when every strip did as asked (Codex delta review 2026-10-08: the causes
  -- told apart, and a run that went well clears an older word: SLOT.go); the strips concerned are named
  local tried = done + missed + norow + covered
  local function names(t) return #t > 0 and (": " .. table.concat(t, ", ", 1, math.min(#t, 4)) .. (#t > 4 and " ..." or "")) or "" end
  if strips == 0 then SLOT.say("SLOT: no strips found in the mixer")
  elseif tried > 0 and done + covered == 0 and missed == 0 then SLOT.say("SLOT: nothing scrolled: the strips show no effect rows")
  elseif tried > 0 and done + covered == 0 then SLOT.say("SLOT: nothing scrolled: the lists did not move")
  elseif missed + norow > 0 then SLOT.say(string.format("SLOT: %d of %d strips did not move%s", missed + norow, tried, names(bad)))
  elseif covered > 0 and covered == tried then SLOT.say("SLOT: a window covers the mixer's effect rows: scrolled, not checked")
  elseif covered > 0 then SLOT.say(string.format("SLOT: %d behind a window, scrolled but not checked%s", covered, names(hidden))) end
  -- the run's report, a small file beside REAPER's data (<resource>/Data/ReaKit_FX_slot_report.txt): what every
  -- strip did, for a look when a strip is reported; a temp file first, then renamed (the house rule)
  SLOT.report(lines)
  return missed + norow == 0
end
function SLOT.report(lines)
  local p = r.GetResourcePath() .. "/Data/ReaKit_FX_slot_report.txt"
  local fh = io.open(p .. ".tmp", "w")
  if not fh then return end
  fh:write(os.date("%Y-%m-%d %H:%M:%S"), "  ", SLOT.last, "\n", table.concat(lines, "\n"), "\n")
  fh:close()
  os.remove(p); os.rename(p .. ".tmp", p)
end
function SLOT.say(msg) SLOT.msg, SLOT.msg_t = msg, r.time_precise(); dbg(msg) end
function SLOT.go(n)
  n = math.max(1, math.floor(tonumber(n) or 1))
  local disps, why = SLOT.displays()
  if not disps then SLOT.last = "slot " .. n .. ": " .. why; SLOT.say("SLOT: " .. why); return false end
  local mx, my = r.GetMousePosition()
  SLOT.msg = nil                                                  -- an older word goes; this run speaks for itself
  local left = r.GetMixerScroll()                                 -- the mixer's leftmost strip: a wheel that misses a list
  local ok, res = pcall(SLOT.run, disps, n)                       -- scrolls the mixer sideways; put back if so
  if SLOT.bmp then pcall(r.JS_LICE_DestroyBitmap, SLOT.bmp); SLOT.bmp = nil end   -- the paging's off-screen bitmap
  r.JS_Mouse_SetPosition(mx, my)                                  -- the pointer back where it was, whatever happened
  if left and r.GetMixerScroll() ~= left then r.SetMixerScroll(left); dbg("slot: the mixer had scrolled sideways; put back") end
  SLOT.test_move, SLOT.test_norescan = nil, nil                   -- the test switches last one run
  if not ok then SLOT.last = "slot " .. n .. ": error " .. tostring(res); SLOT.say("SLOT: something went wrong; see the trace"); dbg(SLOT.last); return false end
  return res
end
function SLOT.step(d) SLOT.pending = (SLOT.pending or 0) + d end   -- the wheel's notches add up; ONE run per tick (SLOT.tick)
function SLOT.tick()                                              -- from the loop: a flick of three notches = one run, not three
  local d = SLOT.pending or 0
  if d == 0 then return end
  SLOT.pending = 0
  SLOT.max = math.max(2, math.min(SLOT.longest(), 32))            -- fresh: before any run it was 2, so a first flick stopped
  SLOT.go(math.max(1, math.min(SLOT.max, SLOT.n + d)))            -- at slot 2 (self-audit 2026-10-08)
end
function SLOT.menu(mx, my, forced)                                -- forced: the pick's number (tests), no menu shown
  local disps, why = SLOT.displays()
  SLOT.max = math.max(2, math.min(SLOT.longest(), 32))            -- as many slots as the longest chain in the mixer has
  local m = {}
  if not disps then m[1] = "#" .. why:sub(1, 1):upper() .. why:sub(2)
  else for i = 1, SLOT.max do m[i] = (i == SLOT.n and "!" or "") .. (i == 1 and "Top of every strip" or "Slot " .. i) end end
  gfx.x, gfx.y = mx, my
  local pick = forced or gfx.showmenu(table.concat(m, "|"))
  if disps and pick and pick >= 1 then SLOT.go(pick) end
end
-- the shared slot: read before a step, written after a run (a key, a toolbar and every dock agree)
local SX = "EON_ReaKitDock"
local go0, tick0, menu0 = SLOT.go, SLOT.tick, SLOT.menu
function SLOT.go(n)
  sc = D.sc and D.sc() or 1
  local res = go0(n)
  r.SetExtState(SX, "slot_n", tostring(SLOT.n), false)
  return res
end
function SLOT.tick()
  if (SLOT.pending or 0) ~= 0 then SLOT.n = tonumber(r.GetExtState(SX, "slot_n")) or SLOT.n end
  return tick0()
end
function SLOT.menu(mx, my, forced)
  sc = D.sc and D.sc() or 1
  SLOT.n = tonumber(r.GetExtState(SX, "slot_n")) or SLOT.n
  return menu0(mx, my, forced)
end
SLOT.n = tonumber(r.GetExtState(SX, "slot_n")) or 1
return SLOT
