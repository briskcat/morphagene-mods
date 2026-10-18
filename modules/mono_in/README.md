# mono_in

**Status:** emulated. Not yet tried on hardware.

**What it does.** With `mono 1` in `options.txt`, the left input is copied
onto the right, so a mono signal into L is heard and recorded on both
channels. This is how Beads, Clouds and Mimeophon treat a mono input. With
`mono 1` the R input is ignored. `mono 0` (the default) is stock stereo.

**Why a setting, not automatic.** Those modules normal L to R when nothing is
plugged into R. The Morphagene firmware has no way to tell: no code reads a
jack-detect pin for R in. Every GPIO input read in mg204 is accounted for:
Play (PA5), SHIFT (PC1), SPLICE (PE2), CLK (PG10), REC (PG12) and the SD card
(PH13). A detect line could still be wired to a pin the firmware never reads.
Only a hardware probe could show that.

**Hook** (0x08027518): the entry `push` of the audio block. The RX DMA
interrupt calls the block with r0 = the RX half it just filled (interleaved
int16 L/R, 8 frames). Dry monitoring and recording both read the input only
from that buffer. With `mono 1`, each frame's L sample is copied over its R
sample before the block reads them. The cost is under 100 cycles per block,
about 0.3% of the 30,006-cycle budget.

**Setting:** SETTINGS +7 (`mono`, 0 or 1), parsed and written by
options_keys. sd_updater sets it to 0 at every boot, before `options.txt` is
read. Without the settings block (no sd_updater), it stays off.

**Verification (emulator)**, from the research repository's
`verify_patch_mono_in.py` on *Full* built with and without this change:
- **Parser:** `mono 0`/`mono 1` store the setting; `mono 2`, `mono x` and a
  bare `mono` are ignored. Other settings are untouched, and stock keys still
  go to the stock dispatch.
- **Writer:** the `mono` line prints the stored value (0 with no settings)
  just before the stock `f_close`.
- **Whole audio blocks** (original init, TIM2 interrupt and audio block):
  Play held, recording, at S.O.S. 0, 2048 and 4095, with a signal into L.
  - With `mono 1`, R silent or R noise: the output and the recorded SDRAM
    are **bit-identical** to the old build fed the L signal on both channels.
  - With `mono 0`: bit-identical to the old build with the same stereo input.
  - Play off, S.O.S. 0 (dry only): every output frame has L = R.

**Try it.** Set `mono 1`, patch a mono source into L only, and listen to both
outputs. Then record and play back: both channels should carry the recording.
