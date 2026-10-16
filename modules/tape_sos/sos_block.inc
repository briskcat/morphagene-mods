@ Shared per-block S.O.S. hook (P7) for tape_sos.S.
@ The including file defines the P7_EXTRA macro (runs with r0-r3, s0-s1 free,
@ r3 = MOD, just before the hook returns) and the k_scale/k_top/k_offset
@ constants plus MOD, MAGIC, T_PICKUP and P7_RETURN.

@ P7 (hook at 0x080276c4, once per audio block). r1 = &0x20021c68; r5 is
@ the S.O.S. reading the stock code converts into the listening coefficient.
    .thumb_func
p7_sos_block:
    ldr     r5, [r1]                    @ replaced: S.O.S. reading
    push    {r0-r3}
    vpush   {s0-s1}
    ldr     r3, =MOD
    ldr     r0, [r3]
    ldr     r2, =MAGIC
    cmp     r0, r2
    bne     9f
    ldrb    r0, [r3, #6]                @ editing S.O.S. with SHIFT?
    cmp     r0, #1
    bne     5f
    ldrb    r0, [r3, #5]
    cbz     r0, 5f
    ldrb    r0, [r3, #4]
    cbz     r0, 5f
    vmov    s0, r5                      @ f = stock S.O.S. law(live reading)
    vcvt.f32.s32 s0, s0
    vldr    s1, k_scale
    vmul.f32 s0, s0, s1
    vldr    s1, k_top
    vcmpe.f32 s0, s1
    vmrs    APSR_nzcv, fpscr
    ble     1f
    vmov.f32 s0, #1.0
    b       2f
1:  vldr    s1, k_offset
    vsub.f32 s0, s0, s1
    vcmpe.f32 s0, #0
    vmrs    APSR_nzcv, fpscr
    bge     2f
    vsub.f32 s0, s0, s0
2:  vstr    s0, [r3, #20]
    movs    r0, #1
    strb    r0, [r3, #16]
    ldrb    r0, [r3, #17]
    cbnz    r0, 3f
    ldrh    r0, [r3, #8]                @ pre-edit knob position (session snapshot)
    strh    r0, [r3, #18]
    movs    r0, #1
    strb    r0, [r3, #17]
3:  ldrh    r5, [r3, #18]               @ listening mix stays where it was
    b       9f
5:  ldrb    r0, [r3, #17]               @ pickup pending?
    cbz     r0, 9f
    ldrh    r0, [r3, #18]
    subs    r0, r5, r0
    it      mi
    rsbmi   r0, r0, #0
    cmp     r0, #T_PICKUP
    ble     6f
    ldrh    r5, [r3, #18]
    b       9f
6:  movs    r0, #0                      @ knob is back: follow it again
    strb    r0, [r3, #17]
9:  P7_EXTRA
    vpop    {s0-s1}
    pop     {r0-r3}
    vldr    s1, k_top                   @ replaced: vldr s1, =1.04884
    b.w     P7_RETURN

