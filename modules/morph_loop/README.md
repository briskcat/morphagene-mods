# morph_loop

**Status:** emulated. The whole audio block was run in the emulator; not yet
tried on a module.

**What it changes.** Stock Morph picks one of 22 presets
(`min(int(morph × 33.99), 21)`). Each one sets a *length fraction*: the next
Gene starts after `Gene length × fraction`. The lowest four presets are:

| Preset | Morph | Stock fraction | Stock divisor | Sound |
|---|---|---|---|---|
| 0 | 0–0.029 | 2.0 | 1 | Gene, then a gap of silence (halved until at most 0.25 s longer than the Gene) |
| 1 | 0.029–0.059 | 1.5 | 2 | Shorter gap |
| 2 | 0.059–0.088 | 1.333 | 3 | Shorter gap |
| 3 | 0.088–0.118 | 1.0 | 1 | Seamless loop (about 8 o'clock) |

This module gives presets 0–2 preset 3's fraction (1.0) and scheduling
divisor (1). Morph fully down, up to about 8:30, then plays the same seamless
loop. Overlap still starts at preset 4, as in stock.

Because the stock fade rule keys on `fraction == 1`, presets 0–2 also take
preset 3's short 250-sample (about 5 ms) crossfade, in both `gnsm` modes.

**Change:** five 4-byte edits in the initialized-data image (flash
0x08047250, copied to RAM 0x20000000 at reset), no code.

| Address | Table, preset | Stock | New |
|---|---|---|---|
| 0x08047630 | length fraction, 0 | 2.0 | 1.0 |
| 0x08047634 | length fraction, 1 | 1.5 | 1.0 |
| 0x08047638 | length fraction, 2 | 1.333333 | 1.0 |
| 0x08047744 | scheduling divisor, 1 | 2 | 1 |
| 0x08047748 | scheduling divisor, 2 | 3 | 1 |

**No setting.** It's a table edit, so it can't be switched in `options.txt`.
It's in its own remix, *Full + Morph loop*; pick *Full* for stock Morph.

**Not yet confirmed:**
- Genes born exactly at Morph 0.0882613 (preset 3's lower edge) set a per-Gene
  flag. It made no difference in the playback test, but other modes
  (clocked, recording, reel changes) weren't run.
- What the scheduling divisor changes with a clock patched in isn't traced.
  Clocked behaviour at the bottom of the knob now matches preset 3's.

**Verification:**
- The stock bytes at all five addresses were read from a fingerprinted mg204
  image; preset 3 holds 1.0 and divisor 1 as expected.
- *Full + Morph loop* is *Full* (reproduced bit for bit from `web/remixes.js`)
  with only these five edits; its sha256 is recorded in the remix.
- **Lookup, emulated:** the original preset lookup (0x0802796a) run for every
  Morph reading 0–4095. Readings 0–482 now load preset 3's fraction, overlap
  and divisor (stock: preset 3 is 362–482); 483–4095 and the instruction path
  match *Full* exactly. Each table is read only there (one literal each).
- **Playback, emulated:** original init, TIM2 interrupt and audio block, Play
  held, Gene Size reading 3500 (a 3,136-sample Gene), 1 s each. *Full* at
  Morph reading 0 is silent for 49% of frames, at 240 for 33%. *Full + Morph
  loop* at 0 and 240 gives **bit-identical output** to *Full* at 420 (8
  o'clock): a Gene every 3,136 samples, no silent frames.
- Research repository: `verify_patch_morph_loop.py`.

**Try it.** Record a loop, Gene Size fully down (whole splice), Morph fully
down. It should loop with no gap, as stock does at 8 o'clock.
