from mgmod.module import Module

MODULE = Module(
    name='sd_updater',
    title='Firmware updates from mgmod.bin on the SD card',
    status='on hardware',
    source='sd_updater.S', entry='upd_hook', defsyms=[('DIAG', 0)],
    hooks=[(0x08023288, '01460320', 'upd_hook')],              # after the startup card mount
    settings=[0, 1, 2, 3],                                     # "OPTS" magic; also writes the key defaults
    ram=[(0x2002B000, 0x2002B7FF)],                            # FatFs objects and the RAM flasher
)
