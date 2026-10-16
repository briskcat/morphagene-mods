# sd_updater

**Status:** on hardware. It updated the module from the card repeatedly
(`mgmod.ok` appears).

## How to use

Put `mgmod.bin` at the root of the card and power on. No button is needed. If
the file is valid, the module flashes itself in a few seconds and restarts.
The file becomes `mgmod.ok`. Install this module by audio once; after that,
updates come from the card.

## How it works

It hooks the stock startup right after the first successful card mount
(0x08023288). Steps:

1. **Look for the file.** If there is no `mgmod.bin`, the stock boot carries
   on.
2. **Validate it:**
   - the size is a multiple of 4, at most 256 KiB;
   - the footer (`MGMD`, length, CRC32) matches;
   - the first word is the stack pointer 0x20030000;
   - the reset vector lies inside the application.
3. **Stage it.** Read the image into SDRAM (0xD0000000) and check the CRC
   again from there.
4. **Rename** `mgmod.bin` to `mgmod.ok` *before* flashing, so a bad image
   cannot reflash in a loop.
5. **Flash it from SRAM** with interrupts off:
   - erase **only** sectors 5 and 6, with a hard refusal of any address below
     0x08020000;
   - program;
   - read back;
   - reset.

**Never touched:** the bootloader and calibration. A failed write leaves the
bootloader working. Recover with the official `mg204.wav` by audio.

**Boot settings.** Every boot it also sets the `options.txt` setting defaults
(SETTINGS magic, `tape 1`, `octl 1`, `scal` empty, `fxsl 1`, `cpul 0`, `mcap 3`,
`sldm 0`, `root 50`, `tlen 8`, `ingn 0`) before the stock parser runs, and clears the
warble and Turing state.

## Verification (emulator)

16 cases, with FatFs and the flash peripheral emulated:

- **No file:** boot continues.
- **A good update:** only sectors 5 and 6 are written and verified, the file
  is retired, and the module resets.
- **Rejected files, nothing erased:** bad CRC, bad magic, wrong length field,
  size not a multiple of 4, oversize, truncated, wrong initial stack pointer,
  even reset vector, reset vector outside the application.
- **Rename fails:** nothing is erased.
- **Power loss mid-programming:** the bootloader and calibration stay intact.
- **A deliberately broken flasher aimed at sector 4** stops at its guard.
