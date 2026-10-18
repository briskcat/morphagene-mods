@ Module mono_in: mono input (mg204).
@ Requires options_keys (the mono key, SETTINGS +7) and sd_updater (default 0).
@
@ The audio block (0x08027518) is called from the RX DMA interrupt with
@ r0 = the RX half just filled (interleaved int16 L, R), r1 = the TX half,
@ r2 = number of int16 values (16: 8 frames), r3 = which half (not read).
@ Dry monitoring and recording both read the input from this buffer only, so
@ rewriting R here changes both.
@   mono 1: each frame's L sample is copied over its R sample.
@   mono 2 (auto): the same, but only while R in is quiet. The firmware reads
@     no jack-detect line for R in, so "unpatched" means: every R sample has
@     stayed below THRESHOLD for HOLD blocks. One louder R sample switches
@     back to stereo at once. Each change is a crossfade of R towards L,
@     STEP per frame (512 frames, about 11 ms); at full gain R = L exactly.
@ Hook: replaces the entry push; r4-r11 are saved by it and restored by the
@ stock epilogue, so they are free here. r0-r3 are left as they were.

    .syntax unified
    .cpu cortex-m4
    .thumb

    .equ SETTINGS,       0x2002A0F0     @ options_keys: +7 mono
    .equ SETTINGS_MAGIC, 0x5354504f
    .equ BLOCK_STOCK,    0x0802751c     @ after the replaced push
    .equ STATE,          0x2002A608     @ +0 quiet blocks (u32), +4 gain (u32, 0-FULL)
    .equ THRESHOLD,      128            @ |R| below this counts as quiet (about -48 dBFS)
    .equ HOLD,           3000           @ quiet blocks before going mono (0.5 s)
    .equ FULL,           32768          @ gain for R = L
    .equ STEP,           64             @ gain change per frame

    .text
    .global mono_block

    .thumb_func
mono_block:
    push    {r4-r11, lr}                @ replaced instruction
    ldr     r4, =SETTINGS
    ldr     r5, [r4]
    ldr     r6, =SETTINGS_MAGIC
    cmp     r5, r6
    bne     9f
    ldrb    r5, [r4, #7]
    ldr     r4, =STATE
    cmp     r5, #1
    beq     1f
    cmp     r5, #2
    beq     2f
    movs    r5, #0                      @ off: auto starts from stereo
    str     r5, [r4]
    str     r5, [r4, #4]
    b       9f

1:  mov     r6, r0                      @ mono 1: copy L over R
    add     r7, r0, r2, lsl #1
    b       11f
10: ldrh    r8, [r6], #4
    strh    r8, [r6, #-2]
11: cmp     r6, r7
    blo     10b
    b       9f

2:  add     r7, r0, r2, lsl #1          @ auto: peak |R| in this half
    adds    r6, r0, #2
    movs    r5, #0
    b       21f
20: ldrsh   r8, [r6], #4
    cmp     r8, #0
    it      lt
    neglt   r8, r8
    cmp     r8, r5
    it      gt
    movgt   r5, r8
21: cmp     r6, r7
    blo     20b
    ldr     r8, [r4]                    @ quiet blocks (RAM is not cleared at
    ldr     r6, =HOLD                   @ boot: out of range counts as 0)
    cmp     r8, r6
    it      hi
    movhi   r8, #0
    cmp     r5, #THRESHOLD
    ite     hs
    movhs   r8, #0                      @ signal on R: stereo
    addlo   r8, r8, #1
    cmp     r8, r6
    it      hi
    movhi   r8, r6
    str     r8, [r4]
    ite     hs                          @ flags of cmp r8, HOLD
    movhs   r9, #FULL
    movlo   r9, #0
    ldr     r10, [r4, #4]               @ gain, kept on the STEP grid
    bic     r10, r10, #(STEP - 1)
    cmp     r10, #FULL
    it      hi
    movhi   r10, #0
    orrs    r5, r9, r10                 @ stereo and settled: nothing to do
    beq     29f
    mov     r6, r0
    b       23f
22: cmp     r10, r9                     @ step the gain towards the target
    it      lo
    addlo   r10, r10, #STEP
    it      hi
    subhi   r10, r10, #STEP
    ldrsh   r8, [r6]                    @ R += (L - R) * gain / FULL
    ldrsh   r11, [r6, #2]
    sub     r8, r8, r11
    mul     r8, r8, r10
    add     r11, r11, r8, asr #15
    strh    r11, [r6, #2]
    adds    r6, r6, #4
23: cmp     r6, r7
    blo     22b
29: str     r10, [r4, #4]
9:  b.w     BLOCK_STOCK
    .ltorg
