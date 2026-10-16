# Every module. Each feature is switched in options.txt (tape, octl, scal, fxsl,
# mcap, sldm, cpul, ingn), so one image covers every combination.
REMIX = dict(
    title='Full',
    description='Every module: Varispeed scale lock, tape / TLA feedback, SRR, warble, Slide jitter, '
                'Turing mode, SD-card updates, options.txt settings, always-on flash prefetch and a troubleshooting CPU log.',
    modules=['record_start_splice', 'shift_gestures', 'tape_sos', 'sd_updater', 'options_keys', 'gene_shape',
             'cpu_meter'],
    sha256='d45ee25706732ff436531e97b5c2fc11b62f1397fb3e65ac4d3822f988e2655b',
)
