# Writing a module

A module is a folder `modules/<name>/` with:

- **`module.py`:** a `MODULE = Module(...)` manifest. It lists hooks,
  requirements and every resource the module claims.
- **The Thumb-2 source:** GNU `as` syntax, linked by the builder after the
  previous module.
- **`README.md`:** what it does, how to play it, its options, hardware status,
  and how it was verified.

## The manifest

```python
from mgmod.module import Module

MODULE = Module(
    name='my_mod', title='One line for the tables', status='emulated',
    source='my_mod.S', entry='my_first_hook',
    requires=['shift_gestures'],                 # must come earlier in the remix
    hooks=[(0x08027b94, '8a4e3468', 'my_hook')], # address, original bytes, symbol
    mod_bytes=[(240, 247)],                      # MOD block offsets you use
    ram=[], settings=[], options_keys=[], gestures=[],
)
```

How the builder applies it:
1. **Assemble** the source and link it at the current image end.
2. **Check** every hook site against its original bytes.
3. **Redirect** each site with a B.W to your symbol. Longer sites are padded
   with NOPs. Your code re-runs the instructions it replaced and branches back.

Byte-only fixes use `patches=[(address, original, new)]` with no source.

**The ledger** ([mgmod/ledger.py](../mgmod/ledger.py)) refuses a remix in which
two modules claim:
- the same flash bytes;
- the same MOD offsets, RAM range or SETTINGS byte;
- the same `options.txt` key or gesture.

Claim everything you touch. [FIRMWARE_MAP.md](FIRMWARE_MAP.md) lists what is
taken.

## Rules

- **Never commit Make Noise code or anything derived from it in bulk:** no
  images, WAVs, disassembly listings or decompiler exports. Hook sites may
  record the few original bytes they check.
- **Keep the module safe to idle.** With its feature off, the module should
  behave exactly like stock, and its per-sample cost should be one byte check
  at most.
- **Be honest about status:**
  - `emulated`: checked in an emulator only;
  - `flashed`: runs on a module, behaviour not tested on its own;
  - `on hardware`: the behaviour was tried on a module.
- **Measure CPU** for anything per sample, at high Morph with short Genes
  (see FIRMWARE_MAP.md).

## Before a pull request

```bash
python3 -m mgmod list
python3 -m mgmod check --firmware path/to/mg204.wav      # every remix reproduces
python3 -m mgmod webpatch --firmware path/to/mg204.wav   # refresh web/remixes.js
```

1. **Record the hash.** If you changed a remix, update its `sha256` to the
   value `check` prints.
2. **Include `web/remixes.js`.** It contains only bytes this project wrote:
   runs that differ from stock, plus the appended code.

## Verification

The modules here were developed with an emulator harness:
- each hook is run alone against a float32/integer model;
- the stock and modified audio paths are compared sample by sample;
- whole sessions run the original audio routine and TIM2 interrupt.

That harness needs a disassembly and decompiler exports of your own firmware
copy, so it isn't part of this repository yet. Porting it so it runs from the
user's `mg204.wav` is planned.

Until then, describe in your README:
- what you checked;
- how you checked it;
- what is still only an assumption.
