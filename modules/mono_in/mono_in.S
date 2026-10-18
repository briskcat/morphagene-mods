@ Module mono_in: mono input (mg204).
@ Requires options_keys (the mono key, SETTINGS +7) and sd_updater (default 0).
@
@ The audio block (0x08027518) is called from the RX DMA interrupt with
@ r0 = the RX half just filled (interleaved int16 L, R), r1 = the TX half,
@ r2 = number of int16 values (16: 8 frames). Dry monitoring and recording
@ both read the input from this buffer only. With mono 1, each frame's L
@ sample is copied over its R sample before the block reads them.
@ mono 2 (diagnostic) copies the other way: slot 1 over slot 0, to test the
@ board's channel order on hardware.
@ Hook: replaces the entry push; r4-r7 are reloaded by the stock code before
@ use, so they are free after the push.

    .syntax unified
    .cpu cortex-m4
    .thumb

    .equ SETTINGS,       0x2002A0F0     @ options_keys: +7 mono
    .equ SETTINGS_MAGIC, 0x5354504f
    .equ BLOCK_STOCK,    0x0802751c     @ after the replaced push

    .text
    .global mono_block

    .thumb_func
mono_block:
    push    {r4-r11, lr}                @ replaced instruction
    ldr     r4, =SETTINGS
    ldr     r5, [r4]
    ldr     r6, =SETTINGS_MAGIC
    cmp     r5, r6
    bne     2f
    ldrb    r5, [r4, #7]
    cmp     r5, #1
    beq     3f
    cmp     r5, #2
    bne     2f
    mov     r4, r0                      @ mono 2 (diagnostic): second slot
    add     r5, r0, r2, lsl #1          @ onto the first, in case the board's
    b       5f                          @ L jack arrives in slot 1
4:  ldrh    r6, [r4, #2]
    strh    r6, [r4], #4
5:  cmp     r4, r5
    blo     4b
    b       2f
3:  mov     r4, r0                      @ frame pointer
    add     r5, r0, r2, lsl #1          @ end of the half
    b       1f
0:  ldrh    r6, [r4], #4                @ L
    strh    r6, [r4, #-2]               @ -> R
1:  cmp     r4, r5
    blo     0b
2:  b.w     BLOCK_STOCK
    .ltorg
