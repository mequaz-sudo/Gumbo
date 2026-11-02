-- Copyright (c) 2026 EON Studios (Quaz). All rights reserved. Free to use: see Gumbo_LICENSE.md.
-- Gumbo - Dock: the selected track's Gumbo, whole, in its own docker tab, following the selection (the owner,
-- 2026-11-01: "i want gumbo to dock all its own"). Run it again to close the tab. The dock itself is the ReaKit FX
-- dock ("ReaKit FX - Dock following the selected track.lua"): Gumbo's release copies it (and its icon picker) beside
-- this file; in the development tree it is found in ../GainKit Plus. This only names the plugin. Windows only; needs
-- js_ReaScriptAPI (ReaPack).
REAKIT_DOCK_ONLY = { key = "gmb", title = "Gumbo", close_on_pop = true }   -- a double-click that floats it closes the tab
local dir = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local dock = "ReaKit FX - Dock following the selected track.lua"
local f = io.open(dir .. dock, "r")
if f then f:close() else dir = dir .. "../GainKit Plus/" end
dofile(dir .. dock)
