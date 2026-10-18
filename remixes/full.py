# Every module. Each feature is switched in options.txt (tape, octl, scal, fxsl,
# mcap, sldm, cpul, ingn, mono), so one image covers every combination.
REMIX = dict(
    title='Full',
    description='Every module: Varispeed scale lock, tape / TLA feedback, SRR, warble, Slide jitter, '
                'Turing mode, mono input, SD-card updates, options.txt settings, always-on flash prefetch and a troubleshooting CPU log.',
    modules=['record_start_splice', 'shift_gestures', 'tape_sos', 'sd_updater', 'options_keys', 'gene_shape',
             'cpu_meter', 'mono_in'],
    sha256='42b587eabeaf6fe83fe27d4bdbffb7b98f17bfa0b61f4c3a248e619249291388',
)
