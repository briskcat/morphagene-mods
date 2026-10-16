# shift_gestures

**Status:** on hardware. Every SHIFT + Varispeed scale (`octl 1`–`4`) was
tried on a module and checked with a tuner.

## Gestures

Turning a knob while SHIFT is held is a gesture. Releasing SHIFT afterwards
does **not** move to the next splice, and SHIFT + SPLICE/REC combinations are
blocked for that hold. A plain SHIFT tap still moves to the next splice, and
so does a tap while recording.

This module runs the SHIFT session and the knob detection for every gesture:

| Gesture | Owner | Feature lives in | Enabled by |
|---|---|---|---|
| SHIFT + S.O.S. | 1 | tape_sos | always |
| SHIFT + Varispeed | 2 | this module | `octl 1`–`4` |
| SHIFT + Morph | 3 | tape_sos (SRR or warble) | `fxsl 1` or `2` |
| SHIFT + Gene Size | 4 | gene_shape (Turing rate) | `sldm 1` |
| SHIFT + Slide | 5 | gene_shape (jitter / spread) | always |
| SHIFT + Organize | 6 | gene_shape (Turing evolution) | `sldm 1` |

- **Thresholds.** A turn counts after 48 counts of movement (out of 4,095).
  Slide's reading is a 4-sample average, so it needs 96.
- **Order.** Detection runs in this order, and the first knob past its
  threshold owns the gesture.

## Scale lock (SHIFT + Varispeed)

While SHIFT is held, Varispeed snaps to the nearest step of a scale. The glide
lands exactly on the step. The scale comes from `options.txt`:

| `octl` | Steps |
|---|---|
| 1 | Octaves: −2, −1, −½, −¼, stop, ¼, ½, 1, 2 |
| 2 | Octaves + fifths (1, 1.5, 2, …) |
| 3 | Semitones: transpose the reel chromatically |
| 4 | Custom: the semitones listed in `scal` plus the octaves, e.g. `scal 3,5,7,10` (minor pentatonic) |
| 0 | Off |

Every scale is relative to 1× and repeats in each octave, forward and reverse,
from about ⅛× up to 2× (the stock table's range). Stop is always a step.

The stock bidirectional table is `2^((i − 144) / 48)`: 48 entries per octave,
so every semitone is an entry, and that entry is the rate (6 significant digits;
octaves are exact). The lock picks table entries, so it doesn't depend on
`vsop` 0 or 1. `vsop 2` (forward-only table) is left stock.

**Hysteresis.** The current step is kept until another step is nearer by a
margin: two semitones for `octl` 1 and 2, three quarters of a semitone
(about 29 ADC counts) for `octl` 3 and 4. A semitone is only about 39 counts
of knob travel, so fine scales take a careful hand. For "just get back to 1×", `octl 1` is the easiest.

The lock holds after SHIFT is released. Turning Varispeed away by about half an
octave (231 counts) releases it, and the knob is continuous again.

**Cost.** While SHIFT + Varispeed is held, the search walks at most 12 grid
points each way per audio block. Otherwise it costs nothing extra.

**LED.** The Varispeed LED has dedicated colours only for the octave rates;
other steps show the stock in-between colours.

## Hooks

| Hook | Site | Rate | Does |
|---|---|---|---|
| P1 | 0x0802486a | TIM2 | SHIFT session, snapshots, knob claims |
| P3 | 0x080251dc | TIM2 | SHIFT release: no navigation after a gesture |
| P4 | 0x080255da | TIM2 | Same, while recording |
| P5 | 0x0802787c | block | Varispeed scale snap while locked |
| P6 | 0x08027bde | block | Glide coefficient 1 while locked |

**State:** MOD +0..+15, +92..+93, +208..+211. When the "SHFT" magic is
missing, P1 zeroes MOD +4..+239.

## Verification (emulator)

- All 20 SHIFT state-machine states against a model.
- Scale snap (`verify_patch_scale_lock.py` in morphagene-research, on the
  built image):
  - every `octl` mode and several custom scales, vsop 0/1/2, a knob sweep and
    random lock states: 340,800 cases against a model;
  - each snapped rate is a scale step (exact at octaves);
  - `octl 1` still gives exactly the nine octave rates;
  - a held `octl 3` sweep visits all 97 steps in order, up and down;
  - the `scal` parser and writer.
- Whole-session runs of the real audio routine and TIM2 interrupt:
  - gestures don't navigate;
  - plain taps do;
  - the lock lands exactly, holds through ±20 counts of knob noise, and
    releases;
  - recording behaves the same.
