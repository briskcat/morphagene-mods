@ Module shift_gestures: SHIFT knob gestures + Varispeed octave lock (mg204).
@ Linked after the previous module's code (mgmod/module.py).
@ Design: README.md beside this file.
@
@ State block MOD (SRAM, inside the heap/stack gap; not zeroed at reset):
@   +0  magic "SHFT"
@   +4  active   u8  SHIFT session in progress (state 14, or state 4 latch armed)
@   +5  consumed u8  a knob moved more than T during this session
@   +6  owner    u8  1 = S.O.S., 2 = Varispeed, 3 = Morph (SRR), 4 = Gene Size, 5 = Slide,
@                    6 = Organize (Turing evolution, sldm 1)
@   +7  lock     u8  octave lock engaged
@   +8  ref_sos  u16 / +10 ref_vs u16   snapshots at session start
@   +12 lock_k   u16 index into octave_m (-2,-1,-1/2,-1/4,stop,1/4,1/2,1,2)
@   +14 release_vs u16 Varispeed reading at SHIFT release (0xffff while held)
@   +16..+127 reserved for sos_feedback.S and tape_sos.S (zeroed here)
@   +208 ref_gs u16 / +210 ref_slide u16  snapshots for gene_shape.S (owners 4, 5)
@   +128..+239 zeroed here too; +240 is the options.txt settings block
@   +128 ref_org u16 (Organize at session start), +130 Organize held u8

    .syntax unified
    .cpu cortex-m4
    .fpu fpv4-sp-d16
    .thumb

    .equ MOD,          0x2002A000
    .equ MAGIC,        0x53484654
    .equ STATE,        0x20001020
    .equ SHIFT_LATCH,  0x2002139c
    .equ NAVIGATION,   0x200012e0
    .equ RELEASE_TIME, 0x20001024
    .equ SOS_ADC,      0x20021c68
    .equ ORG_ADC,      0x20021c70  @ Organize (64-sample average)
    .equ VS_ADC,       0x20021c74
    .equ MORPH_ADC,    0x20021c6c
    .equ VSOP,         0x200012a8
    .equ SLIDE_PTR,    0x20022154
    .equ SLIDE_ADC,    0x20021c78
    .equ GS_ADC,       0x20021c7c
    .equ T_SLIDE,      96          @ Slide is a 4-sample average: wider claim threshold
    .equ T_KNOB,       48          @ counts of movement that claim a SHIFT gesture
    .equ T_PICKUP,     231         @ counts (about half an octave) that release a lock
    .equ SETTINGS,     0x2002A0F0  @ options.txt settings (options_keys / sd_updater)
    .equ SETTINGS_MAGIC, 0x5354504f

    @ Return addresses in the stock image.
    .equ P1_RETURN,    0x0802486e
    .equ TIM2_DONE,    0x080248fc
    .equ NAV_STORE,    0x080251e0
    .equ NAV_SKIP,     0x080251e6
    .equ RATE_NEXT,    0x08027882
    .equ RATE_FULL,    0x08028824
    .equ GLIDE_NEXT,   0x08027be4

    .text
    .global p1_session, p3_state14, p4_record_tap, p5_octave, p6_glide

@ P1 (hook at 0x0802486a, TIM2 control ISR, after debounce, before dispatch).
@ Live: ip = SHIFT integrator, r2 = REC, r3 = SPLICE, lr = now.
    .thumb_func
p1_session:
    push    {r0-r4}
    ldr     r4, =MOD
    ldr     r1, [r4]
    ldr     r0, =MAGIC
    cmp     r1, r0
    beq     1f
    str     r0, [r4]
    movs    r0, #0                      @ zero +4..+239 (tape_sos / gene_shape fields too)
    movs    r1, #4
0:  str     r0, [r4, r1]
    adds    r1, r1, #4
    cmp     r1, #240
    blt     0b
1:  ldr     r1, =STATE
    ldr     r1, [r1]
    cmp     r1, #14
    beq     2f
    cmp     r1, #4
    bne     9f
    ldr     r0, =SHIFT_LATCH
    ldr     r0, [r0]
    cmp     r0, #1
    bne     9f
2:  ldrb    r0, [r4, #4]                @ session: snapshot once
    cbnz    r0, 3f
    ldr     r0, =SOS_ADC
    ldr     r0, [r0]
    strh    r0, [r4, #8]
    ldr     r0, =VS_ADC
    ldr     r0, [r0]
    strh    r0, [r4, #10]
    ldr     r0, =MORPH_ADC
    ldr     r0, [r0]
    strh    r0, [r4, #92]               @ ref_morph (used by the SRR gesture)
    ldr     r0, =GS_ADC
    ldr     r0, [r0]
    strh    r0, [r4, #208]              @ ref_gs (window gesture)
    ldr     r0, =SLIDE_ADC
    ldr     r0, [r0]
    strh    r0, [r4, #210]              @ ref_slide (jitter gesture)
    ldr     r0, =ORG_ADC
    ldr     r0, [r0]
    strh    r0, [r4, #128]              @ ref_org (Turing evolution gesture)
    movs    r0, #0
    strb    r0, [r4, #5]
    strb    r0, [r4, #6]
    movs    r0, #1
    strb    r0, [r4, #4]
3:  cmp     ip, #0                      @ detect only with SHIFT alone
    beq     8f
    cmp     r2, #0
    bne     8f
    cmp     r3, #0
    bne     8f
    ldrb    r0, [r4, #5]
    cmp     r0, #0
    bne     8f
    ldr     r0, =SOS_ADC
    ldr     r0, [r0]
    ldrh    r1, [r4, #8]
    subs    r0, r0, r1
    it      mi
    rsbmi   r0, r0, #0
    cmp     r0, #T_KNOB
    ble     4f
    movs    r0, #1
    strb    r0, [r4, #5]
    strb    r0, [r4, #6]
    b       8f
4:  ldr     r0, =SETTINGS           @ options.txt "octl 0": no Varispeed claim
    ldr     r1, [r0]
    ldr     r0, =SETTINGS_MAGIC
    cmp     r1, r0
    bne     5f
    ldr     r0, =SETTINGS
    ldrb    r0, [r0, #5]
    cmp     r0, #0
    beq     6f
5:  ldr     r0, =VS_ADC
    ldr     r0, [r0]
    ldrh    r1, [r4, #10]
    subs    r0, r0, r1
    it      mi
    rsbmi   r0, r0, #0
    cmp     r0, #T_KNOB
    ble     6f
    movs    r0, #1
    strb    r0, [r4, #5]
    movs    r0, #2
    strb    r0, [r4, #6]
    b       8f
6:  ldr     r0, =SETTINGS           @ options.txt "fxsl 0": no Morph claim
    ldr     r1, [r0]
    ldr     r0, =SETTINGS_MAGIC
    cmp     r1, r0
    bne     12f
    ldr     r0, =SETTINGS
    ldrb    r0, [r0, #6]
    cmp     r0, #0
    beq     7f
12: ldr     r0, =MORPH_ADC              @ SHIFT + Morph: SRR amount (owner 3)
    ldr     r0, [r0]
    ldrh    r1, [r4, #92]
    subs    r0, r0, r1
    it      mi
    rsbmi   r0, r0, #0
    cmp     r0, #T_KNOB
    ble     7f
    movs    r0, #1
    strb    r0, [r4, #5]
    movs    r0, #3
    strb    r0, [r4, #6]
    b       8f
7:  ldr     r0, =SETTINGS               @ SHIFT + Gene Size (owner 4): the Turing
    ldr     r1, [r0]                    @ pattern rate, only with options.txt "sldm 1"
    ldr     r0, =SETTINGS_MAGIC
    cmp     r1, r0
    bne     11f
    ldr     r0, =SETTINGS
    ldrb    r0, [r0, #10]
    cmp     r0, #1
    bne     11f
    ldr     r0, =GS_ADC
    ldr     r0, [r0]
    ldrh    r1, [r4, #208]
    subs    r0, r0, r1
    it      mi
    rsbmi   r0, r0, #0
    cmp     r0, #T_KNOB
    ble     11f
    movs    r0, #1
    strb    r0, [r4, #5]
    movs    r0, #4
    strb    r0, [r4, #6]
    b       8f
11: ldr     r0, =SLIDE_ADC              @ SHIFT + Slide: jitter / spread (owner 5)
    ldr     r0, [r0]
    ldrh    r1, [r4, #210]
    subs    r0, r0, r1
    it      mi
    rsbmi   r0, r0, #0
    cmp     r0, #T_SLIDE
    ble     13f
    movs    r0, #1
    strb    r0, [r4, #5]
    movs    r0, #5
    strb    r0, [r4, #6]
    b       8f
13: ldr     r0, =SETTINGS               @ SHIFT + Organize: Turing evolution
    ldr     r1, [r0]                    @ (owner 6), only with options.txt "sldm 1"
    ldr     r0, =SETTINGS_MAGIC
    cmp     r1, r0
    bne     8f
    ldr     r0, =SETTINGS
    ldrb    r0, [r0, #10]
    cmp     r0, #1
    bne     8f
    ldr     r0, =ORG_ADC
    ldr     r0, [r0]
    ldrh    r1, [r4, #128]
    subs    r0, r0, r1
    it      mi
    rsbmi   r0, r0, #0
    cmp     r0, #T_KNOB
    ble     8f
    movs    r0, #1
    strb    r0, [r4, #5]
    strb    r0, [r4, #130]              @ hold Organize (no splice change)
    movs    r0, #6
    strb    r0, [r4, #6]
8:  ldr     r1, =STATE                  @ consumed in state 14: hide REC/SPLICE
    ldr     r1, [r1]                    @ from the combo checks (no deletes)
    cmp     r1, #14
    bne     10f
    ldrb    r0, [r4, #4]
    cbz     r0, 10f
    ldrb    r0, [r4, #5]
    cbz     r0, 10f
    movs    r0, #0
    str     r0, [sp, #8]                @ saved r2
    str     r0, [sp, #12]               @ saved r3
    b       10f
9:  movs    r0, #0                      @ not a session: keep consumed/owner
    strb    r0, [r4, #4]
10: pop     {r0-r4}
    ldr     r9, =STATE                  @ replaced instruction
    b.w     P1_RETURN

@ P3 (hook at 0x080251dc, state 14 navigation block; also the gate-edge path).
@ Skip the navigation write only on a real release (ip == 0) of a consumed session.
    .thumb_func
p3_state14:
    cmp     ip, #0
    bne     1f
    ldr     r0, =MOD
    ldrb    r1, [r0, #4]
    cbz     r1, 1f
    ldrb    r1, [r0, #5]
    cbz     r1, 1f
    ldr     r1, =NAVIGATION
    ldr     r3, =SHIFT_LATCH
    ldr     r2, =RELEASE_TIME
    movs    r0, #1
    b.w     NAV_SKIP
1:  ldr     r1, =NAVIGATION             @ replaced instructions
    ldr     r3, =SHIFT_LATCH
    b.w     NAV_STORE

@ P4 (hook at 0x080255da, state 4 SHIFT release while recording).
    .thumb_func
p4_record_tap:
    cmp     r2, #1
    bne.w   TIM2_DONE
    ldr     r3, =NAVIGATION
    str     ip, [r0]                    @ latch = 0
    ldr     r2, =MOD
    ldrb    r2, [r2, #4]
    cbz     r2, 1f
    ldr     r2, =MOD
    ldrb    r2, [r2, #5]
    cbz     r2, 1f
    movs    r2, #1                      @ consumed: no navigation
    b.w     TIM2_DONE
1:  movs    r2, #1
    str     r2, [r3]
    b.w     TIM2_DONE

@ P5 (hook at 0x0802787c, audio block, s18 = calibrated Varispeed x in 0..1).
@ While a SHIFT+Varispeed edit is held, snap x to the nearest octave with
@ hysteresis; after release keep it until the reading moves T_PICKUP counts.
@ vsop 0/1 only; vsop >= 2 (forward-only table) is left stock.
@ Preserves every register it uses: the audio routine keeps pointers live in
@ r4-r12 across this point (ip is read again at 0x08027bae).
    .thumb_func
p5_octave:
    push    {r0-r6}
    vpush   {s0-s1}
    ldr     r3, =MOD
    ldr     r1, [r3]
    ldr     r2, =MAGIC
    cmp     r1, r2
    bne     9f
    ldr     r1, =VSOP
    ldr     r1, [r1]
    cmp     r1, #2
    bhs     9f
    ldr     r4, =octave_m
    ldrb    r1, [r3, #6]
    cmp     r1, #2
    bne     5f
    ldrb    r1, [r3, #5]
    cbz     r1, 5f
    ldrb    r1, [r3, #4]
    cbz     r1, 5f
    @ Held edit: u = trunc(x * 6400), the lookup index in 1/16 units.
    vldr    s0, k6400
    vmul.f32 s0, s18, s0
    vcvt.s32.f32 s0, s0
    vmov    r0, s0
    ldrb    r1, [r3, #7]
    cbz     r1, 2f
    ldrh    r1, [r3, #12]               @ keep the current octave within
    ldrh    r1, [r4, r1, lsl #1]        @ +/- 448 (half spacing + 4 index units)
    lsls    r1, r1, #4
    adds    r1, r1, #8
    subs    r1, r0, r1
    it      mi
    rsbmi   r1, r1, #0
    cmp     r1, #448
    ble     3f
2:  movs    r1, #0                      @ nearest of the nine octave indices
    movs    r5, #0                      @ best k
    mvn     r2, #0x80000000             @ best distance
4:  ldrh    r6, [r4, r1, lsl #1]
    lsl     r6, r6, #4
    add     r6, r6, #8
    subs    r6, r0, r6
    it      mi
    rsbmi   r6, r6, #0
    cmp     r6, r2
    itt     lt
    movlt   r2, r6
    movlt   r5, r1
    adds    r1, r1, #1
    cmp     r1, #9
    blt     4b
    strh    r5, [r3, #12]
3:  movs    r0, #1
    strb    r0, [r3, #7]
    movw    r0, #0xffff
    strh    r0, [r3, #14]
    b       7f
5:  ldrb    r1, [r3, #7]                @ not editing: latched lock?
    cbz     r1, 9f
    ldr     r0, =VS_ADC
    ldr     r0, [r0]
    ldrh    r1, [r3, #14]
    movw    r2, #0xffff
    cmp     r1, r2
    bne     6f
    strh    r0, [r3, #14]               @ first block after release
    mov     r1, r0
6:  subs    r1, r0, r1
    it      mi
    rsbmi   r1, r1, #0
    cmp     r1, #T_PICKUP
    ble     7f
    movs    r0, #0                      @ moved away: back to continuous
    strb    r0, [r3, #7]
    b       9f
7:  ldrh    r0, [r3, #12]               @ s18 = (m[k] + 0.5) / 400
    ldrh    r0, [r4, r0, lsl #1]
    vmov    s0, r0
    vcvt.f32.s32 s0, s0
    vldr    s1, k0p5
    vadd.f32 s0, s0, s1
    vldr    s1, k1over400
    vmul.f32 s18, s0, s1
9:  vpop    {s0-s1}
    pop     {r0-r6}
    cmp     r0, #199                    @ replaced instructions
    ble.w   RATE_FULL
    b.w     RATE_NEXT

@ P6 (hook at 0x08027bde, after the glide coefficient is chosen).
@ While locked, glide with k = 1 so the rate lands exactly on the octave.
    .thumb_func
p6_glide:
    ldr     r0, =MOD
    ldrb    r0, [r0, #7]
    cbz     r0, 1f
    vmov.f32 s1, #1.0
    vstr    s1, [sp, #192]
1:  vldr    s1, k0p02                   @ replaced instructions
    ldr     r0, =SLIDE_PTR
    b.w     GLIDE_NEXT

    .align 2
k6400:      .float 6400.0
k0p5:       .float 0.5
k1over400:  .float 0.0025
k0p02:      .word 0x3ca3d70a
@ Lookup indices of the exact rates -2,-1,-1/2,-1/4,stop,1/4,1/2,1,2
@ in the stock bidirectional table (docs/FIRMWARE_MAP.md).
octave_m:   .hword 4, 52, 100, 148, 200, 248, 296, 344, 392
    .ltorg
