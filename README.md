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
- **Your own SFZ libraries**: run the **Gumbo helper** action and drop any .sfz on Gumbo's window. **Gumbo - Add a
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

## Licence and credits

Gumbo is free to use; its code stays EON Studios' ([Gumbo_LICENSE.md](Gumbo/Gumbo_LICENSE.md), which also lists the
MIT and EON Free Licence parts it is built on). Gumbo GM is made from **MuseScore General** by
**S. Christian Collins**, built on FluidR3 by **Frank Wen** and FluidR3Mono by **Michael Cowgill**, under the **MIT**
licence; its notices are in `MuseScore_General_License.md` beside the sounds. EON Studios converted it for Gumbo, every WAV
encoded to FLAC and checked sample for sample against the original. More thanks in
[THIRD_PARTY_CREDITS.md](THIRD_PARTY_CREDITS.md).
