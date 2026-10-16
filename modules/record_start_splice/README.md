# record_start_splice

**Status:** flashed. It's in every build that has run on a module, but it
hasn't been tested on its own.

**What it fixes.** In current-splice record mode, with markers present, stock
record start takes:
- the **write head** from the playback splice (0x20021de4);
- the **record index**, which sets the wrap bounds, from the current Gene's
  splice.

When those differ (for example, playback stopped and another splice
selected), an overdub can write outside the splice you meant. This module takes
the index from the playback splice as well.

**Change:** two byte edits, no code.

| Address | Stock | New |
|---|---|---|
| 0x0802ac60 | literal 0x20021fb8 | literal 0x20021de4 |
| 0x0802a9b0 | `ldr.w r3,[r4,r5,lsl #2]` | `ldr r3,[r4]`; `nop` |

**Verification:**
- Only one instruction (0x0802a9a8) loads the changed literal; a scan of every
  PC-relative load in the image confirmed it.
- r5 is kept for the full-splice Slide path at 0x0802adc4.
- The record-start path was run in the emulator with the playback splice and
  the Gene's splice different.

**Try it.** Stop playback, select another splice, then overdub (with record
mode set to the current splice). The recording should stay inside that
splice.
