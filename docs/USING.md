# Using the mods

All the new features live on **SHIFT**: hold SHIFT and turn a knob. When you
let go of SHIFT after a turn, the module **doesn't** jump to the next splice,
and SHIFT + SPLICE / REC deletes are blocked for that hold, so a gesture can't
delete audio. A plain SHIFT tap still moves to the next splice, as stock.

After a gesture, the knob you turned **holds its old value** until you turn it
back near where it was (pickup). That way the sound doesn't jump when you let go of SHIFT.

| Gesture | What it does | Setting |
|---|---|---|
| SHIFT + S.O.S. | Tape mode or classic TLA feedback | `tape` |
| SHIFT + Morph | Sample-rate reduction or tape warble | `fxsl` |
| SHIFT + Varispeed | Lock to octaves, fifths, semitones or your own scale | `octl`, `scal` |
| SHIFT + Slide | Random Gene start positions (jitter) | always on |
| SHIFT + Organize / Gene Size / Slide | Turing mode controls | `sldm 1` |
| REC held + SHIFT taps | Input gain (stock), now remembered | `ingn` |
| (no gesture) | Mono input: L on both channels | `mono 1` |

Settings are in `options.txt`; see [OPTIONS.md](OPTIONS.md).

## SHIFT + S.O.S.: tape mode (default)

The first SHIFT + S.O.S. turn after power-up switches tape mode on. Until then,
S.O.S. works exactly as stock.

While you overdub an existing splice:
- **A virtual tape head** writes into the Slide / Gene Size window. It moves at
  the Varispeed rate, so it plays backwards in reverse and pauses at zero speed.
- **SHIFT + S.O.S. sets how much of the old recording stays** with each pass
  (like tape feedback). At 100% with silent input, nothing changes.
- **Plain S.O.S.** still sets what you hear.
- **Morph is capped at 0.3 while dubbing** to stay within the CPU budget. Change it with `mcap`.

## SHIFT + S.O.S.: classic TLA feedback (`tape 0`)

The recorded signal becomes your input **plus** the Gene playback, and
SHIFT + S.O.S. sets how much playback is fed back. Use this for
sound-on-sound with TLA, without tape mode's moving head.

## SHIFT + Morph: SRR or warble

- **SRR (`fxsl 1`, default):** sample-rate reduction on the Gene playback.
  Turn right for more; fully left is off.
- **Warble (`fxsl 2`):** tape wow and flutter on the Gene playback speed,
  up to about 1.4 semitones. It's cheaper on CPU than SRR.
- **`fxsl 0`:** off. Morph stays stock.

The input itself isn't affected, so with feedback or TLA the effect builds
up pass by pass. The amount resets at power-up.

## SHIFT + Varispeed: scale lock

While SHIFT is held, Varispeed snaps to the nearest step of a scale, so you
can transpose the reel without a CV quantizer. Choose the scale with `octl`:

| `octl` | Steps |
|---|---|
| 1 (default) | Octaves: −2, −1, −½, −¼, stop, ¼, ½, 1, 2 |
| 2 | Octaves + fifths |
| 3 | Every semitone |
| 4 | Your own scale, listed in `scal` |
| 0 | Off |

For `octl 4`, list the semitones above the root that you want, e.g.
`scal 3,5,7,10` (minor pentatonic) or `scal 2,4,5,7,9,11` (major). The root
and its octaves are always included.

Every scale is relative to normal speed (1×), works forward and in reverse,
and goes from about ⅛× up to 2×. Stop is always a step. The steps are in tune
(equal temperament).

The lock stays after you let go of SHIFT. To release it, turn Varispeed about
half an octave away. In semitone mode the steps are close together on the
knob, so turn slowly; if you mostly want to get back to normal speed, the
default `octl 1` is easiest.

## SHIFT + Slide: jitter

Each new Gene starts at a random offset around the Slide position. Fully left
is off; turn right for a wider spread across the splice.

## Turing mode (`sldm 1`)

A repeating loop of random choices, like a Turing Machine. Each step decides a
Gene's pitch (chord ratio), stereo and position scatter, so the randomness
repeats as a pattern.

1. **Set up:** set `sldm 1` in `options.txt` and power on. Gene Size at about
   1 o'clock (short Genes). Morph low for a melody (one Gene at a time),
   higher for chords.
2. **Lock the loop:** hold SHIFT and turn Organize fully left. The pattern now
   repeats.
3. **Let it mutate:** SHIFT + Organize up from the left. Steps sometimes get a
   new random choice. Fully right is normal randomness (stock).
4. **New pattern:** SHIFT + Organize fully right, then back to fully left.

| Control | In Turing mode |
|---|---|
| SHIFT + Organize | Evolution: fully left = locked, fully right = stock randomness |
| SHIFT + Gene Size | Genes per step: 1, 2, 3, 4, 6, 8, 12 or 16 |
| SHIFT + Slide | Spread: start jitter, repeated by each step when locked |
| `tlen` | Loop length, 1–16 steps (default 8) |
| `root` | Chance in % that a step plays the root pitch (default 50; `root 100` = no pitch changes) |

Pitches come from the stock chord ratios `mcr1`–`mcr3` in `options.txt`.
Organize doesn't move the selected splice while SHIFT is held. There's no LED
feedback for Turing mode.

## Input gain: remembered automatically

Set the input gain as on a stock Morphagene: hold **REC** and tap **SHIFT**.
Each tap steps through the four levels. The mod saves your choice to
`options.txt` about 3 seconds after your last tap, and restores it at
power-up. It never saves while recording; it waits until you stop.

You can also set it directly with `ingn` in `options.txt` (0–3; 0 is the
stock starting level).

## Mono input (`mono 1`)

With `mono 1`, the left input is copied onto the right. A mono source patched
into L is heard on both outputs and recorded on both channels, as on Beads,
Clouds or Mimeophon. R in is ignored while it's on. The Morphagene can't
detect whether R is patched, so this is a setting rather than automatic.
Set `mono 0` (the default) for stereo.

## Working in the background

These need nothing from you:

- **SD-card updates.** Later updates install from `mgmod.bin` on the card in a
  few seconds, with no audio cable ([INSTALLING.md](INSTALLING.md#3-later-updates-sd-card)).
- **Overdub stays in its splice.** A fix: with playback stopped and another
  splice selected, stock could start an overdub outside the selected splice.
  Now it stays inside it.
- **Faster flash access.** The firmware runs with the processor's flash
  prefetch on, which gives the CPU 10–17% more headroom per audio block, so
  high-Morph patches glitch less.
- **CPU log (troubleshooting only).** Off by default; see
  [OPTIONS.md](OPTIONS.md#troubleshooting-the-cpu-log-cpul).

## If something seems off

- **A SHIFT tap doesn't change splice:** a knob (or CV on it) moved while SHIFT
  was held, so it counted as a gesture. Tap again without touching the knobs.
- **Glitches at high Morph:** see the CPU note in the [README](../README.md#known-limits).
- **Go back to stock any time:** see [INSTALLING.md](INSTALLING.md#going-back-to-stock).
