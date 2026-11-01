# Gumbo

An SFZ instrument player for REAPER, in one free JSFX, by EON Studios. Pick an instrument in its browser and play,
or drop an SFZ library on its window: Gumbo plays it with velocity layers, round robins, key switches, release
samples, loops, the sustain pedal and each instrument's own envelopes, at full quality, every recording as it was
made.

- **The browser**: family tiles, search by name, and stars for your favourites.
- **The sound**: DRIVE (before or after the EQ), ATTACK, RELEASE, GLIDE, WIDTH, PAN and VOLUME; a four-band EQ (each
  band a bell, shelf or cut) with a dark-to-bright TONE tilt; the library's own controls; pitch and mod wheels.
- **Drums**: a kit's keys carry the names of their sounds, and a PADS page plays the kit as 16 pads a bank.
- **In the mixer**: the keys and wheels play right in the track's strip.
- **Your tracks**: with the Gumbo helper running, each track takes its instrument's name, colour and icon (only where
  you have not set your own).
- **Your own SFZ libraries**: run the **Gumbo helper** action and drop any .sfz on Gumbo's window. **Gumbo - Add a
  library** brings a whole library folder into the browser at once; **Gumbo - Start with REAPER** keeps the helper
  running from launch. One instrument can use up to about 1 GB of sound for now (the browser shows each one's size);
  a bigger library loads only the part that fits.

## The packages

- **Gumbo**: the player and its scripts.
- **Gumbo starter sounds** (about 230 MB): twelve instruments to start with, upright piano, violin and cello
  sections, plucked violins, French horn, trumpet, flute, clarinet, harp, organ, marimba and timpani.
- **Gumbo VSCO 2 CE orchestra** (about 530 MB, 1,900 files): the other 63 instruments of VSCO 2 Community Edition,
  strings, woodwinds, brass, keys and percussion, with key-switched versions and a General MIDI style drum kit.
- **Gumbo GM sounds** (about 45 MB): ten General MIDI instruments from the Discord SFZ GM Bank: acoustic, bright and
  electric grand pianos, an electric piano, steel-string guitar, finger bass, tremolo and pizzicato strings, sitar and
  shanai.

## Install (ReaPack)

1. **Extensions > ReaPack > Import repositories**, paste this address and click OK:

   ```
   https://raw.githubusercontent.com/mequaz-sudo/Gumbo/main/index.xml
   ```

2. **Extensions > ReaPack > Browse packages**, type **Gumbo**, install **Gumbo** and **Gumbo starter sounds** (and
   **Gumbo VSCO 2 CE orchestra** for the whole orchestra, **Gumbo GM sounds** for the GM instruments), then click
   **Apply**.
3. Add a track, click its **FX** button and add `JS: EON: Gumbo`, then pick an instrument in its browser.

## Licence and credits

Gumbo is free to use; its code stays EON Studios' ([Gumbo_LICENSE.md](Gumbo/Gumbo_LICENSE.md), which also lists the
MIT and EON Free Licence parts it is built on). The sounds are **VSCO 2 Community Edition** by **Versilian Studios**
([versilian-studios.com](https://versilian-studios.com/vsco-community/)), released under **CC0 1.0** (public
domain); their licence and readme files are beside the samples. The GM sounds come from the **Discord SFZ GM Bank**:
public domain (CC0), except the acoustic grand, the **Salamander Grand Piano** by **Alexander Holm** (CC-BY);
`LICENSES.txt` beside them credits each one. EON Studios converted them for Gumbo, every WAV
encoded to FLAC and checked sample for sample against the original. More thanks in
[THIRD_PARTY_CREDITS.md](THIRD_PARTY_CREDITS.md).
