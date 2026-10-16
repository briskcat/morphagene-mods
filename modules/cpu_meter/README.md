# cpu_meter

**Status:** on hardware. Prefetch and the log were run on the module
(2026-10-07); logs are kept in the project's separate (private) research repository.

## Flash prefetch: always on

The firmware runs from flash with 5 wait states at 180 MHz. Stock turns on the
flash caches but leaves the prefetch buffer off (FLASH_ACR `0x605`). This
module writes `0x705` at boot instead (one immediate at 0x0802153a). Stock
writes FLASH_ACR only at that one place, so prefetch stays on. There is no setting:
it has no downside, and installing stock firmware restores the stock value.

**Measured on the module:** prefetch saves about 3–5k cycles per audio block
under load (10–17% of the 30,006-cycle budget). Without it, high Morph + SRR
and high-Morph dubbing glitched; with it they didn't.

## CPU log: `cpul` (default 0, troubleshooting only)

The audio routine already times itself with the DWT cycle counter, but stock
never starts the counter. This module starts it and collects, per second of
audio: peak and mean cycles per block, blocks over 80% and 100% of the block
period, and the context at the peak (active Genes, Morph, Gene Size, rate,
recording, tape mode, SRR). With `cpul 1`, at most every 10 s, at the idle end
of a main-loop pass, it appends the finished seconds to `cpulog.txt` with the
firmware's own FatFs (the same point where stock rewrites `options.txt`).

```text
//sec peak mean over80 over100 genes morph gsize rate rec tape srr
0 13764 13702 0 0 1 2048 1500 1000 0 0 0
```

**Reading it.** The counter only covers the audio routine, not interrupt
latency before it, so glitches can happen with `over100 = 0`. Treat a peak of
about 27.5k cycles as the practical ceiling.

## Hooks

| Hook | Site | Does |
|---|---|---|
| PF | 0x0802153a | Boot: FLASH_ACR 0x605 → 0x705 (byte patch) |
| A1 | 0x08028666 | End of every audio block: counter start, statistics |
| M1 | 0x08023eec | Idle main loop: append to `cpulog.txt` every 10 s |

**State:** RAM 0x20029000–0x20029FFF (statistics, a 64-second ring, the FIL).
Settings come from options_keys (`cpul`); without it, prefetch is still on
and the log off.

## Verification (emulator)

The research repository's emulator test (`verify_patch_cpu_meter.py`, not public):
- **A1** against an independent model: 21,000 random blocks (ring contents,
  both thresholds, flags and registers), plus counter start, ring-full drops,
  reset detection, `cpul 0`, no settings, only bit 8 of FLASH_ACR
  touched.
- **M1** with a mock FatFs: 10 s pacing, header once per session, exact lines,
  open and seek failures retried later, card not mounted; registers and stack
  alignment preserved.
- **Whole audio blocks:** identical audio output with and without the module.
- The whole-session regression.
