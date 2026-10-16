# Firmware map (mg204)

This is what module authors need to know about the stock application. All of it
was recovered by reverse engineering and checked by running the original
instructions in an emulator (Unicorn). Addresses are for mg204 only.

## Image and processor

- **Processor:** STM32F427/429, Cortex-M4F (Thumb-2 with a single-precision
  FPU), 180 MHz.
- **Application:** starts at 0x08020000 (flash sectors 5 and 6, 256 KiB). The
  stock image is 0x28400 bytes; modules are appended after it.
- **Never written:** the bootloader (below 0x08020000) and the calibration
  (sector 3, 0x0800C000).

## Where the work happens

| Routine | Address | Rate | Notes |
|---|---|---|---|
| Audio block | 0x08027518 | 6,000/s (8 frames at 48 kHz) | Two reconstruction paths, A (around 0x08028000) and B (around 0x0802a000): four-point interpolation when the Genes' envelope sum is ≤ 2, linear otherwise. Per-sample code is duplicated in both, so per-sample hooks come in pairs |
| TIM2 interrupt (vector 44) | 0x08024718 | about 20,000/s | Buttons, debounce, SHIFT state machine, LEDs (shifted out serially), gate outputs |
| Control ADC DMA interrupt | 0x080263e4 | per ADC scan | Averages the six knob+CV channels |
| Startup | `application_main` | once | Card mount at 0x08023132; on success it continues at 0x08023288 (sd_updater hook) |

## Knob readings (0..4095, knob and CV summed before the ADC)

The attenuverters are analog, in the CV path, so the firmware can't see them.

| Control | Address | Averaging |
|---|---|---|
| S.O.S. | 0x20021c68 | 16 |
| Morph | 0x20021c6c | 16 |
| Organize | 0x20021c70 | 64 |
| Varispeed | 0x20021c74 | 64 |
| Slide | 0x20021c78 | 4 (noisy: gestures use a wider threshold) |
| Gene Size | 0x20021c7c | 64 |

## Stock options (`options.txt`) at 0x200012a8

| Offset | Key | Offset | Key |
|---|---|---|---|
| +0 | vsop | +28 | rsop |
| +8 | pmod | +32 | pmin |
| +12 | omod | +36 | inop |
| +20 | cvop | +40 | gnsm |
| +24 | ckop | | |

**How the parser works:** it skips line 1, takes the first four characters as
the key, and stores the digit at position 5 minus `'0'`, without a range check.
The writer prints the stored value back. `gnsm` is read in one place
(0x0802897a), as zero or non-zero.

## Useful state

| Address | Meaning |
|---|---|
| 0x20022108 | Recording active |
| 0x200012e0 | Navigation request (SHIFT release → next splice) |
| 0x20001020 | SHIFT state machine state (14 = SHIFT held) |
| 0x200220e8 / 0x200220e0 | Varispeed target rate / glided rate used per sample |
| 0x20022154 | Slide (0..1, smoothed per sample) |
| 0x2002215c, 0x2002208c | Splice markers, marker count |
| 0x20021e0c / 0x20021e08 | Gene fade length (samples) / per-sample envelope step (1/fade). Rewritten every block |
| 0x20021e64… | Per-Gene arrays (4 slots): envelope, crossmix, elapsed, rate selector, position, length, bounds, phase |
| 0x20021de8 | End-of-splice trigger. Set to 4 by the envelope code, counted down by TIM2 to drive the splice LED and the gate |

**Fade 250 means full splice.** With Gene Size fully counter-clockwise, stock
forces a 250-sample fade. The end-of-splice test (0x08028ca2) checks for
exactly 250. A module that changes the fade must keep 250 in that case, or the
gate and splice LED stop working.

**Gene envelope hold step.** While a Gene is held, its level alternates
between 1 and 1 + step on alternate samples. A very short fade therefore
causes audible ripple; `gene_shape` stops at 8 samples.

## Module state

All patch RAM sits in the gap between `.bss` (ends at 0x200243c8) and the
stacks. None of it is zeroed at reset.

**MOD block (0x2002A000).** "SHFT" magic at +0. When the magic is missing,
shift_gestures zeroes +4..+239 once.

| Offsets | Owner | Use |
|---|---|---|
| +0..+15 | shift_gestures | Magic, SHIFT session (active, consumed, owner, lock), snapshots |
| +16..+91 | tape_sos | Tape/feedback mode, retention, tape head, block cache, RAM-copy flag |
| +92..+93 | shift_gestures | Morph snapshot |
| +94..+127 | tape_sos | SRR state |
| +128..+130 | shift_gestures | Organize snapshot and hold (gene_shape releases the hold) |
| +144..+207 | tape_sos | Tape frame buffer |
| +208..+211 | shift_gestures | Gene Size / Slide snapshots |
| +212..+231 | gene_shape | Pickups, window, jitter amount, random generator |
| +232..+233 | tape_sos | Per-block flags for the per-sample hooks |

**SETTINGS (0x2002A0F0).** "OPTS" magic (set by sd_updater with the defaults
every boot), then +4 `tape`, +5 `octl`, +6 `fxsl`, +7 unused, +8 `cpul`,
+9 `mcap`, +10 `sldm`, +11 `root`, +12 `tlen`, +13 `ingn` (saved input gain),
+14 ingn applied this boot, +15 pending gain + 1 (0 = none).

**Other RAM:**
- 0x20029000..0x20029FFF: cpu_meter statistics, ring and FIL.
- 0x2002A100..0x2002A5FF: the tape engine, copied to SRAM.
- 0x2002A600..0x2002A603: options_keys, block count when a new input gain was first seen.
- 0x2002A604..0x2002A605: options_keys, `scal` mask (bit *d* = *d* semitones), cleared by sd_updater every boot.
- 0x2002A700..0x2002A73F: tape_sos warble state.
- 0x2002A740..0x2002A7FF: gene_shape Turing state.
- 0x2002B000..0x2002B7FF: the SD updater's FatFs objects and flasher.
- During an SD update only, the image is staged in SDRAM at 0xD0000000.

**Gesture owners** (MOD +6): 1 S.O.S., 2 Varispeed, 3 Morph, 4 Gene Size,
5 Slide, 6 Organize.

## FatFs functions (linked in the stock image)

| Function | Address |
|---|---|
| `f_mount` | 0x0803219c |
| `f_open` | 0x08032260 |
| `f_read` | 0x080323fc |
| `f_close` | 0x080327a8 |
| `f_lseek` | 0x08032be8 |
| `f_stat` | 0x08033128 |
| `f_rename` | 0x08033848 |
| `f_gets` | 0x0803449c |
| `f_printf` | 0x08034804 |

## CPU budget

At high Morph with short Genes, the stock audio block is already at the
processor's limit; stock can glitch there.

Emulated instruction counts per block (Gene Size 3000, Morph 4000):

| Build | Instructions |
|---|---|
| Stock | 8,194 |
| `full`, everything idle | 8,395 |
| `full`, SRR on | 8,593 |

Instruction counts understate the real cost of high Morph, because SDRAM
reads stall.

**Rules of thumb:**
- Do work per block, not per sample.
- Gate per-sample hooks on one byte that a per-block hook sets.
- Use registers the stock code is about to overwrite instead of saving and
  restoring your own.

## Hook-writing gotchas

- **Live registers.** `ip` (r12) and `lr` are live in the audio routine; save
  them, or call helpers with `push {lr}` around `bl`.
- **Rebuild what you replace.** Re-run every instruction your hook overwrites,
  including PC-relative literal loads (load the value from your own pool).
- **Flags and IT blocks.** Check whether the following stock code reads the
  flags, and never hook inside an IT block.
- **Branches into the window.** Make sure nothing else branches into the bytes
  your B.W replaces (search the disassembly). gene_shape's first Gene Size hook
  sat at 0x0802780a and covered 0x0802780c, a target of the reel-mode path:
  reel mode crashed until it moved to 0x08027808.
- **Range.** `cbz`/`cbnz` reach only forward, 126 bytes. Use `cmp` + `beq` when
  the assembler says "branch out of range".
