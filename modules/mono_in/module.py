from mgmod.module import Module

# Mono input: with `mono 1` in options.txt, the left input is copied onto the
# right at the top of every audio block, so a mono signal into L is heard and
# recorded on both channels. `mono 2` does it only while R in is quiet: the
# firmware reads no jack-detect line for R in, so the R level stands in for one.
MODULE = Module(
    name='mono_in',
    title='Mono input: L copied onto R, always or while R is quiet (mono)',
    status='on hardware',
    source='mono_in.S', entry='mono_block',
    requires=['options_keys'],
    hooks=[
        (0x08027518, '2de9f04f', 'mono_block'),                # audio block entry: copy L over R in the RX half
    ],
    ram=[(0x2002A608, 0x2002A60F)],                            # auto mode: quiet blocks, crossfade gain
    options_keys=['mono'],
)
