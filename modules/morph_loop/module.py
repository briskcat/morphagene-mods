from mgmod.module import Module

# Morph's lowest presets (0-2) wait 2x, 1.5x and 1.33x the Gene length before
# the next Gene, so a gap of silence follows each one. Preset 3 (about 8
# o'clock) waits exactly 1x: a seamless loop. This gives presets 0-2 preset 3's
# length fraction and scheduling divisor, so the knob's bottom reaches the loop.
# Tables live in the initialized-data image copied from 0x08047250 to RAM.
MODULE = Module(
    name='morph_loop',
    title='Morph fully down plays a seamless loop (no silence gap)',
    status='untested',
    patches=[
        (0x08047630, '00000040', '0000803f'),        # length fraction, preset 0: 2.0 -> 1.0
        (0x08047634, '0000c03f', '0000803f'),        # preset 1: 1.5 -> 1.0
        (0x08047638, 'a8aaaa3f', '0000803f'),        # preset 2: 1.333333 -> 1.0
        (0x08047744, '02000000', '01000000'),        # scheduling divisor, preset 1: 2 -> 1
        (0x08047748, '03000000', '01000000'),        # preset 2: 3 -> 1
    ],
)
