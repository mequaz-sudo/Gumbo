# Gumbo — licence

Copyright (c) 2026 EON Studios (Quaz). All rights reserved.

Gumbo is free. You may download it, install it and use it at no cost, for any music, sound or audio work,
commercial or not. Everything you make with it is yours.

Without written permission from EON Studios you may not:

- copy Gumbo's code, in whole or in part, into another program, plugin or script;
- share changed versions of it;
- sell, rent or bundle Gumbo, or host copies of it for download (point people to the official repository instead);
- remove this notice or the copyright lines in Gumbo's files.

This covers Gumbo's own files: `Gumbo_ReaKit.jsfx`, the `gb_*.jsfx-inc` includes beside it (`gb_sfz`, `gb_load`,
`gb_voice`, `gb_helper`, `gb_eq`, `gb_face`, `gb_face_p2`) and the Gumbo scripts (`Gumbo helper.lua`,
`Gumbo - Add a library.lua`, `Gumbo - Start with REAPER.lua`, `gumbo_sfz.lua`, `gumbo_index.lua`,
`gumbo_helper_core.lua`). The other ReaKit includes installed with it (knobs, buttons, meters, theme, piano, the curve
painter and the rest) are EON Studios' ReaKit library under the MIT licence (`LICENSE` in the repository).

Gumbo's EQ and TONE run on Quezy's filter engine, shared with EON Studios' free Quezy EQ:

- `qz_engine.jsfx-inc` is EON Studios' code under the EON Free Licence 1.0 (free to use; not for sale or reuse of its
  code); the parts it ports from Justin Johnson's ReEQ keep ReEQ's MIT licence, below.
- `rk_svf.jsfx-inc` is a port of Justin Johnson's state-variable filter (MIT; the full notice is in the file); its
  filter math is Andrew Simper's (Cytomic), from his published papers.
- `rk_svf_match.jsfx-inc` is EON Studios' code after Yuriy Ivantsov's matched-filter method (MIT; the notice is in
  the file).

ReEQ's notice, as its MIT licence asks:

> MIT License
>
> Copyright (c) Justin Johnson
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
> documentation files (the "Software"), to deal in the Software without restriction, including without limitation the
> rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
> permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of
> the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
> WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
> COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
> OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

The sounds are separate packages with their own terms: the starter sounds and the VSCO 2 CE orchestra are Versilian
Studios' VSCO 2 Community Edition, released under CC0 1.0 (public domain); the licence file is beside the samples.
SFZ libraries you load are under their own makers' terms.

Gumbo is provided as is, without warranty of any kind. EON Studios is not liable for any damage or loss arising
from its use.

Contact: eonaudio.pro
