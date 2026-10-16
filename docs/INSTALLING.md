# Installing, updating and going back to stock

You need:
- the official `mg204.wav` from Make Noise's Morphagene firmware page;
- a way to play a WAV into the module (computer or phone, a cable to
  **Left Signal IN**);
- the Morphagene's SD card.

## 1. Build

Pick one:

- **Web builder (easiest):** open [the web builder](../web/index.html), choose
  your `mg204.wav`, then download the **update WAV** for the first install and
  `mgmod.bin` for later updates.
- **Command line:**

  ```bash
  python3 -m mgmod build full --firmware path/to/mg204.wav
  ```

  This writes `build/mg204-full.wav` (audio update) and `build/mgmod.bin` (SD
  card).

## 2. First install: audio

The SD-card updater is itself a mod, so it has to arrive by audio once. This is
the same procedure as an official update:

1. **Prepare the input.** Remove the SD card. Connect the player to **Left
   Signal IN** at about 80% volume.
2. **Start the bootloader.** Power on while holding **REC**. Only the SPLICE
   window lights (green). Release REC.
3. **Play the update WAV.** The windows flash while it loads. When it
   finishes, all lights flash.
4. **Finish as Make Noise's update instructions say,** including the Varispeed
   calibration (power on holding SPLICE, turn Varispeed fully both ways, press
   SPLICE, power-cycle).

## 3. Later updates: SD card

1. **Copy the file.** Put `mgmod.bin` at the root of the card, with exactly
   that name.
2. **Update.** Put the card in the module and power on. No button is needed.
   The update takes a few seconds, then the module restarts.
3. **Check it worked.** On the card, `mgmod.bin` is now `mgmod.ok`.

The updater checks the file's footer (`MGMD`, size, CRC32), the vector table,
and a hard limit that never erases anything below the application (the
bootloader and calibration are never touched). A file that fails a check is
ignored and the module boots normally.

## Going back to stock

The bootloader is below the application, and no mod or update writes it. If a
build misbehaves or doesn't start, use the audio procedure above with the
**official `mg204.wav`**. This always returns the module to stock firmware.

## Troubleshooting

- **The WAV doesn't load (lights don't flash, or it stops part-way).** Turn
  the volume up or down a little and try again. Turn off any sound effects,
  equalisers or "enhancements" on the player, and keep it from going to sleep.
- **The SD update didn't happen (`mgmod.bin` didn't change to `mgmod.ok`).**
  The SD updater arrives with the first audio install, so do that first. Check
  the file is at the root of the card and named exactly `mgmod.bin`.
- **Something behaves strangely after an update.** Install the official
  `mg204.wav` by audio to get back to stock, then try the build again.
