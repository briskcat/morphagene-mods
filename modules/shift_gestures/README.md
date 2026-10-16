# shift_gestures

**Status:** on hardware. SHIFT + Varispeed octave lock was confirmed on a
module.

## Gestures

Turning a knob while SHIFT is held is a gesture. Releasing SHIFT afterwards
does **not** move to the next splice, and SHIFT + SPLICE/REC combinations are
blocked for that hold. A plain SHIFT tap still moves to the next splice, and
so does a tap while recording.

This module runs the SHIFT session and the knob detection for every gesture:

| Gesture | Owner | Feature lives in | Enabled by |
|---|---|---|---|
| SHIFT + S.O.S. | 1 | tape_sos | always |
| SHIFT + Varispeed | 2 | this module | `octl 1` |
| SHIFT + Morph | 3 | tape_sos (SRR or warble) | `fxsl 1` or `2` |
| SHIFT + Gene Size | 4 | gene_shape (Turing rate) | `sldm 1` |
| SHIFT + Slide | 5 | gene_shape (jitter / spread) | always |
| SHIFT + Organize | 6 | gene_shape (Turing evolution) | `sldm 1` |

- **Thresholds.** A turn counts after 48 counts of movement (out of 4,095).
  Slide's reading is a 4-sample average, so it needs 96.
- **Order.** Detection runs in this order, and the first knob past its
  threshold owns the gesture.

## Octave lock (SHIFT + Varispeed)

While SHIFT is held, Varispeed snaps to exact rates: −2, −1, −½, −¼, stop, ¼,
½, 1, 2 (entries of the stock bidirectional lookup table). The glide lands
exactly on the rate.

The lock holds after SHIFT is released. Turning Varispeed away by about half an
octave (231 counts) releases it, and the knob is continuous again.

## Hooks

| Hook | Site | Rate | Does |
|---|---|---|---|
| P1 | 0x0802486a | TIM2 | SHIFT session, snapshots, knob claims |
| P3 | 0x080251dc | TIM2 | SHIFT release: no navigation after a gesture |
| P4 | 0x080255da | TIM2 | Same, while recording |
| P5 | 0x0802787c | block | Varispeed snap while locked |
| P6 | 0x08027bde | block | Glide coefficient 1 while locked |

**State:** MOD +0..+15, +92..+93, +208..+211. When the "SHFT" magic is
missing, P1 zeroes MOD +4..+239.

## Verification (emulator)

- All 20 SHIFT state-machine states against a model.
- Octave snap: every knob value.
- Whole-session runs of the real audio routine and TIM2 interrupt:
  - gestures don't navigate;
  - plain taps do;
  - the lock lands exactly, holds through ±20 counts of knob noise, and
    releases;
  - recording behaves the same.
