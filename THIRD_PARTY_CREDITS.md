# Third-party credits

- **MuseScore General** (S. Christian Collins; from FluidR3 by Frank Wen and FluidR3Mono by Michael Cowgill; Temple
  Blocks by Ethan Winer, Drumline Cymbals by Michael Schorsch; MIT): the Gumbo GM sounds, converted for Gumbo by EON
  Studios. Its acknowledgements and copyright notices are in
  `GM/Data/EON_Gumbo/Library/MuseScore General/MuseScore_General_License.md`, beside the sounds.
- **sfizz** (the SFZ engine by the SFZ Tools developers, BSD 2-Clause): Gumbo's code is EON Studios' own, and its
  playback was measured against sfizz 1.2.3 and matched to it. The envelope curves, velocity, panning, the region EQ
  bands and default release follow sfizz's published source, acknowledged here as the reference.
- **sfzformat.com**: the SFZ format reference Gumbo reads its files by.
- **Justin Johnson (ReEQ, MIT)**, **Andrew Simper (Cytomic)** and **Yuriy Ivantsov (MIT)**: Gumbo's EQ and TONE run
  on Quezy's filter engine (ReEQ's state-variable filter and band design, Simper's filter math, Ivantsov's matched
  coefficients). The notices are in the files and in `Gumbo/Gumbo_LICENSE.md`.
- **Michael Gruhn (LOSER), "Saturation" (2006-2007)**: DRIVE uses his sine waveshaper curve, with acknowledgement of
  the author as his notice asks (`Gumbo/ReaKit/rk_sat.jsfx-inc`).
- **SPACE and CHORUS**: the rooms follow **William G. Gardner**'s "The Virtual Acoustic Room" (MIT Media Lab, 1992);
  the halls port the Faust library's `zita_rev1_stereo` by **Julius O. Smith III** (STK-4.3), a model of **Fons
  Adriaensen**'s zita-rev1; the plate ports **Chris Johnson**'s kPlateA (Airwindows, MIT); the chorus ports **Peter
  Allwin**'s junologue-chorus (MIT) with **Emilie Gillet**'s stmlib SoftLimit (MIT). The feedback chorus and flanger
  are EON Studios' own code at the values the MMA's **General MIDI 2** specification publishes. The notices are in
  `Gumbo/Gumbo_LICENSE.md`.
- **FluidSynth** (LGPL 2.1 or later): Gumbo's code is EON Studios' own; the reverb and chorus levels and the SoundFont
  defaults (the pressure vibrato, the 24-bit rule) were measured against FluidSynth 2.6.2 or follow its published
  behaviour, acknowledged here as the reference.
- **The ReaKit library** (EON Studios, MIT): the other includes in `Gumbo/ReaKit/`.
