@ Module gene_shape: Slide jitter and Turing mode (mg204).
@ Requires shift_gestures (shift_gestures.S: SHIFT session, owners 4, 5 and 6, snapshots).
@
@ SHIFT + Slide sets a jitter amount: each new Gene starts at its stock start
@ (Slide, plus the stock Morph jitter) plus a uniform random offset of up to
@ +/- amount/2 of the splice, wrapped inside the splice. Knob left = off.
@ amount = (knob position)^2. Applied in both paths' birth code, so it costs
@ nothing between births.
@
@ Both knobs hold their pre-edit value during the edit and until they come back
@ within T_PICKUP counts (like Morph after SHIFT + Morph).
@
@ Turing mode (options.txt "sldm 1", README.md): a loop of seeds decides each
@ Gene's random choices. SHIFT + Gene Size sets the pattern rate (Genes per
@ step), SHIFT + Organize sets evolution, SHIFT + Slide
@ is the jitter (spread), seeded per step when locked. Loop length (tlen) and
@ root weight (root) come from options.txt.
@
@ State (MOD + offset): +208 ref_gs u16, +210 ref_slide u16 (P1 snapshots),
@ +212 Gene Size pickup u8, +213 Slide pickup u8,
@ +216 pre-edit Gene Size u16, +218 pre-edit Slide u16,
@ +222 jitter knob u16, +224 jitter amount f, +228 RNG u32.

    .syntax unified
    .cpu cortex-m4
    .fpu fpv4-sp-d16
    .thumb

    .equ MOD,        0x2002A000
    .equ MAGIC,      0x53484654
    .equ NAVIGATION, 0x200012e0
    .equ ENVELOPES,  0x20021e64
    .equ T_PICKUP,   48
    .equ T_ZERO,     48                @ knob counts treated as fully left
    .equ T_LOCK,     96                @ Organize counts treated as locked (the
                                       @ lowest knob reading is about 56)
    .equ G2_RETURN,  0x0802780c
    .equ G3_RETURN,  0x080288f2
    .equ GS_RETURN,  0x08027978
    .equ GA_RETURN,  0x0802838e
    .equ GB_RETURN,  0x08029bbc
    .equ CA_RETURN,  0x08028494
    .equ CB_RETURN,  0x08029cb8
    .equ O1_RETURN,  0x080276f4
    .equ ORG_LAST,   0x200220ac        @ last accepted Organize reading
    .equ ORG_MAX,    0x20022078        @ stock Organize calibration maximum
    .equ ZONE_HYST,  32                @ counts past a rate zone edge before the rate changes
    .equ SETTINGS,   0x2002A0F0        @ options.txt settings; +10 sldm, +11 root, +12 tlen
    .equ SETTINGS_MAGIC, 0x5354504f
    .equ TURING,     0x2002A740        @ Turing state (MOD + 0x740, 0xC0 bytes)
    .equ TURING_MAGIC, 0x474e5254      @ "TRNG"
    .equ T_TOP,      160               @ knob counts from the top treated as fully right
    .equ SMORPH,     0x20022084        @ smoothed Morph (drives the stock scatter)
    .equ SLIDE_POS,  0x20022154        @ Slide position (float, 0..1)
    .equ GS_ADC,     0x20021c7c

    .text
    .global g2_size, g3_size, gs_slide, ga_birth, gb_birth, ca_chord, cb_chord, o1_organize

@ Gene Size reading -> effective value (pickup hold). In/out r0; keeps r1-r12.
    .thumb_func
size_hold:
    push    {r1-r3, lr}
    ldr     r3, =MOD
    ldr     r1, [r3]
    ldr     r2, =MAGIC
    cmp     r1, r2
    bne     9f
    ldrb    r1, [r3, #6]
    cmp     r1, #4
    bne     5f
    ldrb    r1, [r3, #5]
    cbz     r1, 5f
    ldrb    r1, [r3, #4]
    cbz     r1, 5f
    bl      turing_mode                 @ editing: sldm 1 = pattern rate
    cbz     r1, 7f
    bl      turing_init
    push    {r0}
    ldr     r2, =TURING
    ldrb    r1, [r2, #21]
    bl      rate_zone
    strb    r0, [r2, #21]
    ldr     r1, =rate_table
    ldrb    r0, [r1, r0]
    strb    r0, [r2, #22]
    pop     {r0}
7:  ldrb    r1, [r3, #212]
    cbnz    r1, 2f
    ldrh    r1, [r3, #208]              @ pre-edit reading (session snapshot)
    strh    r1, [r3, #216]
    movs    r1, #1
    strb    r1, [r3, #212]
2:  ldrh    r0, [r3, #216]
    b       9f
5:  ldrb    r1, [r3, #212]              @ pickup pending?
    cbz     r1, 9f
    ldrh    r1, [r3, #216]
    subs    r2, r0, r1
    it      mi
    rsbmi   r2, r2, #0
    cmp     r2, #T_PICKUP
    ble     6f
    mov     r0, r1
    b       9f
6:  movs    r1, #0                      @ knob is back: follow it again
    strb    r1, [r3, #212]
9:  pop     {r1-r3, pc}

@ r1 = 1 with options.txt "sldm 1" (Turing mode), else 0. Keeps the rest.
    .thumb_func
turing_mode:
    push    {r0, r2}
    movs    r1, #0
    ldr     r0, =SETTINGS
    ldr     r2, [r0]
    push    {r3}
    ldr     r3, =SETTINGS_MAGIC
    cmp     r2, r3
    pop     {r3}
    bne     9f
    ldrb    r2, [r0, #10]
    cmp     r2, #1
    it      eq
    moveq   r1, #1
9:  pop     {r0, r2}
    bx      lr

@ Pattern rate zone: r0 = Gene Size reading, r1 = current zone (0-7). Returns
@ r0 = zone (reading / 512), with ZONE_HYST counts of hysteresis at the edges.
@ Keeps r1-r12.
    .thumb_func
rate_zone:
    push    {r2}
    lsrs    r2, r0, #9
    cmp     r2, r1
    beq     8f
    ite     hi
    subhi   r0, r0, #ZONE_HYST          @ up: the reading must clear the edge
    addls   r0, r0, #ZONE_HYST          @ down: likewise
    lsrs    r2, r0, #9
    cmp     r2, #7
    it      hi
    movhi   r2, #7
8:  mov     r0, r2
    pop     {r2}
    bx      lr
rate_table: .byte 1, 2, 3, 4, 6, 8, 12, 16   @ Genes per step, by zone
    .align 1
    .ltorg

@ G2 (0x08027808, once per block): Gene Size reading. r0 = control base.
@ It must not cover 0x0802780c: the reel-mode override path (0x08028ad0) and the
@ G3 path (0x080288f8) branch there.
    .thumb_func
g2_size:
    ldr     r6, [r0, #12]               @ replaced
    ldr     r0, [r0, #20]
    push    {lr}
    bl      size_hold
    pop     {lr}
    b.w     G2_RETURN

@ G3 (0x080288ee, alternate path): same reading.
    .thumb_func
g3_size:
    ldr     r6, [r0, #12]               @ replaced
    ldr     r0, [r0, #20]
    push    {lr}
    bl      size_hold
    pop     {lr}
    b.w     G3_RETURN

@ GS (0x08027972, once per block): Slide reading into r2, with pickup; while
@ editing, the knob sets the jitter amount (in Turing mode the spread: the same
@ jitter, seeded per step when locked). r0, r1, r5, s2, s3 are reloaded next.
    .thumb_func
gs_slide:
    ldr     r2, [r6, #16]               @ replaced
    push    {r3}
    ldr     r5, =MOD
    ldr     r0, [r5]
    ldr     r1, =MAGIC
    cmp     r0, r1
    bne     9f
    ldrb    r0, [r5, #6]
    cmp     r0, #5
    bne     5f
    ldrb    r0, [r5, #5]
    cmp     r0, #0
    beq     5f
    ldrb    r0, [r5, #4]
    cmp     r0, #0
    beq     5f
    strh    r2, [r5, #222]              @ editing
    subs    r0, r2, #T_ZERO             @ jitter = ((k - 48) / 4000)^2
    it      mi
    movmi   r0, #0
    vmov    s2, r0                      @ s2 is reloaded by the replaced vldr
    vcvt.f32.s32 s2, s2
    vldr    s3, k_jscale                @ s3 is reloaded at 0x0802797e; s1 is live
    vmul.f32 s2, s2, s3
    vmul.f32 s2, s2, s2
    vmov.f32 s3, #1.0
    vcmpe.f32 s2, s3
    vmrs    APSR_nzcv, fpscr
    it      gt
    vmovgt.f32 s2, s3
    vstr    s2, [r5, #224]
    ldrb    r0, [r5, #213]
    cbnz    r0, 2f
    ldrh    r0, [r5, #210]              @ pre-edit reading (session snapshot)
    strh    r0, [r5, #218]
    movs    r0, #1
    strb    r0, [r5, #213]
2:  ldrh    r2, [r5, #218]
    b       9f
5:  ldrb    r0, [r5, #213]
    cbz     r0, 9f
    ldrh    r0, [r5, #218]
    subs    r1, r2, r0
    it      mi
    rsbmi   r1, r1, #0
    cmp     r1, #T_PICKUP
    ble     6f
    mov     r2, r0
    b       9f
6:  movs    r0, #0
    strb    r0, [r5, #213]
9:  pop     {r3}
    vldr    s2, k_stock_s2              @ replaced: vldr s2, [pc, #64] (0x080279b8)
    b.w     GS_RETURN

    .align 2
k_jscale:   .float 0.00025               @ 1 / 4000
k_escale:   .float 0.000260485           @ 1 / (4095 - 96 - 160)
k_10000:    .float 10000.0
k_stock_s2: .word 0x398a26fe            @ the stock literal at 0x080279b8
    .ltorg

@ Gene birth, both reconstruction paths (once per new Gene). The stock code
@ copies the origin (absolute frame, from Slide) into the start register and
@ then adds the reverse offset. We add (U - 0.5) * amount * splice length and
@ wrap inside the splice [r5, r6). r5 = splice start, r6 = splice end.
@ Turing chord: the step's chord ratio, from \reg (a 32-bit value hashed from the
@ seed). Root with probability root / 100 (options.txt root, percent), otherwise
@ mcr1-mcr3 evenly. Leaves index + 1 in TURING+20 for the chord store hooks
@ (CA/CB). r0 = TURING. Uses r1, r2.
    .macro CHORD_PICK reg
    ldr     r1, =SETTINGS
    ldrb    r1, [r1, #11]
    lsls    r1, r1, #24                 @ root * 2^24
    lsrs    r2, \reg, #8
    add     r2, r2, r2, lsl #2
    add     r2, r2, r2, lsl #2
    lsls    r2, r2, #2                  @ U * 2^24 * 100
    cmp     r2, r1
    bhs     5f
    movs    r1, #1                      @ root (index 0)
    b       6f
5:  and     r1, \reg, #0xff            @ index = 1 + (low byte * 3) / 256
    add     r1, r1, r1, lsl #1
    lsrs    r1, r1, #8
    adds    r1, r1, #2
6:  strb    r1, [r0, #20]
    .endm

    .macro BIRTH_JITTER dst, origin, ret, slot
    push    {r0-r4, lr}                 @ lr is live in the stock audio routine
    vpush   {s0-s3}                     @ not s4: path B's destination
    vmov.f32 s2, \origin
    @ --- Turing (sldm 1, evolution < 1): this step's seed decides the birth.
    ldr     r0, =SETTINGS
    ldr     r1, [r0]
    ldr     r2, =SETTINGS_MAGIC
    cmp     r1, r2
    bne     8f
    ldrb    r1, [r0, #10]
    cmp     r1, #1
    bne     8f
    bl      turing_init
    ldr     r0, =TURING
    movs    r1, #0                      @ no chord pick yet for this birth, and no
    strb    r1, [r0, #20]               @ seeded spread value
    strb    r1, [r0, #104]
    vldr    s0, [r0, #12]               @ evolution
    vmov.f32 s1, #1.0
    vcmpe.f32 s0, s1
    vmrs    APSR_nzcv, fpscr
    bge     8f                          @ fully right: stock randomness
    ldrb    r1, [r0, #8]                @ step k
    ldrb    r3, [r0, #23]               @ Genes already played on this step
    adds    r4, r3, #1                  @ pattern rate: k + 1 after `rate` Genes
    strb    r4, [r0, #23]
    ldrb    r2, [r0, #22]
    cmp     r4, r2
    blo     11f
    movs    r4, #0
    strb    r4, [r0, #23]
    adds    r4, r1, #1
    ldr     r2, =SETTINGS               @ loop length (options.txt tlen, 1-16)
    ldrb    r2, [r2, #12]
    cmp     r4, r2
    it      hs
    movhs   r4, #0
    strb    r4, [r0, #8]
11: add     r2, r0, #24
    cbnz    r3, 1f                      @ evolve on the step's first Gene only:
    bl      turing_rand                 @ replace seed k with probability e
    ldr     r3, [r0, #4]
    lsrs    r3, r3, #8
    vmov    s1, r3
    vcvt.f32.u32 s1, s1, #24
    vcmpe.f32 s1, s0
    vmrs    APSR_nzcv, fpscr
    bge     1f
    bl      turing_rand
    ldr     r3, [r0, #4]
    str     r3, [r2, r1, lsl #2]
1:  ldr     r3, [r2, r1, lsl #2]        @ seed -> the stock RNG state slot, so the
    str     r3, [sp, #(40 + \slot)]    @ birth draws (crossmix, Morph) replay
    eor     r3, r3, r3, lsl #13         @ scatter from the seed (decorrelated)
    eor     r3, r3, r3, lsr #17
    eor     r3, r3, r3, lsl #5
    mov     r4, r3                      @ chord ratio from the seed, too
    eor     r4, r4, r4, lsl #13
    eor     r4, r4, r4, lsr #17
    eor     r4, r4, r4, lsl #5
    CHORD_PICK r4
    eor     r4, r4, r4, lsl #13         @ and the spread offset (Slide jitter below)
    eor     r4, r4, r4, lsr #17
    eor     r4, r4, r4, lsl #5
    str     r4, [r0, #100]
    movs    r1, #1
    strb    r1, [r0, #104]
    ldr     r1, =SMORPH                 @ stock scatter only when Morph > 0.25 and
    vldr    s3, [r1]                    @ the Gene Size reading >= 2000
    vmov.f32 s1, #0.25
    vcmpe.f32 s3, s1
    vmrs    APSR_nzcv, fpscr
    ble     8f
    ldr     r1, =GS_ADC
    ldr     r1, [r1]
    cmp     r1, #2000
    blt     8f
    subs    r4, r6, r5                  @ splice length
    ble     8f
    lsrs    r3, r3, #8                  @ scatter = (U - 0.5) * 10000 * m^2
    vmov    s0, r3
    vcvt.f32.u32 s0, s0, #24
    vmov.f32 s1, #0.5
    vsub.f32 s0, s0, s1
    ldr     r1, =k_10000
    vldr    s1, [r1]
    vmul.f32 s0, s0, s1
    vmul.f32 s0, s0, s3
    vmul.f32 s0, s0, s3
    vmov    s1, r4                      @ origin = start + trunc(trunc(len * slide) + scatter)
    vcvt.f32.s32 s1, s1
    ldr     r1, =SLIDE_POS
    vldr    s3, [r1]                    @ (Morph no longer needed)
    vmul.f32 s1, s1, s3
    vcvt.s32.f32 s1, s1
    vcvt.f32.s32 s1, s1
    vadd.f32 s1, s1, s0
    vcvt.s32.f32 s1, s1
    vmov    r1, s1
    add     r1, r1, r5
    subs    r2, r6, #1                  @ capped at end - 1, as stock
    cmp     r1, r2
    it      gt
    movgt   r1, r2
    vmov    s2, r1
    vcvt.f32.s32 s2, s2
8:  ldr     r2, =MOD
    ldr     r0, [r2]
    ldr     r1, =MAGIC
    cmp     r0, r1
    bne     9f
    ldr     r0, [r2, #224]              @ jitter amount (0.0 = 0 bits)
    cmp     r0, #0
    beq     9f
    subs    r3, r6, r5                  @ splice length
    ble     9f
    ldr     r1, =TURING                 @ locked Turing pattern: the step's seed
    ldr     r0, [r1]                    @ gives the offset (repeats with the loop)
    ldr     r4, =TURING_MAGIC
    cmp     r0, r4
    bne     20f
    ldrb    r0, [r1, #104]
    cbz     r0, 20f
    ldr     r0, [r1, #100]
    b       21f
20: ldr     r0, [r2, #228]              @ otherwise random: xorshift32
    cbnz    r0, 1f
    ldr     r0, =0x2545f491
1:  eor     r0, r0, r0, lsl #13
    eor     r0, r0, r0, lsr #17
    eor     r0, r0, r0, lsl #5
    str     r0, [r2, #228]
21:
    lsrs    r0, r0, #8                  @ U = top 24 bits / 2^24
    vmov    s0, r0
    vcvt.f32.u32 s0, s0, #24
    vmov.f32 s1, #0.5
    vsub.f32 s0, s0, s1
    vldr    s1, [r2, #224]
    vmul.f32 s0, s0, s1
    vmov    s1, r3
    vcvt.f32.s32 s1, s1                 @ length
    vfma.f32 s2, s0, s1                 @ origin + (U - 0.5) * amount * length
    vmov    s0, r5
    vcvt.f32.s32 s0, s0                 @ start
    vcmpe.f32 s2, s0
    vmrs    APSR_nzcv, fpscr
    it      lt
    vaddlt.f32 s2, s2, s1
    vmov    s0, r6
    vcvt.f32.s32 s0, s0                 @ end
    vcmpe.f32 s2, s0
    vmrs    APSR_nzcv, fpscr
    it      ge
    vsubge.f32 s2, s2, s1
9:  vmov.f32 \dst, s2
    vpop    {s0-s3}
    pop     {r0-r4, lr}
    b.w     \ret
    .endm

@ GA (0x0802838a, path A birth): replaced vmov.f32 s30, s16.
    .thumb_func
ga_birth:
    BIRTH_JITTER s30, s16, GA_RETURN, 36   @ path A: RNG state at [sp, #36]
    .ltorg

@ GB (0x08029bb8, path B birth): replaced vmov.f32 s4, s1.
    .thumb_func
gb_birth:
    BIRTH_JITTER s4, s1, GB_RETURN, 28     @ path B: RNG state at [sp, #28]
    .ltorg

@ Turing state: initialise once (magic). Keeps every register except flags.
@ +0 magic, +4 xorshift32, +8 step u8, +12 evolution f, +20 chord pick u8
@ (index + 1, 0 = none), +21 rate zone u8, +22 pattern rate u8, +23 repeat u8,
@ +24..+87 seeds[16], +100 seeded spread value u32, +104 its valid flag u8.
    .thumb_func
turing_init:
    push    {r0-r2, lr}
    ldr     r0, =TURING
    ldr     r1, [r0]
    ldr     r2, =TURING_MAGIC
    cmp     r1, r2
    beq     9f
    str     r2, [r0]
    ldr     r1, =0x2545f491
    str     r1, [r0, #4]
    movs    r1, #0
    strb    r1, [r0, #8]
    str     r1, [r0, #20]               @ no pick, rate zone 0, repeat 0
    movs    r1, #1                      @ pattern rate 1 (a step per Gene)
    strb    r1, [r0, #22]
    mov     r1, #0x3f800000             @ evolution 1.0: stock until edited
    str     r1, [r0, #12]
    movs    r2, #0
1:  bl      turing_rand                 @ fill the seeds
    add     r1, r0, #24
    push    {r3}
    ldr     r3, [r0, #4]
    str     r3, [r1, r2, lsl #2]
    pop     {r3}
    adds    r2, r2, #1
    cmp     r2, #16
    blo     1b
9:  pop     {r0-r2, pc}

@ Advance the Turing xorshift32 (r0 = TURING); new value in [r0, #4]. Keeps registers.
    .thumb_func
turing_rand:
    push    {r1}
    ldr     r1, [r0, #4]
    eor     r1, r1, r1, lsl #13
    eor     r1, r1, r1, lsr #17
    eor     r1, r1, r1, lsl #5
    str     r1, [r0, #4]
    pop     {r1}
    bx      lr

@ CA (0x08028490, path A) / CB (0x08029cb4, path B): the birth's chord index is
@ stored per Gene (0 = base rate, 1-3 = mcr1-mcr3). A locked Turing birth
@ replaces it with the step's pick.
    .macro CHORD_STORE ptr
    push    {r2, r3}
    ldr     r2, =TURING
    ldr     r3, [r2]
    push    {r4}
    ldr     r4, =TURING_MAGIC
    cmp     r3, r4
    pop     {r4}
    bne     1f
    ldrb    r3, [r2, #20]
    cbz     r3, 1f
    subs    r7, r3, #1
    movs    r3, #0
    strb    r3, [r2, #20]
1:  pop     {r2, r3}
    str     r7, [\ptr, #4]             @ replaced
    .endm

    .thumb_func
ca_chord:
    CHORD_STORE r0
    movs    r4, #0                      @ replaced
    b.w     CA_RETURN
    .ltorg

    .thumb_func
cb_chord:
    CHORD_STORE r1
    ldr     r1, [sp, #20]               @ replaced
    b.w     CB_RETURN
    .ltorg

@ O1 (0x080276f0, audio block): the Organize reading. With sldm 1, while SHIFT is
@ down, and after a SHIFT + Organize edit until the knob comes back, the block
@ sees the last accepted Organize value (0x200220ac), so the selected splice
@ cannot move. During SHIFT + Organize (owner 6) the knob sets Turing evolution:
@ x = (k - 96) / (4095 - 96 - 160), e = x^2: exactly 0 (locked) in the bottom
@ 96 counts, exactly 1 (stock) in the top 160.
@ Replaces "ldr r0,[r4,#8]; ldr r7,=0x20022078".
    .thumb_func
o1_organize:
    ldr     r0, [r4, #8]                @ replaced: Organize reading
    push    {r1-r3}
    ldr     r1, =MOD
    ldr     r2, [r1]
    ldr     r3, =MAGIC
    cmp     r2, r3
    bne     9f
    ldr     r2, =SETTINGS
    ldr     r3, [r2]
    push    {r1}
    ldr     r1, =SETTINGS_MAGIC
    cmp     r3, r1
    pop     {r1}
    bne     9f
    ldrb    r2, [r2, #10]
    cmp     r2, #1
    bne     9f
    ldrb    r2, [r1, #4]                @ SHIFT down: hold from the press (the stock
    cbz     r2, 2f                      @ splice change needs only ~9 counts, less
    ldrb    r2, [r1, #6]                @ than the 48-count claim)
    cmp     r2, #6
    bne     3f
    ldrb    r2, [r1, #5]
    cbz     r2, 3f
    push    {lr}                        @ SHIFT + Organize: evolution
    bl      turing_init
    pop     {lr}
    vpush   {s0-s1}
    subs    r2, r0, #T_LOCK
    it      mi
    movmi   r2, #0
    vmov    s0, r2
    vcvt.f32.s32 s0, s0
    ldr     r2, =k_escale
    vldr    s1, [r2]
    vmul.f32 s0, s0, s1
    vmov.f32 s1, #1.0
    vcmpe.f32 s0, s1
    vmrs    APSR_nzcv, fpscr
    it      ge
    vmovge.f32 s0, s1
    vmul.f32 s0, s0, s0
    ldr     r2, =TURING
    vstr    s0, [r2, #12]
    vpop    {s0-s1}
3:  ldr     r2, =ORG_LAST
    ldr     r0, [r2]
    b       9f
2:  ldrb    r2, [r1, #130]              @ after an edit: hold until the knob is back
    cbz     r2, 9f                      @ within T_PICKUP
    ldr     r2, =ORG_LAST
    ldr     r2, [r2]
    subs    r3, r0, r2
    it      mi
    rsbmi   r3, r3, #0
    cmp     r3, #T_PICKUP
    bgt     5f
    movs    r3, #0
    strb    r3, [r1, #130]
    b       9f
5:  mov     r0, r2
9:  pop     {r1-r3}
    ldr     r7, =ORG_MAX                @ replaced (literal load)
    b.w     O1_RETURN
    .ltorg
