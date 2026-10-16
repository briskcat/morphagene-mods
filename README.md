# morphagene-mods

New features for the Make Noise Morphagene, added to **your own copy** of the
official firmware (version mg204). It's an unofficial community project, not
affiliated with or supported by Make Noise.

- **SHIFT + knob gestures:** tape-style overdubbing, sound-on-sound feedback,
  sample-rate reduction or tape warble, Varispeed locked to octaves, fifths,
  semitones or your own scale, random Gene
  start positions and a Turing-Machine-style "Turing mode".
- **Your input gain is remembered** between power cycles.
- **Updates from the SD card** in about 2 seconds, with no audio cable (after
  the first install).
- **Every feature can be switched off** in `options.txt`, so one build covers
  every combination.

## No Make Noise firmware here

No Make Noise firmware is included or distributed here: no firmware files,
no images, no update WAVs. You download the official `mg204.wav` from Make
Noise yourself. The builder checks it's the genuine, unmodified file and adds
the mods to it, on your own computer. The mods are new code written for this
project. They patch your copy in place.

**Don't share the files you build**, because they contain Make Noise's firmware.
Share a link to this project instead.

## Quick start

1. **Get the official firmware.** Download `mg204.wav` from the Make Noise
   Morphagene firmware page.
2. **Build.** Open the **[web builder](https://briskcat.github.io/morphagene-mods/)**, choose your `mg204.wav`,
   and download the **update WAV**.
   Everything runs in your browser; nothing is uploaded.
3. **Install it like an official update:** power on while holding REC, then
   play the WAV into Left Signal IN. Step-by-step instructions:
   **[docs/INSTALLING.md](docs/INSTALLING.md)**.
4. **Play.** **[docs/USING.md](docs/USING.md)** shows every gesture and how to
   play it.
5. **Optional: settings.** **[docs/OPTIONS.md](docs/OPTIONS.md)** lists the
   settings in `options.txt`, such as turning a feature off.

Later updates are simpler: copy `mgmod.bin` to the SD card and power on.

**Going back to stock** always works: install Make Noise's own `mg204.wav`
the same way. The mods never touch the bootloader.

## What's included

| Feature | How you use it | Status |
|---|---|---|
| Tape mode / TLA feedback | SHIFT + S.O.S. | tried on hardware |
| Sample-rate reduction or tape warble | SHIFT + Morph | tried on hardware |
| Varispeed lock: octaves, octaves + fifths, semitones or a custom scale | SHIFT + Varispeed | tried on hardware |
| Random Gene start positions (jitter) | SHIFT + Slide | tried on hardware |
| Turing mode | `sldm 1`, then SHIFT + Organize / Gene Size / Slide | tried on hardware |
| Input gain remembered | automatic (REC held + SHIFT taps, as stock) | tried on hardware |
| SD-card updates | `mgmod.bin` on the card | tried on hardware |
| Faster flash access (more CPU headroom) | always on | tried on hardware |
| CPU log for troubleshooting | `cpul 1` | tried on hardware |
| Overdub stays inside the selected splice | automatic (a fix) | built into every image; not tested on its own |

Every feature was also checked instruction by instruction in an emulator
against the stock firmware.

## Known limits

- **CPU at high Morph.** The stock firmware is already at its CPU limit at high
  Morph with short Genes, and stock can glitch there too. The mods add a little.
  Flash prefetch, which is always on, more than makes up for it. If SRR glitches, try warble (`fxsl 2`), which is cheaper.
- **CV on a gesture knob.** CV moving a knob that has a SHIFT gesture can look
  like a turn while SHIFT is held, so a plain SHIFT tap may not move to the next
  splice. This is most likely with Slide.
- **mg204 only.** The builder refuses any other firmware file.

## Building from the command line

Requires Python 3.9+ and the [Arm GNU Toolchain](https://developer.arm.com/downloads/-/arm-gnu-toolchain-downloads)
(14.2 is known to reproduce the recorded builds exactly; binutils 2.47 cannot
link these modules).

```bash
python3 -m mgmod build full --firmware path/to/mg204.wav
```

This writes `build/mg204-full.wav` (the audio update) and `build/mgmod.bin`
(for the SD card). `python3 -m mgmod check --firmware mg204.wav` rebuilds and
compares against the recorded checksum.

## For developers

```
mgmod/            the builder: module loading, collision checks, stock check, outputs
modules/<name>/   each mod: module.py (hooks and claims), Thumb-2 source, technical README
remixes/<name>.py which modules go in a build, in which order, and its expected sha256
web/              the static web builder; remixes.js holds only bytes this project wrote
docs/             user guides, the firmware map, contributing
```

The builder appends each module's code after the stock image, checks the
original bytes at every hook site, and redirects each site with a branch.
Before building, it refuses two modules that claim the same flash site, RAM,
setting, `options.txt` key or gesture ([mgmod/ledger.py](mgmod/ledger.py)).
The web builder's `remixes.js` contains only bytes this project wrote,
never stock bytes.

Technical details for each module are in `modules/<name>/README.md`. The
firmware map is [docs/FIRMWARE_MAP.md](docs/FIRMWARE_MAP.md). For writing a
module, see [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## Credits and licence

- **Licence:** MIT ([LICENSE](LICENSE)). It covers this repository only, not
  the Make Noise firmware.
- **Audio update format:** Émilie Gillet's
  [stm-audio-bootloader](https://github.com/pichenettes/stm-audio-bootloader)
  (MIT), which the Morphagene uses. `mgmod/card.py` and `web/app.js`
  reimplement its encoder.
- **Inspiration:** the structure follows
  [octabam](https://github.com/sambanks/octabam) for the Elektron Octatrack.
- **Trademarks:** Morphagene and Make Noise are trademarks of Make Noise. This
  project is not endorsed by Make Noise.
