from mgmod.module import Module

MODULE = Module(
    name='shift_gestures',
    title='SHIFT + knob gestures; SHIFT + Varispeed exact octave lock',
    status='on hardware',
    source='shift_gestures.S', entry='p1_session',
    hooks=[
        (0x0802486a, 'dff82092', 'p1_session'),      # TIM2: SHIFT session, knob claims
        (0x080251dc, 'b449b54b', 'p3_state14'),      # SHIFT release: no navigation after a gesture
        (0x080255da, '012a7ff48ea9', 'p4_record_tap'),
        (0x0802787c, 'c72840f3d187', 'p5_octave'),   # audio: octave snap while locked
        (0x08027bde, '7c48dfed7c0a', 'p6_glide'),
    ],
    mod_bytes=[(0, 15), (92, 93), (128, 130), (208, 211)],     # +128..+130: Organize snapshot and hold
    options_keys=['octl'],
    gestures=['SHIFT+Varispeed'],
)
