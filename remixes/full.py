# Every module. Each feature is switched in options.txt (tape, octl, fxsl,
# mcap, sldm, cpul, ingn), so one image covers every combination.
REMIX = dict(
    title='Full',
    description='Every module: octave lock, tape / TLA feedback, SRR, warble, Slide jitter, '
                'Turing mode, SD-card updates, options.txt settings, always-on flash prefetch and a troubleshooting CPU log.',
    modules=['record_start_splice', 'shift_gestures', 'tape_sos', 'sd_updater', 'options_keys', 'gene_shape',
             'cpu_meter'],
    sha256='07a934192eec0d67c20eed7ce23a8b642a79c225c5da605a3f684f90ae6c5ac1',
)
