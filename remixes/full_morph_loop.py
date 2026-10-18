# Full, plus Morph fully down playing a seamless loop (a table edit, so it has no
# options.txt switch; use Full for stock Morph).
REMIX = dict(
    title='Full + Morph loop',
    description='Everything in Full, and Morph fully down plays a seamless loop instead of adding silence '
                '(stock reaches the loop at about 8 o\'clock).',
    modules=['record_start_splice', 'shift_gestures', 'tape_sos', 'sd_updater', 'options_keys', 'gene_shape',
             'cpu_meter', 'mono_in', 'morph_loop'],
    sha256='2712e0089b174e8607e357097dc7979969adc1f2e2c92d2ea4dec6ca50b9fdca',
)
