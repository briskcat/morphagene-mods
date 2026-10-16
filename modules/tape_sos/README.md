# tape_sos

**Status:** on hardware.
- **Works:** tape mode and feedback at normal settings; SRR; warble (the
  Varispeed LED keeps its octave colours while warbling).
- **Known issue:** at high Morph, tape dubbing and SRR can glitch (CPU, see
  below).

## SHIFT + S.O.S.

The first SHIFT + S.O.S. turn after power-up switches mode. S.O.S. is stock
until then. What it switches to depends on `options.txt`:

**`tape 1` (default): tape mode.** While overdubbing an existing splice:
- **Raw input.** The record signal is the raw input, with no S.O.S. mix and no
  splice filter.
- **A tape head.** A fractional head moves at the glided Varispeed rate inside
  the Slide / Gene Size window. It follows the knobs live and wraps inside the
  window. Reverse works; zero speed pauses writing.
- **Retention.** Each crossed sample becomes `stored × retention + input`.
  SHIFT + S.O.S. sets retention (stock S.O.S. curve). At 100% retention with
  silent input, nothing is written.
- **The listening mix** stays on S.O.S. (with pickup after a SHIFT edit).
- **Morph cap.** Morph is limited to `mcap`/10 (default 0.3; `mcap 0` = no
  cap) while tape mode is dubbing, to stay within the CPU budget.

**`tape 0`: classic TLA feedback.** The record signal becomes
`clamp(input + f × Gene playback)`, and SHIFT + S.O.S. sets `f`. This makes
sound-on-sound with TLA easier without tape mode's head. Input Only stays
stock.

## SHIFT + Morph: SRR (`fxsl 1`)

Sample-and-hold rate reduction on the **Gene playback**, before the S.O.S. mix.
The dry input is untouched, so in feedback / stock TLA the effect builds up pass
by pass.

- **Amount.** The knob position sets it. Fully left (the bottom 96 counts; the
  knob's lowest reading is about 56) is off. Fully right holds
  at 200 Hz, with the wet mix at `min(1, 4 × amount)`.
- **Morph pickup.** Morph holds its pre-edit value until the knob returns
  within 48 counts.
- **Reset.** The amount resets at power-up.

## SHIFT + Morph: warble (`fxsl 2`)

Tape wow and flutter on the Gene playback speed, recreating the pitch movement
of the plugin's Prism Warble without a delay line. Same gesture, pickup and
dead zone as SRR.

- **How.** A virtual tape delay drifts toward random targets ((30·amount + 0.1)
  events per second). Once per block the Gene playback rate is multiplied by
  1 − Δd/8. The offset from stock stays bounded (up to about 18 ms).
- **Depth.** About 1.4 semitones at full amount, 2.5% pitch at 0.3.
- **Exact again at 0.** The delay returns to rest in about 1 s, then the rates
  are set back exactly to stock, so 1× and the octave lock stay exact.
- **Not in tape dubs.** The tape head runs at the clean Varispeed speed. In
  classic TLA (`tape 0`), the warbled playback is re-recorded, as with SRR.
- **LED.** Hook L1 gives the stock Varispeed LED code the clean target, so its
  octave colours hold while warbling.
- **Cost.** About 130 instructions per block; cheaper than SRR.

## Hooks

| Hook | Site | Rate | Does |
|---|---|---|---|
| P7 | 0x080276c4 | block | S.O.S. edits, retention/feedback, monitor pickup, tape-engine flush |
| P10 | 0x08027984 | block | SRR amount and Morph pickup, Morph cap; sets the per-sample flags |
| P11 / P12 | 0x08028e7a / 0x0802a148 | sample | Paths A / B: SRR, the stock S.O.S. mix, then the tape or feedback record path. One byte gates it all |
| WA / WB | 0x080291d8 / 0x0802a4bc | sample, while recording | Paths A / B: buffer the frame for the tape engine (it writes once per block) |
| L1 | 0x08024af8 | TIM2 | Varispeed LED: the clean target while warbling |

**State:** MOD +16..+91, +94..+127, +144..+207, +232..+233. The tape engine is
copied to SRAM at 0x2002A100. Warble state: 0x2002A700 (cleared by
sd_updater at boot).

## CPU

At high Morph with short Genes, stock is already at its limit. Emulated
instructions per block (Gene Size 3000, Morph 4000):

| Build | Instructions |
|---|---|
| Stock | 8,194 |
| Mod, idle | 8,395 |
| Mod, SRR on | 8,593 |

Tape dubbing reads every sample it writes. If high Morph glitches are a
problem, use `fxsl 0` (no SRR) or `fxsl 2` (warble is cheaper), keep flash prefetch on (it always is)
(cpu_meter), or lower `mcap`.

## Verification (emulator)

- **Mix paths.** Both paths compared with the stock firmware's mix, case by
  case:
  - with SRR active, the result equals stock mixing the SRR'd playback
    (1,600 cases);
  - SRR together with classic feedback (800 cases);
  - tape and feedback modes (2,404 cases).
- **SRR control.** 3,000 cases against a float32 model.
- **Warble.** Bit-exact against a float32 model over 29,000 blocks (55 stock
  target changes, both glide styles, two returns to rest); the tape head rate
  excludes the warble; LED cases; whole audio blocks return exactly to the
  stock rate.
- **Tape engine.** 14,400 steps against a model.
- **Whole sessions:** all checks pass.
