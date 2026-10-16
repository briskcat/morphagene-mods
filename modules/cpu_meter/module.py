from mgmod.module import Module

MODULE = Module(
    name='cpu_meter',
    title='Flash prefetch (always on) and a CPU log on the SD card (cpul)',
    status='on hardware',
    source='cpu_meter.S', entry='cpu_block',
    patches=[(0x0802153a, '40f20560', '40f20570')],         # boot: FLASH_ACR 0x605 -> 0x705 (prefetch on)
    hooks=[
        (0x08028666, '0360bb42', 'cpu_block'),                 # end of every audio block: statistics
        (0x08023eec, '024e3668', 'cpu_main'),                  # idle main loop: append to cpulog.txt
    ],
    ram=[(0x20029000, 0x20029FFF)],                            # statistics, ring and FIL
    options_keys=['cpul'],
)
