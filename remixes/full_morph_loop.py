# Full, plus Morph fully down playing a seamless loop (a table edit, so it has no
# options.txt switch; use Full for stock Morph).
REMIX = dict(
    title='Full + Morph loop',
    description='Everything in Full, and Morph fully down plays a seamless loop instead of adding silence '
                '(stock reaches the loop at about 8 o\'clock).',
    modules=['record_start_splice', 'shift_gestures', 'tape_sos', 'sd_updater', 'options_keys', 'gene_shape',
             'cpu_meter', 'morph_loop'],
    sha256='315ad604fa7e7629a47606c7da380c83b21be3ab1fae294a793047eed8c10f8e',
)
