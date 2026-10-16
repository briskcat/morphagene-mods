from mgmod.module import Module

# Stock record start (current-splice mode, markers present) takes the write head
# from the playback splice 0x20021de4 but the record index, which sets the wrap
# bounds, from the current Gene's splice. When they differ (playback stopped,
# another splice selected) overdub writes outside the intended splice. This
# takes the index from 0x20021de4 as well.
MODULE = Module(
    name='record_start_splice',
    title='Overdub stays inside the selected splice',
    status='flashed',
    patches=[
        (0x0802ac60, 'b81f0220', 'e41d0220'),        # literal: 0x20021fb8 -> 0x20021de4
        (0x0802a9b0, '54f82530', '236800bf'),        # ldr.w r3,[r4,r5,lsl#2] -> ldr r3,[r4]; nop
    ],
)
