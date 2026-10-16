# gene_shape

**Status:** on hardware.
- **Works:** Slide jitter; Turing mode (played on the module, 2026-10-10).
- **Reel mode fixed:** earlier builds hooked Gene Size at 0x0802780a, which
  covered a branch target of the reel-mode path and crashed in reel mode. The
  hook is now at 0x08027808 (confirmed on hardware).

## Slide jitter: SHIFT + Slide

Sets a jitter amount, `((knob − 48) / 4000)²`; fully left is off. Each new Gene
starts at its stock start plus a random offset of up to ± amount / 2 of the
splice, wrapped inside the splice. It is applied in both paths' Gene-birth code
(GA 0x0802838a, GB 0x08029bb8), with its own xorshift32 generator. It costs
nothing between births.

## Knob holds and pickup

During a gesture (SHIFT + Slide, or SHIFT + Gene Size in Turing mode), the knob doesn't move Gene Size or Slide. Afterwards
they hold their pre-edit value until the knob comes back within 48 counts:
- Gene Size: hooks G2 0x08027808 and G3 0x080288ee;
- Slide: hook GS 0x08027972.

## Turing mode: `sldm 1`

A loop of random seeds decides each Gene's random choices, so the randomness
repeats like a Turing Machine. Set `sldm 1` in `options.txt`; `tlen` (loop
length, 1–16, default 8) and `root` (default 50) are optional.

**Play it:**
1. Gene Size about 1 o'clock (short Genes; position scatter needs the shorter
   half of Gene Size). Morph low for a melody (one Gene at a time), higher for
   harmony (overlapping Genes at different ratios).
2. **Lock:** hold SHIFT and turn Organize fully left. The pattern repeats.
3. **Mutate:** SHIFT + Organize up from the left; a step occasionally gets a
   new seed. Fully right is normal randomness (stock), which is also "off".
4. **New pattern:** SHIFT + Organize fully right, then back to fully left.
5. **No pitch shifting:** `root 100`.

| Control | With `sldm 1` |
|---|---|
| SHIFT + Organize | Evolution: fully left (bottom 96 counts) locked, fully right (top 160 counts) stock |
| SHIFT + Gene Size | Genes per step: 1, 2, 3, 4, 6, 8, 12, 16 |
| SHIFT + Slide | Spread: the Slide jitter, with each step keeping its own offset when locked |
| SHIFT + Morph | Unchanged (tape_sos effect) |
| `tlen`, `root` | Loop length; chance in percent that a step plays the root |

**What the seed decides** at each Gene start: the chord ratio (root with
probability `root` %, otherwise `mcr1`–`mcr3` evenly, at any Morph), the
stereo crossmix and Morph's position scatter, plus the spread offset. Morph
still decides how much overlap, crossmix and scatter there is. Organize is held
while SHIFT is down and after an edit, so the selected splice never moves.
Knobs pick up as with the other gestures. There is no LED feedback.

**How:** at each Gene birth (GA/GB) the step's seed is written into the stock
RNG state slot, so the stock draws replay; hooks CA (0x08028490) / CB
(0x08029cb4) replace the per-Gene chord index with the step's pick; O1
(0x080276f0) holds Organize and reads evolution. With evolution fully right
nothing changes: audio is byte-identical to `sldm 0`. State: 0x2002A740
(cleared by sd_updater at boot). CPU: a few dozen instructions per Gene start.

## Verification (emulator)

- **Fragments against float32 models:**
  - Gene Size hold and pickup (2,000 cases);
  - Slide hold and jitter amount (2,000);
  - Gene births in both paths (3,000).
- **Through the real audio routine:** with jitter off, every new Gene starts
  exactly where stock starts it. With jitter on, starts spread across the
  splice in both paths.
- **Whole session:** both gestures take effect, pickup releases, and all
  session checks pass.

- **Turing** (the research repository's `verify_patch_turing.py`,
  `verify_patch_turing_controls.py`):
  - 4,000 Gene births in both paths against a float32 model (step, length,
    rate, evolution, seed replay, locked scatter, chord pick, registers);
  - 600 chord-store cases; evolution, rate and spread knob mappings; parser;
  - whole audio blocks: a locked loop repeats every `tlen` births; the chord
    ratio follows `root` (100 / 50 / 0) at Morph 0.29 and 0.93; evolution 1
    is byte-identical to `sldm 0`;
  - a whole session through every gesture, with no navigation or splice
    change, and `sldm 0` unchanged.

An earlier hook site (0x08029970) turned out to be a per-sample calculation in
one path only; jitter did nothing on hardware. The birth check above was added
because of that.
