# options_keys

**Status:** on hardware (including the `ingn` save). The mod section appears in `options.txt` and the keys
take effect.

## What it does

Adds `tape`, `octl`, `fxsl`, `cpul`, `mcap`, `sldm`, `root` and
`tlen` and `ingn` to `options.txt` (see [docs/OPTIONS.md](../../docs/OPTIONS.md)).

- **Parser hook** (0x08023326): checks our keys before the stock key dispatch.
  On/off keys accept 0 or 1, `fxsl` 0–2 and `mcap` 0–9 (one digit); `root`
  (0–100) and `tlen` (1–16) read up to four digits. Anything else is ignored.
- **Writer hook** (0x0802455e): just before the stock writer's final `f_close`,
  it appends:
  - the `//Morphagene Study mods` section with the current values and comments;
  - a comment line for SHIFT + Slide.

**Settings block** (0x2002A0F0): "OPTS" magic, then +4 `tape`, +5 `octl`,
+6 `fxsl`, +7 unused, +8 `cpul`, +9 `mcap`, +10 `sldm`, +11 `root`, +12
`tlen`, +13 `ingn`, +14 applied this boot, +15 pending gain + 1. sd_updater
writes the defaults every boot.

## Input gain (`ingn`)

The stock firmware resets the input gain (REC held + SHIFT taps, index at
`0x20001068`) to 0 at every power-up, before `options.txt` is read.

- **Main-loop hook** (0x08023ee6): the request dispatcher's test of flag
  `0x80` (rewrite `options.txt`) in `0x20022074`. It is reached only when no
  other card request is pending. The site is separate from cpu_meter's idle
  hook at 0x08023eec, so the two modules don't share a site.
- **First pass after boot:** writes `ingn` to the gain and calls the stock
  codec routine (0x080257dc) once.
- **After that:** a gain that differs from `ingn` and stays unchanged for 3 s
  (18,000 audio blocks), with no recording and the card mounted, is copied to
  `ingn`. Flag `0x80` is then set with interrupts masked, and the pass carries on into the
  stock writer. This is the same rewrite stock does after every reel load.
  Going back to the saved value cancels a pending save.
- **Writer:** the `ingn` line always prints the live gain, so any rewrite keeps it.

**Requires:** sd_updater.

## Verification (emulator)

- **Parser:** every key and value, invalid and out-of-range values, and stock
  keys passing through.
- **Writer:** stored and default values, with a mock `f_printf`/`f_close`.
- **Gestures:** each setting switches its gesture on and off.
- **Input gain** (the research repository's `verify_patch_input_gain.py`, not public; on a built
  image): `ingn` parsing and range, the writer line, and 16,000 main-loop
  passes against a model (boot apply, 3 s wait, recording, card state,
  restart and cancel, exit target, registers, stack alignment at the codec
  call, `FLAGS` written only with interrupts masked).
