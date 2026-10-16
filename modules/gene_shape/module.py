from mgmod.module import Module

MODULE = Module(
    name='gene_shape',
    title='Slide jitter on SHIFT + Slide; sldm 1: Turing mode',
    status='on hardware',
    source='gene_shape.S', entry='g2_size',
    requires=['shift_gestures'],
    hooks=[
        (0x08027808, 'c6684069', 'g2_size'),                   # Gene Size reading (hold, pickup); not
                                                               # 0x0802780a: reel mode branches to 0x0802780c
        (0x080288ee, 'c6684069', 'g3_size'),                   # same, alternate path
        (0x08027972, '32699fed101a', 'gs_slide'),              # Slide reading; jitter amount
        (0x0802838a, 'b0ee48fa', 'ga_birth'),                  # Gene birth, branch A
        (0x08029bb8, 'b0ee602a', 'gb_birth'),                  # Gene birth, branch B
        (0x08028490, '47600024', 'ca_chord'),                  # chord index store, branch A (Turing)
        (0x08029cb4, '4f600599', 'cb_chord'),                  # chord index store, branch B
        (0x080276f0, 'a068b44f', 'o1_organize'),               # Organize reading: held; Turing evolution
    ],
    mod_bytes=[(212, 231)],
    ram=[(0x2002A740, 0x2002A7FF)],                            # Turing state
    options_keys=['sldm', 'root', 'tlen'],
    gestures=['SHIFT+Gene Size', 'SHIFT+Slide', 'SHIFT+Organize'],
)
