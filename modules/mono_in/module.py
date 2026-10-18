from mgmod.module import Module

# Mono input: with `mono 1` in options.txt, the left input is copied onto the
# right at the top of every audio block, so a mono signal into L is heard and
# recorded on both channels. The firmware reads no jack-detect line for R in,
# so it is a setting rather than automatic normalling.
MODULE = Module(
    name='mono_in',
    title='Mono input: L copied onto R (mono)',
    status='emulated',
    source='mono_in.S', entry='mono_block',
    requires=['options_keys'],
    hooks=[
        (0x08027518, '2de9f04f', 'mono_block'),                # audio block entry: copy L over R in the RX half
    ],
    options_keys=['mono'],
)
