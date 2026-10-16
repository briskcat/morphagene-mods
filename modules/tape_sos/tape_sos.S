@ Module tape_sos: tape-style overdub, classic TLA feedback, SRR and warble (mg204).
@ options.txt "tape 1" (default) = tape mode; "tape 0" = classic TLA
@ feedback (record = clamp(input + f * playback)). See options_keys.S.
@ Requires shift_gestures (shift_gestures.S).
@
@ Tape mode turns on with the first SHIFT + S.O.S. edit after power-up
@ (state +16), and SHIFT + S.O.S. then sets retention (state +20, stock S.O.S.
@ knob law). While overdubbing an existing splice in tape mode:
@   - the record signal is the raw input (no S.O.S. mix, no splice filter);
@   - a fractional head moves at the glided Varispeed rate (0x200220e0) inside
@     the Slide / Gene Size window of the record splice, following the knobs
@     live (the head keeps its offset when the window moves);
@   - at every integer tape position it crosses, the input is linearly
@     interpolated and stored as  stored * retention + input  (int16, clamped);
@     retention 1.0 with silent input writes nothing (bit-exact retention).
@ Gene playback, monitor (S.O.S. mix), new-recording capture and the stock
@ stop logic are unchanged. Zero speed pauses writing; reverse works.
@
@ State (MOD + offset): +16 tape on, +17 pickup, +18 mon_ref, +20 retention f,
@ +24 prevL f, +28 prevR f, +32 pos i32, +36 frac f, +40 valid u8,
@ +44 window start i32, +48 window length i32, +56..+83 per-block cache,
@ +84 RAM copy flag, +88 buffered frame count, +0x90..+0xCF frame buffer.
@ SRR (SHIFT + Morph): +92 ref_morph u16, +94 Morph pickup u8, +95 SRR active u8,
@ +96 pre-edit Morph u16, +100 target f, +104 amount f, +108 step f, +112 mix f,
@ +116 phase f, +120/+124 held L/R f.
@ The engine runs from SRAM at MOD + 0x100 (0x2002A100).
@ Batched: the per-sample hook only buffers the input frame; P7 writes the
@ previous block's frames to tape in one pass (one block = 167 us of latency).
@ Speed, Slide, Gene Size and retention are sampled once per 8-sample block.

    .syntax unified
    .cpu cortex-m4
    .fpu fpv4-sp-d16
    .thumb

    .equ MOD,        0x2002A000
    .equ MAGIC,      0x53484654
    .equ T_PICKUP,   48
    .equ T_FX_ZERO,  96                @ SHIFT + Morph counts treated as off
    .equ LED_RETURN, 0x08024afe
    .equ P7_RETURN,  0x080276ca
    .equ A_AFTER_FILTER, 0x08028ef4
    .equ A_STOCK,    0x08028e94
    .equ B_AFTER_FILTER, 0x0802a1c2
    .equ B_STOCK,    0x0802a162
    .equ WA_STOCK,   0x080291dc
    .equ WA_DONE,    0x08029234
    .equ WB_STOCK,   0x0802a4c0
    .equ WB_DONE,    0x0802a518
    .equ HEAD,       0x2002210c
    .equ CAPACITY,   0x20021ca4
    .equ REC_ACTIVE, 0x20022108
    .equ REC_INDEX,  0x20022114
    .equ MARKER_COUNT, 0x2002208c
    .equ MARKERS,    0x2002215c
    .equ BUSY,       0x200213b4
    .equ LEFT_PTR,   0x200220fc
    .equ RIGHT_PTR,  0x20022100
    .equ RATE,       0x200220e0
    .equ SLIDE,      0x20022154
    .equ GENE_LENGTH, 0x20021f90
    .equ RAMCODE,    0x2002A100        @ engine copy (MOD + 0x100)
    .equ RAMFLAG,    84                @ MOD + 84: RAM_MAGIC once copied
    .equ RAM_MAGIC,  0x54415045        @ "TAPE"
    .equ COUNT,      88                @ MOD + 88: buffered frames this block
    .equ P10_RETURN, 0x0802798c
    .equ A_SKIP,     0x08028ea0         @ after the inop selection (feedback path)
    .equ B_SKIP,     0x0802a16e
    .equ SETTINGS,   0x2002A0F0         @ options.txt settings (options_keys)
    .equ SETTINGS_MAGIC, 0x5354504f
    .equ BUFFER,     0x90              @ MOD + 0x90: 8 frames x (L, R) floats
    .equ BUFFER_FRAMES, 8
    .equ TARGET,     0x200220e8         @ Varispeed target rate (stock, per block)
    .equ WARBLE,     0x2002A700         @ warble state (MOD + 0x700)
    .equ WARBLE_MAGIC, 0x4c425257       @ "WRBL"

    .text
    .global p7_sos_block, p11_mix_a, p12_mix_b, wa_tape, wb_tape, engine, engine_end, eng_prepare, eng_flush, p10_morph_cap, led_rate

@ P7: shared S.O.S. block hook; also forget the tape head between takes.
    .macro P7_EXTRA
    ldrb    r0, [r3, #COUNT]            @ flush last block's buffered frames
    cbz     r0, 76f
    ldr     r0, [r3, #RAMFLAG]
    ldr     r1, =RAM_MAGIC
    cmp     r0, r1
    bne     76f
    ldr     r1, k_flush_ram
    push    {r3, lr}
    blx     r1
    pop     {r3, lr}
76: movs    r0, #0
    strb    r0, [r3, #COUNT]
    strb    r0, [r3, #56]               @ engine recomputes its block cache
    ldr     r0, =REC_ACTIVE
    ldr     r0, [r0]
    cbnz    r0, 77f
    strb    r0, [r3, #40]               @ not recording: forget the head
77: ldr     r0, [r3]                    @ copy the engine to RAM once MOD is live
    ldr     r1, =MAGIC
    cmp     r0, r1
    bne     79f
    ldr     r0, [r3, #RAMFLAG]
    ldr     r1, =RAM_MAGIC
    cmp     r0, r1
    beq     79f
    ldr     r0, =engine
    bic     r0, r0, #1
    ldr     r1, =engine_end
    ldr     r2, =RAMCODE
78: ldr     r3, [r0], #4
    str     r3, [r2], #4
    cmp     r0, r1
    blo     78b
    dsb
    isb
    ldr     r3, =MOD
    ldr     r1, =RAM_MAGIC
    str     r1, [r3, #RAMFLAG]
79:
    .endm
    .include "sos_block.inc"
    .align 2                            @ P7's constants stay within vldr range
k_scale:    .word 0x398a26fe            @ 0.00026350463 (stock S.O.S. scale)
k_top:      .word 0x3f864064            @ 1.04884
k_offset:   .float 0.04884
k_flush_ram:   .word RAMCODE + eng_flush - engine + 1      @ RAM entry points
k_prepare_ram: .word RAMCODE + eng_prepare - engine + 1
    .ltorg

@ Per-sample tape check: one byte, r1 preserved. P8/P9's tape path only swaps
@ the record signal to raw input and skips the splice filter, so a stale byte
@ before the state block is initialised is harmless (no take is running).
    .macro TAPE_ON
    push    {r1}
    ldr     r1, =MOD
    ldrb    r1, [r1, #16]
    cmp     r1, #1
    pop     {r1}                        @ pop does not change flags
    bne     8f
    .endm

@ Z set (eq) when options.txt selects tape mode ("tape 1", the default);
@ Z clear for "tape 0" (classic TLA feedback). Uses and restores r1, r2.
    .macro TAPE_SETTING
    push    {r1, r2}
    ldr     r1, =SETTINGS
    ldr     r2, [r1]
    ldr     r1, =SETTINGS_MAGIC
    cmp     r2, r1
    bne     71f                         @ no settings: default tape (Z set below)
    ldr     r1, =SETTINGS
    ldrb    r2, [r1, #4]
    cmp     r2, #1
    b       72f
71: cmp     r1, r1
72: pop     {r1, r2}                    @ pop does not change flags
    .endm

    .macro CLAMP a, b
    vmov.f32 s0, #1.0
    vcmpe.f32 \a, s0
    vmrs    APSR_nzcv, fpscr
    it      gt
    vmovgt.f32 \a, s0
    vcmpe.f32 \b, s0
    vmrs    APSR_nzcv, fpscr
    it      gt
    vmovgt.f32 \b, s0
    vneg.f32 s0, s0
    vcmpe.f32 \a, s0
    vmrs    APSR_nzcv, fpscr
    it      lt
    vmovlt.f32 \a, s0
    vcmpe.f32 \b, s0
    vmrs    APSR_nzcv, fpscr
    it      lt
    vmovlt.f32 \b, s0
    .endm

    .macro SRR_APPLY left, right, ta, tb
    vldr    \ta, [r1, #116]             @ phase += step
    vldr    \tb, [r1, #108]
    vadd.f32 \ta, \ta, \tb
    vmov.f32 \tb, #1.0
    vcmpe.f32 \ta, \tb
    vmrs    APSR_nzcv, fpscr
    blt     81f
    vsub.f32 \ta, \ta, \tb             @ new hold
    vstr    \left, [r1, #120]
    vstr    \right, [r1, #124]
81: vstr    \ta, [r1, #116]
    vldr    \ta, [r1, #112]             @ wet mix
    vldr    \tb, [r1, #120]
    vsub.f32 \tb, \tb, \left
    vfma.f32 \left, \tb, \ta
    vldr    \tb, [r1, #124]
    vsub.f32 \tb, \tb, \right
    vfma.f32 \right, \tb, \ta
    .endm

@ Merged per-sample hooks (one per reconstruction branch), at the S.O.S. mix:
@ SRR on the Gene playback, then the stock monitor/record mix, then the tape or
@ feedback record path. MOD+232 (set once per block by P10) is non-zero when
@ SRR is active or tape/feedback mode is on, MOD+233 when tape/feedback is on.
@ When +232 is zero the stock instructions run inline (one byte checked per
@ sample); with SRR alone the tape checks are skipped too.
@ Branch A (0x08028e7a): playback s16/s19, input s4/s3, mix s2, r0 = Input Only.
    .thumb_func
p11_mix_a:
    push    {r1}
    ldr     r1, =MOD
    ldrb    r1, [r1, #232]
    cbnz    r1, 1f
    pop     {r1}
    vsub.f32 s8, s16, s4                @ stock 0x08028e7a..0x08028e9c
    vsub.f32 s7, s19, s3
    vmov.f32 s13, s4
    vmov.f32 s14, s3
    vfma.f32 s14, s2, s7
    cmp     r0, #0
    vfma.f32 s13, s8, s2
    itt     eq
    vmoveq.f32 s3, s14
    vmoveq.f32 s4, s13
    b.w     A_SKIP
1:  ldr     r1, =MOD
    ldrb    r1, [r1, #95]
    cbz     r1, 2f
    ldr     r1, =MOD
    SRR_APPLY s16, s19, s8, s7          @ s8/s7 are written just below
2:  ldr     r1, =MOD
    ldrb    r1, [r1, #233]              @ tape / feedback mode on?
    cbnz    r1, 3f
    pop     {r1}                        @ SRR only: stock mix inline
    vsub.f32 s8, s16, s4
    vsub.f32 s7, s19, s3
    vmov.f32 s13, s4
    vmov.f32 s14, s3
    vfma.f32 s14, s2, s7
    cmp     r0, #0
    vfma.f32 s13, s8, s2
    itt     eq
    vmoveq.f32 s3, s14
    vmoveq.f32 s4, s13
    b.w     A_SKIP
3:  pop     {r1}
    vsub.f32 s8, s16, s4
    vsub.f32 s7, s19, s3
    vmov.f32 s13, s4
    vmov.f32 s14, s3
    vfma.f32 s14, s2, s7
    vfma.f32 s13, s8, s2                @ monitor mix L
    TAPE_ON
    TAPE_SETTING
    bne     7f
    vstr    s21, [r7]                   @ tape: record raw input, skip the splice filter
    vmov.f32 s30, s14
    b.w     A_AFTER_FILTER
7:  cmp     r0, #0                      @ feedback: Input Only stays stock
    bne     8f
    push    {r1}
    vpush   {s0}
    ldr     r1, =MOD
    vldr    s0, [r1, #20]
    vfma.f32 s4, s16, s0               @ record = input + f * playback
    vfma.f32 s3, s19, s0
    CLAMP   s4, s3
    vpop    {s0}
    pop     {r1}
    b.w     A_SKIP
8:  cmp     r0, #0
    b.w     A_STOCK
    .ltorg

@ Branch B (0x0802a148): playback s27/s24, input s7/s6, mix s19, r4 = Input Only.
    .thumb_func
p12_mix_b:
    push    {r1}
    ldr     r1, =MOD
    ldrb    r1, [r1, #232]
    cbnz    r1, 1f
    pop     {r1}
    vsub.f32 s1, s27, s7                @ stock 0x0802a148..0x0802a16a
    vsub.f32 s17, s24, s6
    vmov.f32 s30, s7
    vmov.f32 s14, s6
    vfma.f32 s14, s19, s17
    cmp     r4, #0
    vfma.f32 s30, s1, s19
    itt     eq
    vmoveq.f32 s6, s14
    vmoveq.f32 s7, s30
    b.w     B_SKIP
1:  ldr     r1, =MOD
    ldrb    r1, [r1, #95]
    cbz     r1, 2f
    ldr     r1, =MOD
    SRR_APPLY s27, s24, s1, s17         @ s1/s17 are written just below
2:  ldr     r1, =MOD
    ldrb    r1, [r1, #233]              @ tape / feedback mode on?
    cbnz    r1, 3f
    pop     {r1}                        @ SRR only: stock mix inline
    vsub.f32 s1, s27, s7
    vsub.f32 s17, s24, s6
    vmov.f32 s30, s7
    vmov.f32 s14, s6
    vfma.f32 s14, s19, s17
    cmp     r4, #0
    vfma.f32 s30, s1, s19
    itt     eq
    vmoveq.f32 s6, s14
    vmoveq.f32 s7, s30
    b.w     B_SKIP
3:  pop     {r1}
    vsub.f32 s1, s27, s7
    vsub.f32 s17, s24, s6
    vmov.f32 s30, s7
    vmov.f32 s14, s6
    vfma.f32 s14, s19, s17
    vfma.f32 s30, s1, s19               @ monitor mix L
    TAPE_ON
    TAPE_SETTING
    bne     7f
    vstr    s25, [r0]                   @ tape: record raw input, skip the splice filter
    vmov.f32 s22, s14
    b.w     B_AFTER_FILTER
7:  cmp     r4, #0                      @ feedback: Input Only stays stock
    bne     8f
    push    {r1}
    vpush   {s0}
    ldr     r1, =MOD
    vldr    s0, [r1, #20]
    vfma.f32 s7, s27, s0               @ record = input + f * playback
    vfma.f32 s6, s24, s0
    CLAMP   s7, s6
    vpop    {s0}
    pop     {r1}
    b.w     B_SKIP
8:  cmp     r4, #0
    b.w     B_STOCK
    .ltorg

@ WA / WB: write-block entries (recording active). The tape engine runs from
@ SRAM (copied by P7_EXTRA). It returns r0 = 1 when it handled the sample;
@ then the stock stop logic runs, otherwise the stock write does.
    .macro WRITE_HOOK lreg, rreg, stock, done
    push    {r1-r3}
    ldr     r2, =MOD
    ldrb    r3, [r2, #56]
    cmp     r3, #1
    bne     3f
5:  ldrb    r3, [r2, #COUNT]            @ tape: buffer the frame, write at block end
    cmp     r3, #BUFFER_FRAMES
    bhs     6f
    add     r1, r2, r3, lsl #3
    vstr    \lreg, [r1, #BUFFER]
    vstr    \rreg, [r1, #(BUFFER + 4)]
    adds    r3, r3, #1
    strb    r3, [r2, #COUNT]
6:  pop     {r1-r3}
    b.w     \done
3:  cmp     r3, #2
    beq     8f
    ldr     r3, [r2, #RAMFLAG]          @ first sample of the block: decide
    ldr     r1, =RAM_MAGIC
    cmp     r3, r1
    bne     8f                          @ engine not in RAM yet: stock write
    push    {r0, lr}
    vmov    r0, \lreg
    vmov    r1, \rreg
    ldr     r3, k_prepare_ram
    blx     r3
    pop     {r0, lr}
    ldr     r2, =MOD
    ldrb    r3, [r2, #56]
    cmp     r3, #1
    beq     5b
8:  pop     {r1-r3}
    ldr     r4, =HEAD                   @ replaced instructions
    ldr     r5, =CAPACITY
    b.w     \stock
    .endm

@ P10 (0x08027984, once per block): Morph cap while tape-dubbing. Stock high
@ Morph TLA is already at the CPU limit (slightly glitchy on the module), and
@ tape writing must read each stored sample to apply retention, so while tape
@ mode is on and a take is recording, Morph is limited to options.txt mcap/10
@ (default 0.3; mcap 0 = no cap). The cap
@ applies to the block's Morph value (s31), which drives the overlap preset,
@ scheduling, chord-ratio selection and the smoothed Morph. Flags are not
@ needed afterwards (0x08027a44 recomputes them).
    .thumb_func
p10_morph_cap:
    vmov    s31, r7                     @ replaced: Morph reading -> 0..1
    vcvt.f32.s32 s31, s31, #12
    push    {r0-r3}
    vpush   {s0-s2}
    ldr     r3, =MOD
    ldr     r0, [r3]
    ldr     r1, =MAGIC
    cmp     r0, r1
    beq     10f
    movs    r0, #0                      @ state block not live: SRR off, so the
    strb    r0, [r3, #95]               @ per-sample hooks can trust one byte
    b       90f
10: @ --- SHIFT + Morph: SRR amount; Morph holds its pre-edit value (pickup).
    ldrb    r0, [r3, #6]
    cmp     r0, #3
    bne     15f
    ldrb    r0, [r3, #5]
    cbz     r0, 15f
    ldrb    r0, [r3, #4]
    cbz     r0, 15f
    subs    r0, r7, #T_FX_ZERO          @ SRR/warble target = knob position, with
    it      lt                          @ the bottom T_FX_ZERO counts as off (the
    movlt   r0, #0                      @ knob's lowest reading is ~56, not 0)
    vmov    s0, r0
    vcvt.f32.s32 s0, s0
    vldr    s2, k_fx_span
    vmul.f32 s0, s0, s2
    vmov.f32 s2, #1.0
    vcmpe.f32 s0, s2
    vmrs    APSR_nzcv, fpscr
    it      gt
    vmovgt.f32 s0, s2
    vstr    s0, [r3, #100]
    ldrb    r0, [r3, #94]
    cbnz    r0, 12f
    ldrh    r0, [r3, #92]               @ pre-edit Morph reading (session snapshot)
    strh    r0, [r3, #96]
    movs    r0, #1
    strb    r0, [r3, #94]
12: ldrh    r0, [r3, #96]
    vmov    s31, r0
    vcvt.f32.s32 s31, s31, #12
    b       20f
15: ldrb    r0, [r3, #94]               @ pickup pending?
    cbz     r0, 20f
    ldrh    r0, [r3, #96]
    subs    r1, r7, r0
    it      mi
    rsbmi   r1, r1, #0
    cmp     r1, #T_PICKUP
    ble     16f
    vmov    s31, r0
    vcvt.f32.s32 s31, s31, #12
    b       20f
16: movs    r0, #0                      @ knob is back: Morph follows it again
    strb    r0, [r3, #94]
    @ --- smooth the amount, derive hold step and wet mix (once per block).
20: vldr    s0, [r3, #100]              @ target
    vldr    s1, [r3, #104]              @ smoothed amount
    vsub.f32 s2, s0, s1
    vldr    s0, k_srr_slew
    vfma.f32 s1, s2, s0
    vldr    s0, [r3, #100]
    vcmpe.f32 s0, #0
    vmrs    APSR_nzcv, fpscr
    bne     21f
    vldr    s0, k_srr_floor             @ target 0: land exactly on bypass
    vcmpe.f32 s1, s0
    vmrs    APSR_nzcv, fpscr
    bge     21f
    vsub.f32 s1, s1, s1
21: vstr    s1, [r3, #104]
    ldr     r0, =SETTINGS               @ fxsl 2: the amount drives warble, not SRR
    ldr     r1, [r0]
    ldr     r2, =SETTINGS_MAGIC
    cmp     r1, r2
    bne     22f
    ldrb    r0, [r0, #6]
    cmp     r0, #2
    bne     22f
    push    {lr}                        @ lr is live in the stock audio routine
    bl      warble_block
    pop     {lr}
    movs    r0, #0
    strb    r0, [r3, #95]               @ SRR off
    b       90f
22: vcmpe.f32 s1, #0
    vmrs    APSR_nzcv, fpscr
    ite     gt
    movgt   r0, #1
    movle   r0, #0
    strb    r0, [r3, #95]               @ SRR active
    ble     90f
    vldr    s0, k_64                    @ step = table(amount * 64), linear
    vmul.f32 s0, s1, s0
    vcvt.s32.f32 s2, s0
    vmov    r0, s2
    cmp     r0, #63
    it      gt
    movgt   r0, #63
    vmov    s2, r0
    vcvt.f32.s32 s2, s2
    vsub.f32 s0, s0, s2                 @ fraction
    ldr     r1, =srr_steps
    add     r1, r1, r0, lsl #2
    vldr    s2, [r1]
    vldr    s1, [r1, #4]
    vsub.f32 s1, s1, s2
    vfma.f32 s2, s1, s0
    vstr    s2, [r3, #108]              @ step
    vldr    s1, [r3, #104]              @ mix = min(1, 4 * amount)
    vmov.f32 s0, #4.0
    vmul.f32 s1, s1, s0
    vmov.f32 s0, #1.0
    vcmpe.f32 s1, s0
    vmrs    APSR_nzcv, fpscr
    it      gt
    vmovgt.f32 s1, s0
    vstr    s1, [r3, #112]
    @ --- Morph cap while tape-dubbing.
90: ldr     r0, =MOD
    ldrb    r1, [r0, #16]
    cmp     r1, #1
    bne     99f
    ldr     r1, [r0]
    ldr     r0, =MAGIC
    cmp     r1, r0
    bne     99f
    ldr     r0, =REC_ACTIVE
    ldr     r0, [r0]
    cbz     r0, 99f
    TAPE_SETTING
    bne     99f
    ldr     r0, =SETTINGS               @ mcap (+9): 0 = no cap, 1-9 = 0.1-0.9
    ldr     r1, [r0]
    ldr     r2, =SETTINGS_MAGIC
    movs    r3, #3                      @ default without settings: 0.3
    cmp     r1, r2
    it      eq
    ldrbeq  r3, [r0, #9]
    cmp     r3, #9
    it      hi
    movhi   r3, #3
    cbz     r3, 99f
    ldr     r0, =k_morph_caps
    add     r0, r0, r3, lsl #2
    vldr    s0, [r0]
    vcmpe.f32 s31, s0
    vmrs    APSR_nzcv, fpscr
    it      gt
    vmovgt.f32 s31, s0
99: ldr     r0, =MOD                    @ +232: anything for the per-sample hooks?
    ldrb    r1, [r0, #95]               @ +233: tape / feedback mode on
    ldrb    r2, [r0, #16]
    cmp     r2, #1
    ite     eq
    moveq   r2, #1
    movne   r2, #0
    orr     r1, r1, r2
    ldr     r3, [r0]
    push    {r4}
    ldr     r4, =MAGIC
    cmp     r3, r4
    pop     {r4}
    itt     ne
    movne   r1, #0
    movne   r2, #0
    strb    r1, [r0, #232]
    strb    r2, [r0, #233]
    vpop    {s0-s2}
    pop     {r0-r3}
    b.w     P10_RETURN
    .align 2
k_morph_caps: .float 0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9   @ by mcap digit
k_srr_slew:  .float 0.008               @ ~ the plugin's per-sample 0.001, per 8-frame block
k_srr_floor: .float 0.00001
k_64:        .float 64.0
k_fx_span:   .float 0.000250062516     @ 1 / (4095 - T_FX_ZERO)

@ Warble (fxsl 2), once per block from P10 with r3 = MOD, s1 = smoothed amount.
@ A virtual tape delay d (samples) drifts to random targets, as in the plugin's
@ Prism Warble: events at (30a + 0.1)/s move the target to 100 + U*880*a with
@ a random one-pole coefficient (U * 0.0001 per sample = U * 0.0008 per
@ block). The pitch of a delay line read at d is 1 - dd/dt, so the playback
@ rate is multiplied by w = 1 - (d - d_prev)/8 for this block. The position
@ offset therefore stays bounded (it is the change in d). At amount 0 the
@ delay returns to rest and w lands exactly on 1.
@ Applied by scaling the stock target (0x200220e8) and the glided rate
@ (0x200220e0) by w / w_applied, which commutes with the per-sample glide.
@ The clean target is re-read whenever the stock code has written a new one.
@ The tape engine divides the glided rate by w_applied, so dubs do not warble.
@ State (WARBLE): +0 magic, +4 RNG, +8 d, +12 target d, +16 coefficient,
@ +20 w_applied, +24 clean target, +28 last target written (bits).
    .thumb_func
warble_block:
    push    {r4-r7, lr}
    vpush   {s3-s8}
    ldr     r4, =WARBLE
    ldr     r5, [r4]
    ldr     r6, =WARBLE_MAGIC
    cmp     r5, r6
    beq     1f
    str     r6, [r4]
    ldr     r5, =0x2545f491
    str     r5, [r4, #4]
    vldr    s3, k_w_rest
    vstr    s3, [r4, #8]
    vstr    s3, [r4, #12]
    vsub.f32 s3, s3, s3
    vstr    s3, [r4, #16]
    vmov.f32 s3, #1.0
    vstr    s3, [r4, #20]
    mvn     r5, #0
    str     r5, [r4, #28]
1:  vcmpe.f32 s1, #0
    vmrs    APSR_nzcv, fpscr
    ble     5f
    bl      w_uniform                   @ event this block?
    vldr    s4, k_w_30
    vmul.f32 s4, s1, s4
    vldr    s5, k_w_0p1
    vadd.f32 s4, s4, s5
    vldr    s5, k_w_per_block
    vmul.f32 s4, s4, s5
    vcmpe.f32 s3, s4
    vmrs    APSR_nzcv, fpscr
    bge     6f
    bl      w_uniform                   @ new target delay
    vldr    s4, k_w_880
    vmul.f32 s3, s3, s4
    vmul.f32 s3, s3, s1
    vldr    s4, k_w_rest
    vadd.f32 s3, s3, s4
    vstr    s3, [r4, #12]
    bl      w_uniform                   @ new drift speed
    vldr    s4, k_w_coef
    vmul.f32 s3, s3, s4
    vstr    s3, [r4, #16]
    b       6f
5:  vldr    s3, k_w_rest                @ amount 0: back to rest
    vstr    s3, [r4, #12]
    vldr    s3, k_w_return
    vstr    s3, [r4, #16]
6:  vldr    s4, [r4, #8]                @ d_prev
    vldr    s5, [r4, #12]
    vsub.f32 s5, s5, s4
    vldr    s6, [r4, #16]
    vmul.f32 s5, s5, s6
    vadd.f32 s5, s4, s5                 @ d
    vcmpe.f32 s1, #0                    @ amount 0 and nearly at rest: land
    vmrs    APSR_nzcv, fpscr
    bgt     7f
    vldr    s6, k_w_rest
    vsub.f32 s7, s5, s6
    vabs.f32 s7, s7
    vldr    s8, k_w_land
    vcmpe.f32 s7, s8
    vmrs    APSR_nzcv, fpscr
    it      lt
    vmovlt.f32 s5, s6
7:  vstr    s5, [r4, #8]
    vsub.f32 s5, s5, s4                 @ w = 1 - (d - d_prev) / 8
    vldr    s6, k_w_eighth
    vmul.f32 s5, s5, s6
    vmov.f32 s4, #1.0
    vsub.f32 s5, s4, s5
    vldr    s6, [r4, #20]               @ w_applied
    vcmpe.f32 s5, s4
    vmrs    APSR_nzcv, fpscr
    bne     8f
    vcmpe.f32 s6, s4
    vmrs    APSR_nzcv, fpscr
    beq     9f                          @ at rest: leave the stock rates alone
8:  ldr     r5, =TARGET
    ldr     r6, [r5]
    ldr     r7, [r4, #28]
    cmp     r6, r7
    it      ne
    strne   r6, [r4, #24]               @ the stock code wrote a new target
    vldr    s7, [r4, #24]
    vmul.f32 s8, s7, s5
    vstr    s8, [r5]
    vmov    r6, s8
    str     r6, [r4, #28]
    ldr     r5, =RATE                   @ glided rate *= w / w_applied
    vldr    s3, [r5]
    vdiv.f32 s8, s5, s6
    vmul.f32 s3, s3, s8
    vcmpe.f32 s5, s4                    @ back at w = 1: snap onto the clean
    vmrs    APSR_nzcv, fpscr            @ target when within 1e-5 (glide states)
    bne     81f
    vsub.f32 s8, s3, s7
    vabs.f32 s8, s8
    vabs.f32 s6, s7
    vldr    s4, k_w_snap
    vmul.f32 s6, s6, s4
    vcmpe.f32 s8, s6
    vmrs    APSR_nzcv, fpscr
    it      le
    vmovle.f32 s3, s7
81: vstr    s3, [r5]
    vstr    s5, [r4, #20]
9:  vpop    {s3-s8}
    pop     {r4-r7, pc}

@ L1 (0x08024af8, TIM2 LED code): the Varispeed LED compares the target rate
@ with exact octaves. While warble scales the target, show the clean one, so
@ the colour windows keep following the knob and the octave lock.
@ Replaces "ldr r1,=TARGET; vldr s13,[r1]". Flags are set again right after.
    .thumb_func
led_rate:
    ldr     r1, =TARGET
    vldr    s13, [r1]
    push    {r0, r2}
    ldr     r0, =WARBLE
    ldr     r2, [r0]
    ldr     r1, =WARBLE_MAGIC
    cmp     r2, r1
    bne     9f
    ldr     r2, [r0, #20]               @ w_applied == 1.0: the target is clean
    mov     r1, #0x3f800000
    cmp     r2, r1
    beq     9f
    ldr     r1, =TARGET                 @ the stock code just wrote a new (clean)
    ldr     r1, [r1]                    @ target that P10 has not scaled yet
    ldr     r2, [r0, #28]
    cmp     r1, r2
    bne     9f
    vldr    s13, [r0, #24]
9:  pop     {r0, r2}
    ldr     r1, =TARGET
    b.w     LED_RETURN

@ s3 = uniform [0, 1) from the xorshift32 state at WARBLE+4 (r4 = WARBLE).
    .thumb_func
w_uniform:
    ldr     r5, [r4, #4]
    eor     r5, r5, r5, lsl #13
    eor     r5, r5, r5, lsr #17
    eor     r5, r5, r5, lsl #5
    str     r5, [r4, #4]
    lsrs    r5, r5, #8
    vmov    s3, r5
    vcvt.f32.u32 s3, s3, #24
    bx      lr

    .align 2
k_w_rest:      .float 100.0
k_w_30:        .float 30.0
k_w_0p1:       .float 0.1
k_w_per_block: .float 0.000166666667   @ 1 / 6000 blocks per second
k_w_880:       .float 880.0
k_w_coef:      .float 0.0008
k_w_return:    .float 0.002
k_w_land:      .float 0.01
k_w_eighth:    .float 0.125
k_w_snap:      .float 0.00001
srr_steps:                              @ (200 / 48000) ^ (i / 64): hold step per sample
    .word 0x3f800000                  @ 1
    .word 0x3f6afd69                  @ 0.91792923
    .word 0x3f57b43f                  @ 0.842594071
    .word 0x3f460047                  @ 0.773441726
    .word 0x3f35c040                  @ 0.709964768
    .word 0x3f26d5a4                  @ 0.651697413
    .word 0x3f19246e                  @ 0.598212104
    .word 0x3f0c92e4                  @ 0.549116376
    .word 0x3f01096b                  @ 0.504049972
    .word 0x3eece4ae                  @ 0.462682202
    .word 0x3ed97387                  @ 0.424709518
    .word 0x3ec79ad9                  @ 0.38985328
    .word 0x3eb73921                  @ 0.357857721
    .word 0x3ea82f96                  @ 0.328488062
    .word 0x3e9a61fb                  @ 0.301528794
    .word 0x3e8db662                  @ 0.276782094
    .word 0x3e8214fd                  @ 0.254066374
    .word 0x3e6ecfe6                  @ 0.233214951
    .word 0x3e5b366e                  @ 0.21407482
    .word 0x3e4938bf                  @ 0.196505535
    .word 0x3e38b50e                  @ 0.180378174
    .word 0x3e298c56                  @ 0.165574399
    .word 0x3e1ba21c                  @ 0.15198558
    .word 0x3e0edc3c                  @ 0.139512007
    .word 0x3e0322b9                  @ 0.128062149
    .word 0x3df0bf19                  @ 0.117551989
    .word 0x3ddcfcfc                  @ 0.107904407
    .word 0x3dcad9ff                  @ 0.0990486094
    .word 0x3dba3410                  @ 0.0909196137
    .word 0x3daaebe8                  @ 0.083457771
    .word 0x3d9ce4d4                  @ 0.0766083274
    .word 0x3d900478                  @ 0.070321023
    .word 0x3d8432a5                  @ 0.0645497224
    .word 0x3d72b24e                  @ 0.059252077
    .word 0x3d5ec739                  @ 0.0543892134
    .word 0x3d4c7ea1                  @ 0.0499254488
    .word 0x3d3bb62c                  @ 0.0458280287
    .word 0x3d2c4e54                  @ 0.0420668871
    .word 0x3d1e2a29                  @ 0.0386144253
    .word 0x3d112f1a                  @ 0.0354453096
    .word 0x3d0544c5                  @ 0.0325362858
    .word 0x3cf4a98f                  @ 0.0298660077
    .word 0x3ce0952c                  @ 0.0274148815
    .word 0x3cce26aa                  @ 0.025164921
    .word 0x3cbd3b68                  @ 0.0230996166
    .word 0x3cadb39f                  @ 0.0212038133
    .word 0x3c9f7221                  @ 0.0194636
    .word 0x3c925c27                  @ 0.0178662073
    .word 0x3c86591d                  @ 0.0163999139
    .word 0x3c76a4e3                  @ 0.0150539604
    .word 0x3c6266dd                  @ 0.0138184702
    .word 0x3c4fd223                  @ 0.0126843777
    .word 0x3c3ec3cc                  @ 0.0116433611
    .word 0x3c2f1bce                  @ 0.0106877815
    .word 0x3c20bcc1                  @ 0.00981062701
    .word 0x3c138ba4                  @ 0.0090054613
    .word 0x3c076fb2                  @ 0.00826637615
    .word 0x3bf8a453                  @ 0.00758794829
    .word 0x3be43c54                  @ 0.00696519953
    .word 0x3bd18112                  @ 0.00639356024
    .word 0x3bc04f5d                  @ 0.00586883583
    .word 0x3bb086e8                  @ 0.00538717595
    .word 0x3ba20a0e                  @ 0.00494504627
    .word 0x3b94bd97                  @ 0.00453920251
    .word 0x3b888889                  @ 0.00416666667
    .ltorg

@ P11 / P12 (per sample, just before the S.O.S. mix in each branch): SRR on
@ the Gene playback. Sample-and-hold with a fractional phase; wet mix.

    .thumb_func
wa_tape:
    WRITE_HOOK s4, s3, WA_STOCK, WA_DONE
    .ltorg

    .thumb_func
wb_tape:
    WRITE_HOOK s7, s6, WB_STOCK, WB_DONE
    .ltorg

@ One channel: v in s13; stored = sat16(trunc(stored * retention + v * 32767)).
@ Skipped when retention is exactly 1 and v == 0. Uses r2, r11, s13, s14.
    .macro WRITE_CH base, idx
    vcmp.f32 s13, #0
    vmrs    APSR_nzcv, fpscr
    bne     91f
    cbnz    r3, 92f
91: add     r11, \base, \idx, lsl #1
    ldrsh   r2, [r11]
    vmov    s14, r2
    vcvt.f32.s32 s14, s14
    vmul.f32 s13, s13, s15
    vfma.f32 s13, s14, s10
    vcvt.s32.f32 s13, s13
    vmov    r2, s13
    ssat    r2, #16, r2
    strh    r2, [r11]
92:
    .endm
    .macro WRITE_POINT idx
    vmul.f32 s12, s4, s5                @ t = d / |r|
    vmov.f32 s13, s6
    vfma.f32 s13, s12, s8               @ vL
    WRITE_CH r8, \idx
    vmov.f32 s13, s7
    vfma.f32 s13, s12, s9               @ vR
    WRITE_CH r9, \idx
    .endm

@ ---------------------------------------------------------------------------
@ Tape engine (position independent, copied to RAMCODE). r0/r1 = input bits.
@ Registers in the fast path: r0 pos, r1 reverse target, r4..r6 window,
@ r7 MOD, r8/r9 channel bases, r3 exact flag.
@ Per-block cache (MOD): +56 mode (0 = recompute, 1 = tape, 2 = stock),
@ +57 exact (retention == 1), +60 r, +64 1/|r|, +68 retention, +72 window end,
@ +76 left base, +80 right base; window start/length +44/+48; head +32/+36;
@ previous input +24/+28.
    .align 2
@ eng_prepare (r0/r1 = first frame of the block): fill the block cache.
    .thumb_func
engine:
eng_prepare:
    push    {r4-r7, lr}
    vpush   {s0-s4}
    vmov    s0, r0
    vmov    s1, r1
    ldr     r7, e_mod
    bl      e_setup
    vpop    {s0-s4}
    pop     {r4-r7, pc}

@ eng_flush: write the buffered frames of the previous block with its cache.
    .thumb_func
eng_flush:
    push    {r4-r11, lr}
    vpush   {s0-s15}
    ldr     r7, e_mod
    ldrb    r2, [r7, #56]
    cmp     r2, #1
    bne     e_done                      @ no valid cache: drop (cannot happen)
    ldr     r0, [r7, #32]               @ pos
    vldr    s3, [r7, #36]               @ frac
    vldr    s2, [r7, #60]               @ r
    vldr    s5, [r7, #64]               @ 1/|r|
    vldr    s6, [r7, #24]               @ prevL
    vldr    s7, [r7, #28]               @ prevR
    vldr    s10, [r7, #68]              @ retention
    vmov.f32 s11, #1.0
    vldr    s15, e_32767
    ldr     r4, [r7, #44]               @ window start
    ldr     r5, [r7, #48]               @ window length
    ldr     r6, [r7, #72]               @ window end
    ldr     r8, [r7, #76]               @ left base
    ldr     r9, [r7, #80]               @ right base
    ldrb    r3, [r7, #57]               @ exact retention
    movs    r10, #0                     @ frame index
    vcmpe.f32 s2, #0
    vmrs    APSR_nzcv, fpscr
    beq     e_still
    blt     e_reverse
@ Forward frames.
e_fwd:
    ldrb    r2, [r7, #COUNT]
    cmp     r10, r2
    bhs     e_store
    add     r2, r7, r10, lsl #3
    vldr    s0, [r2, #BUFFER]
    vldr    s1, [r2, #(BUFFER + 4)]
    vsub.f32 s8, s0, s6                 @ dL
    vsub.f32 s9, s1, s7                 @ dR
    vsub.f32 s4, s11, s3                @ d = 1 - frac
10: vcmpe.f32 s4, s2
    vmrs    APSR_nzcv, fpscr
    bgt     20f
    adds    r0, r0, #1
    cmp     r0, r6
    it      ge
    movge   r0, r4
    WRITE_POINT r0
    vadd.f32 s4, s4, s11
    b       10b
20: vadd.f32 s3, s3, s2
21: vcmpe.f32 s3, s11
    vmrs    APSR_nzcv, fpscr
    blt     22f
    vsub.f32 s3, s3, s11
    b       21b
22: vmov.f32 s6, s0                     @ prev = this frame
    vmov.f32 s7, s1
    adds    r10, r10, #1
    b       e_fwd
@ Reverse frames (q = -r in s2).
e_reverse:
    vneg.f32 s2, s2
e_rev:
    ldrb    r2, [r7, #COUNT]
    cmp     r10, r2
    bhs     e_store
    add     r2, r7, r10, lsl #3
    vldr    s0, [r2, #BUFFER]
    vldr    s1, [r2, #(BUFFER + 4)]
    vsub.f32 s8, s0, s6
    vsub.f32 s9, s1, s7
    vmov.f32 s4, s3                     @ d = frac, target = pos
    mov     r1, r0
    vcmpe.f32 s4, #0
    vmrs    APSR_nzcv, fpscr
    bgt     32f
    vmov.f32 s4, s11                    @ at an integer: d = 1, target = pos - 1
    subs    r1, r1, #1
    cmp     r1, r4
    it      lt
    addlt   r1, r1, r5
32: vcmpe.f32 s4, s2
    vmrs    APSR_nzcv, fpscr
    bgt     40f
    WRITE_POINT r1
    subs    r1, r1, #1
    cmp     r1, r4
    it      lt
    addlt   r1, r1, r5
    vadd.f32 s4, s4, s11
    b       32b
40: vsub.f32 s3, s3, s2                 @ frac -= q, borrow into pos
41: vcmpe.f32 s3, #0
    vmrs    APSR_nzcv, fpscr
    bge     42f
    vadd.f32 s3, s3, s11
    subs    r0, r0, #1
    cmp     r0, r4
    it      lt
    addlt   r0, r0, r5
    b       41b
42: vmov.f32 s6, s0
    vmov.f32 s7, s1
    adds    r10, r10, #1
    b       e_rev
@ Stopped: nothing moves or writes; prev follows the last frame.
e_still:
    ldrb    r2, [r7, #COUNT]
    cbz     r2, e_store
    subs    r2, r2, #1
    add     r2, r7, r2, lsl #3
    vldr    s6, [r2, #BUFFER]
    vldr    s7, [r2, #(BUFFER + 4)]
e_store:
    str     r0, [r7, #32]
    vstr    s3, [r7, #36]
    vstr    s6, [r7, #24]
    vstr    s7, [r7, #28]
    ldr     r2, e_head
    str     r0, [r2]                    @ display / high-water follow the tape head
e_done:
    movs    r2, #0
    strb    r2, [r7, #COUNT]
    vpop    {s0-s15}
    pop     {r4-r11, pc}

@ e_setup: once per block. Decides tape vs stock and fills the cache.
e_setup:
    push    {lr}
    movs    r2, #2
    strb    r2, [r7, #56]               @ default: stock
    ldr     r2, [r7]
    ldr     r3, e_magic
    cmp     r2, r3
    bne     9f
    ldrb    r2, [r7, #16]
    cmp     r2, #1
    bne     9f
    ldr     r2, e_settings              @ options.txt "tape 0": stock writes
    ldr     r3, [r2]
    ldr     r4, e_settings_magic
    cmp     r3, r4
    bne     8f
    ldrb    r3, [r2, #4]
    cmp     r3, #1
    bne     9f
8:  ldr     r2, e_index
    ldr     r2, [r2]                    @ record splice
    ldr     r3, e_count
    ldr     r3, [r3]
    cmp     r2, #1
    blt     9f
    cmp     r2, r3
    bgt     9f
    ldr     r3, e_markers
    subs    r4, r2, #1
    ldr     r4, [r3, r4, lsl #2]        @ splice start
    ldr     r5, [r3, r2, lsl #2]        @ splice end
    subs    r6, r5, r4                  @ span
    cmp     r6, #2
    blt     9f
    ldr     r2, e_gene
    vldr    s2, [r2]
    vcvt.s32.f32 s2, s2
    vmov    r2, s2                      @ length = clamp(gene, 16, span)
    cmp     r2, #16
    it      lt
    movlt   r2, #16
    cmp     r2, r6
    it      gt
    movgt   r2, r6
    vmov    s2, r6
    vcvt.f32.s32 s2, s2
    ldr     r3, e_slide
    vldr    s3, [r3]
    vmul.f32 s2, s2, s3
    vcvt.s32.f32 s2, s2
    vmov    r3, s2
    adds    r3, r4, r3                  @ start = splice start + trunc(span * slide)
    subs    r6, r5, r2
    cmp     r3, r6
    it      gt
    movgt   r3, r6
    cmp     r3, r4
    it      lt
    movlt   r3, r4                      @ r3 = window start, r2 = length
    ldrb    r4, [r7, #40]
    cbnz    r4, 2f
    str     r3, [r7, #32]               @ new take: head at the window start
    movs    r4, #0
    str     r4, [r7, #36]
    vstr    s0, [r7, #24]
    vstr    s1, [r7, #28]
    movs    r4, #1
    strb    r4, [r7, #40]
    b       3f
2:  ldr     r4, [r7, #44]               @ window moved: keep the head's offset
    ldr     r5, [r7, #48]
    cmp     r4, r3
    bne     4f
    cmp     r5, r2
    beq     3f
4:  ldr     r5, [r7, #32]
    subs    r5, r5, r4
    cmp     r5, #0
    it      lt
    movlt   r5, #0
    udiv    r6, r5, r2
    mls     r5, r6, r2, r5
    adds    r5, r3, r5
    str     r5, [r7, #32]
3:  str     r3, [r7, #44]
    str     r2, [r7, #48]
    adds    r3, r3, r2
    str     r3, [r7, #72]               @ window end
    ldr     r2, e_rate                  @ speed, clamped to +/-4
    vldr    s2, [r2]
    ldr     r2, e_warble                @ without the warble factor (fxsl 2)
    ldr     r3, [r2]
    ldr     r2, e_wmagic
    cmp     r3, r2
    bne     4f
    ldr     r2, e_warble
    vldr    s3, [r2, #20]
    vdiv.f32 s2, s2, s3
4:
    vmov.f32 s3, #4.0
    vcmpe.f32 s2, s3
    vmrs    APSR_nzcv, fpscr
    it      gt
    vmovgt.f32 s2, s3
    vneg.f32 s3, s3
    vcmpe.f32 s2, s3
    vmrs    APSR_nzcv, fpscr
    it      lt
    vmovlt.f32 s2, s3
    vstr    s2, [r7, #60]
    vabs.f32 s3, s2                     @ 1/|r| (0 when stopped)
    vcmpe.f32 s3, #0
    vmrs    APSR_nzcv, fpscr
    beq     5f
    vmov.f32 s4, #1.0
    vdiv.f32 s3, s4, s3
5:  vstr    s3, [r7, #64]
    vldr    s3, [r7, #20]               @ retention
    vstr    s3, [r7, #68]
    vmov.f32 s4, #1.0
    vcmpe.f32 s3, s4
    vmrs    APSR_nzcv, fpscr
    ite     eq
    moveq   r2, #1
    movne   r2, #0
    strb    r2, [r7, #57]
    ldr     r2, e_left
    ldr     r2, [r2]
    str     r2, [r7, #76]
    ldr     r2, e_right
    ldr     r2, [r2]
    str     r2, [r7, #80]
    movs    r2, #1
    strb    r2, [r7, #56]               @ tape handles this block
9:  pop     {pc}

    .align 2
e_mod:     .word MOD
e_magic:   .word MAGIC
e_head:    .word HEAD
e_index:   .word REC_INDEX
e_count:   .word MARKER_COUNT
e_markers: .word MARKERS
e_gene:    .word GENE_LENGTH
e_slide:   .word SLIDE
e_rate:    .word RATE
e_left:    .word LEFT_PTR
e_right:   .word RIGHT_PTR
e_32767:   .float 32767.0
e_warble:  .word WARBLE
e_wmagic:  .word WARBLE_MAGIC
e_settings: .word SETTINGS
e_settings_magic: .word SETTINGS_MAGIC
engine_end:

    .align 2
    .ltorg
