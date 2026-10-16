# Every module. Each feature is switched in options.txt (tape, octl, fxsl,
# mcap, sldm, pfch, cpul, ingn), so one image covers every combination.
REMIX = dict(
    title='Full',
    description='Every module: octave lock, tape / TLA feedback, SRR, warble, Slide jitter, '
                'Turing mode, SD-card updates, options.txt settings, flash prefetch and the CPU log.',
    modules=['record_start_splice', 'shift_gestures', 'tape_sos', 'sd_updater', 'options_keys', 'gene_shape',
             'cpu_meter'],
    sha256='f8c3593066c9e9ea942aae9d220282610f29e4a4287180f267aae0b677ccf89f',
)
