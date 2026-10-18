# mono_in

**Status:** on hardware (2026-10-18): `mono 1` and `mono 2` (auto) both work. Auto went mono with R unplugged and stayed stereo with a stereo source.

**What it does.** A mono signal into L is heard and recorded on both
channels, the way Beads, Clouds and Mimeophon treat a mono input.

| `mono` | Behaviour |
|---|---|
| 0 (default) | Stereo, as stock |
| 1 | L is always copied onto R; R in is ignored |
| 2 | Auto: L is copied onto R only while R in is quiet |

**Why auto listens to R instead of the jack.** Those modules normal L to R
when nothing is plugged into R. The Morphagene firmware has no way to tell:
no code reads a jack-detect pin for R in. Every GPIO input read in mg204 is
accounted for: Play (PA5), SHIFT (PC1), SPLICE (PE2), CLK (PG10), REC (PG12)
and the SD card (PH13). A detect line could still be wired to a pin the
firmware never reads; only a hardware probe could show that.

**Auto mode (`mono 2`).**
- **Going mono:** when every R sample has stayed below 128 (about −48 dBFS)
  for 0.5 s, R fades to a copy of L over about 11 ms.
- **Going back to stereo:** a single louder R sample starts the fade back at
  once, so a stereo source takes over within a few milliseconds.
- **Catch:** a stereo source whose right side stays below −48 dBFS for half a
  second turns mono until R comes back. If an unplugged R in is noisier than
  the threshold on your module, auto stays stereo; tell us and the threshold
  can become a setting.

**Hook** (0x08027518): the entry `push` of the audio block. The RX DMA
interrupt calls the block with r0 = the RX half it just filled (interleaved
int16 L/R, 8 frames). Dry monitoring and recording both read the input only
from that buffer, so rewriting R there changes both. The cost is at most a
few hundred cycles per block, about 1% of the 30,006-cycle budget.

**Setting:** SETTINGS +7 (`mono`, 0–2), parsed and written by options_keys.
sd_updater sets it to 0 at every boot, before `options.txt` is read. Without
the settings block (no sd_updater), it stays off.

**State:** RAM 0x2002A608 (quiet blocks) and 0x2002A60C (crossfade gain). It
isn't cleared at boot, so out-of-range values are treated as stereo.

**Verification (emulator)**, from the research repository's
`verify_patch_mono_in.py` on *Full* built with and without this module:
- **Parser:** `mono 0`, `1` and `2` store the setting; `mono 3`, `mono x` and
  a bare `mono` are ignored. Other settings are untouched, and stock keys
  still go to the stock dispatch.
- **Writer:** the `mono` line prints the stored value (0 with no settings)
  just before the stock `f_close`.
- **Auto mode against a bit-exact model:** about 23,000 blocks of the hook on
  its own. They cover silent R, near-silent noise, loud bursts, single loud
  samples, switching modes and garbage state RAM. The whole input half and the
  state match the model, and the registers and stack are preserved.
- **Whole audio blocks** (original init, TIM2 interrupt and audio block):
  Play held, recording, at S.O.S. 0, 2048 and 4095, with a signal into L.
  - With `mono 1`, R silent or R noise: the output and the recorded SDRAM
    are **bit-identical** to the old build fed the L signal on both channels.
  - With `mono 0`: bit-identical to the old build with the same stereo input.
  - With `mono 2` and loud noise on R: bit-identical to the old build (stays stereo).
  - With `mono 2`, R silent, Play off, S.O.S. 0: L = R in every output frame
    once the hold time and fade have passed.
  - Play off, S.O.S. 0, `mono 1` (dry only): every output frame has L = R.

**Try it.** Set `mono 2`. Patch a mono source into L only: after half a
second both outputs carry it. Patch a stereo source into both: it stays stereo.
