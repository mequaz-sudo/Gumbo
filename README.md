# Gumbo

An SFZ instrument player for REAPER, in one free JSFX, by EON Studios. Pick an instrument in its browser and play,
or drop an SFZ library or a SoundFont (.sf2, a compressed .sf3, 16 or 24-bit) on its window: Gumbo plays it with velocity
layers, round robins, key switches, release samples, loops, the sustain pedal, each instrument's own envelopes
(the filter's and the pitch's too), its EQ bands, its bend range and its own controls, at full quality, every
recording as it was made.

- **The browser**: family tiles, a GM set filed under them, search by name, and stars for your favourites.
- **The sound**: DRIVE (before or after the EQ), ATTACK, RELEASE, GLIDE, WIDTH, PAN and VOLUME; a four-band EQ (each
  band a bell, shelf or cut, with Q knobs) and a dark-to-bright TONE tilt, remembered per instrument and per program
  of a GM set, with a HOLD switch; the library's own controls, attack and release knobs included; pitch and mod
  wheels; key pressure for vibrato.
- **SPACE and CHORUS**: a reverb with General MIDI 2's six types (three rooms, two halls and a plate), its picture
  glowing with the live tail, and a chorus with a Juno-style I, I + II and II, a feedback chorus and a flanger. Each
  sound brings its own amounts, the song's reverb and chorus controllers add to them, and the knobs are remembered per
  sound, like the EQ.
- **Drums**: a kit's keys carry the names of their sounds, and a PADS page plays the kit as 16 pads a bank, each
  pad with an icon and its family's colour (or one you pick); the MIDI editor's lanes take the names too.
- **In the mixer**: Gumbo opens embedded in the mixer, where the keys and wheels play right in the track's strip;
  the keyboard and the display fold away when you want the room.
- **Your tracks**: with the Gumbo helper running, each track takes its instrument's name, colour and icon (only where
  you have not set your own).
- **Your own SFZ libraries**: run the **Gumbo helper** action and drop an .sfz on Gumbo's window (what it reads from
  one is [listed below](#what-gumbo-plays-from-an-sfz)). **Gumbo - Add a
  library** brings a whole library folder into the browser at once; **Gumbo - Start with REAPER** keeps the helper
  running from launch. One instrument can use up to about 3 GB of sound (the browser shows each one's size); one
  over about 1 GB is kept at 16-bit so it fits, and a bigger one loads only the part that fits.

## The packages

- **Gumbo**: the player and its scripts.
- **Gumbo GM sounds** (about 80 MB): **Gumbo GM**, a whole General MIDI set in one instrument, all 128 programs,
  the drum kits and every variation bank (289 programs in all). Pick a program in Gumbo's program box or its
  browser, or send program changes and bank select; channel 10 plays the kits.

The **VSCO 2 Community Edition** orchestra (75 instruments at full quality, about 760 MB) is a separate free download
with its own address: [Gumbo-Sounds](https://github.com/mequaz-sudo/Gumbo-Sounds).

## Install (ReaPack)

1. **Extensions > ReaPack > Import repositories**, paste this address and click OK:

   ```
   https://raw.githubusercontent.com/mequaz-sudo/Gumbo/main/index.xml
   ```

2. **Extensions > ReaPack > Browse packages**, type **Gumbo**, install **Gumbo** and **Gumbo GM sounds**, then click
   **Apply**.
3. Add a track, click its **FX** button and add `JS: EON: Gumbo`, then pick an instrument in its browser.

## What Gumbo plays from an SFZ

Gumbo reads SFZ 1 and the parts of SFZ 2 and ARIA that sample libraries use most, from WAV, FLAC and Ogg sounds, up to
64 voices at once. A line it does not use is skipped and the instrument still loads.

It plays:

- **Mapping**: key and velocity ranges, round robins and random picks (`seq_length`, `seq_position`, `lorand`,
  `hirand`), key switches (`sw_last`, `sw_lokey`, `sw_hikey`, `sw_default`, with their `sw_label` names), the
  `attack`, `release`, `release_key`, `first` and `legato` triggers, choke groups (`group`, `off_by`, `off_mode`,
  `off_time`), `polyphony` and `note_polyphony`, controller ranges (`loccN`, `hiccN`), and crossfades on a controller,
  on velocity or on the key, with their curves. `#define`, `#include`, `default_path` and `<curve>` headers are read.
- **Sound**: tuning and transpose, volume, pan, the amplitude envelope (its times scaled by velocity or by the key
  where the library asks), velocity curves (`amp_veltrack`, `amp_velcurve_N`, `amp_velpow`), `amp_random`, loops
  (from the SFZ or from the loop points stored in the sound file), `offset`, `offset_random` and `end`, and release
  samples with `rt_decay`.
- **Tone and movement**: one filter per region, a low-pass or high-pass of 1, 2 or 4 poles or a 2-pole band-pass or
  notch, with resonance, key and velocity tracking; the filter envelope and the pitch envelope; one LFO each on
  pitch, volume and the filter (the SFZ 1 `pitchlfo`, `amplfo`, `fillfo` or an SFZ 2 `lfoN`, sine or triangle); the
  three region EQ bands; the reverb and chorus amounts (`effect1`, `effect2`); the bend range (`bend_up`,
  `bend_down`).
- **Controllers**: volume (7), expression (11), the sustain pedal (64), reverb and chorus (91, 93), pitch bend, the
  mod wheel and channel pressure. A library's own controls play live when they move amplitude, volume, pan, tuning,
  the filter's cutoff (one controller a region) or the amplitude envelope's times, up to eight a region, and show
  on the CONTROLS page as knobs under their `label_ccN` names.

It leaves out:

- generated sounds (`sample=*sine` and the other oscillators): those regions are skipped;
- the `<effect>`, `<midi>` and `<sample>` headers;
- a second filter (`cutoff2`, `fil2_type`) and filter types other than the eight above (a 6-pole filter plays as
  the nearest one; with a peak, shelf, comb or all-pass filter the region plays unfiltered);
- flex envelopes (`egN_...`), a second LFO on the same target, and LFO shapes other than sine and triangle (they
  play as a sine);
- controller assignments other than those above: each stays at the value the library sets for the controller's start;
- the `sw_previous`, `sw_down` and `sw_up` key switches, `amp_keytrack`, `pitch_random`, `pitch_veltrack`, `width`
  and `position`, `direction=reverse`, `loop_crossfade`, `bend_step` and `bend_smooth`, and EQ bands that follow
  velocity or a controller;
- the sostenuto and soft pedals and polyphonic key pressure.

A SoundFont is turned into an SFZ first and then read the same way: its filter, both envelopes, both LFOs and its
velocity and key rules come across, and a controller rule plays live when it moves the volume or the filter's
cutoff; any other stays at the controller's starting value.

## Licence and credits

Gumbo is free to use; its code stays EON Studios' ([Gumbo_LICENSE.md](Gumbo/Gumbo_LICENSE.md)). [LICENSE](LICENSE)
says which licence covers which files: Gumbo's own, the parts shared with ReaKit FX under the
[EON Free Licence](LICENSE-EON-FREE.md), and the MIT ReaKit library. Gumbo GM is made from **MuseScore General** by
**S. Christian Collins**, built on FluidR3 by **Frank Wen** and FluidR3Mono by **Michael Cowgill**, under the **MIT**
licence; its notices are in `MuseScore_General_License.md` beside the sounds. EON Studios converted it for Gumbo, every WAV
encoded to FLAC and checked sample for sample against the original. More thanks in
[THIRD_PARTY_CREDITS.md](THIRD_PARTY_CREDITS.md).
