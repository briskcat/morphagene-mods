@ Module cpu_meter: CPU log on the SD card + flash prefetch (mg204).
@ Independent of the other patches; reads options_keys settings when present.
@
@ options.txt (options_keys): "pfch 1" turns the flash prefetch buffer on
@ (FLASH_ACR bit 8; stock leaves it off), "cpul 1" writes cpulog.txt.
@ Defaults: pfch 1, cpul 0. The boot code also writes FLASH_ACR 0x705 instead of 0x605
@ (module.py), so prefetch is on before the settings are read.
@
@ Audio (A1, end of every audio block, where the stock code stores the DWT
@ cycle count at 0x20021c90): applies pfch, sets DEMCR.TRCENA once so CYCCNT
@ actually counts, and accumulates one-second windows (6,000 blocks): peak and
@ mean cycles per block, blocks over 80% and over 100% of the 30,006-cycle
@ block period, and the context at the peak block (active Genes, Morph,
@ Gene Size, glided Varispeed rate, recording, tape mode, SRR). Each finished
@ window goes into a 64-entry ring. No push/pop: only registers the stock exit
@ no longer needs are used.
@
@ Main loop (M1, the end of an idle pass, where the stock loop has found no
@ pending card work and reloads the card state): at most every 10 s of audio,
@ with the card mounted, append the pending windows to cpulog.txt with the
@ firmware's own FatFs (f_open, f_lseek to the end, f_printf, f_close). This is
@ the same place in the loop as the stock options.txt rewrite (status bit 7).
@
@ State (CPU + offset): +0 magic "CPUL", +4 head, +8 tail, +12 window blocks,
@ +16 window cycle sum, +20 window peak, +24 over-80 u16, +26 over-100 u16,
@ +28 Morph u16, +30 Gene Size u16, +32 rate x1000 i32, +36 Genes u8,
@ +37 flags u8 (1 recording, 2 tape mode, 4 SRR), +40 window number,
@ +44 last block counter (reset detection), +48 windows dropped (ring full),
@ +52 block counter at the last write attempt, +56 header written u8,
@ +60 card errors, +64 last FatFs result, +68 drops already reported.
@ Ring at +0x100: 64 x 32 bytes, same field order as the window (+0 window,
@ +4 peak, +8 mean, +12 over-80, +14 over-100, +16 Morph, +18 Gene Size,
@ +20 rate, +24 Genes, +25 flags). FIL at +0xA00.

    .syntax unified
    .cpu cortex-m4
    .fpu fpv4-sp-d16
    .thumb

    .equ CPU,          0x20029000
    .equ CPU_MAGIC,    0x4c555043       @ "CPUL"
    .equ RING,         0x20029100
    .equ RING_N,       64
    .equ FIL,          0x20029A00       @ FatFs FIL (~560 B)
    .equ SETTINGS,     0x2002A0F0       @ options_keys: +7 pfch, +8 cpul
    .equ SETTINGS_MAGIC, 0x5354504f
    .equ MOD,          0x2002A000
    .equ MOD_MAGIC,    0x53484654
    .equ FLASH_ACR,    0x40023c00
    .equ DEMCR,        0xe000edfc
    .equ DWT_CTRL,     0xe0001000
    .equ BLOCKS,       0x20021394       @ +1 per audio call (.bss: 0 after reset)
    .equ MORPH_ADC,    0x20021c6c
    .equ GS_ADC,       0x20021c7c
    .equ RATE,         0x200220e0       @ glided Varispeed rate (float)
    .equ REC_ACTIVE,   0x20022108
    .equ ENVELOPES,    0x20021e64       @ Gene envelope levels, 4 active slots
    .equ CARD_OK,      0x20001290       @ 1 = card mounted (the stock loop's r6)
    .equ F_OPEN,       0x08032261
    .equ F_LSEEK,      0x08032be9
    .equ F_PRINTF,     0x08034805
    .equ F_CLOSE,      0x080327a9
    .equ AUDIO_RETURN, 0x0802866a       @ mov.w r4,#0; it gt; strgt (peak since boot)
    .equ LOOP_HEAD,    0x08022f7e
    .equ BUDGET,       30006            @ SYSCLK cycles per 8-frame block
    .equ HIGH,         24005            @ 80 % of BUDGET
    .equ WINDOW,       6000             @ blocks per log line (1.0002 s)
    .equ WRITE_EVERY,  60000            @ blocks between card writes (10 s)

    .text
    .global cpu_block, cpu_main

@ A1, replacing "str r3,[r0]; cmp r3,r7" at 0x08028666.
@ Live: r0 = 0x20021c90, r3 = cycles this block, r6 = 0x2002205c, r7 = peak
@ since boot. Free: r1, r2, r4, r5, r8-r12, lr, s0, s1.
    .thumb_func
cpu_block:
    str     r3, [r0]                    @ replaced: last = CYCCNT
    movs    r2, #1                      @ defaults without settings: pfch 1, cpul 0
    movs    r4, #0
    ldr     r1, =SETTINGS
    ldr     r5, [r1]
    ldr     r8, =SETTINGS_MAGIC
    cmp     r5, r8
    itt     eq
    ldrbeq  r2, [r1, #7]                @ pfch
    ldrbeq  r4, [r1, #8]                @ cpul
    ldr     r1, =FLASH_ACR              @ prefetch = pfch
    ldr     r5, [r1]
    mov     r8, r5
    bfi     r8, r2, #8, #1
    cmp     r8, r5
    it      ne
    strne   r8, [r1]
    cmp     r4, #0
    beq     9f
    ldr     r1, =DEMCR                  @ start CYCCNT once (no debugger needed)
    ldr     r5, [r1]
    tst     r5, #0x01000000
    bne     1f
    orr     r5, r5, #0x01000000
    str     r5, [r1]
    ldr     r1, =DWT_CTRL
    ldr     r5, [r1]
    orr     r5, r5, #1
    str     r5, [r1]
    b       9f                          @ this block's count is not valid
1:  ldr     r1, =CPU
    ldr     r8, =BLOCKS
    ldr     r8, [r8]
    ldr     r5, [r1]
    ldr     r9, =CPU_MAGIC
    cmp     r5, r9
    bne     2f
    ldr     r5, [r1, #44]
    cmp     r8, r5
    bhs     3f                          @ counter went backwards: a reset
2:  movs    r5, #0                      @ (re)initialise the state block
    movs    r10, #0
21: str     r5, [r1, r10]
    adds    r10, r10, #4
    cmp     r10, #0x100
    blo     21b
    str     r9, [r1]
3:  str     r8, [r1, #44]
    ldr     r5, [r1, #12]               @ window blocks += 1
    adds    r5, r5, #1
    str     r5, [r1, #12]
    ldr     r9, [r1, #16]               @ cycle sum
    add     r9, r9, r3
    str     r9, [r1, #16]
    ldrh    r9, [r1, #24]               @ over 80 %
    movw    r10, #HIGH
    cmp     r3, r10
    it      hi
    addhi   r9, r9, #1
    strh    r9, [r1, #24]
    ldrh    r9, [r1, #26]               @ over 100 %
    movw    r10, #BUDGET
    cmp     r3, r10
    it      hi
    addhi   r9, r9, #1
    strh    r9, [r1, #26]
    ldr     r9, [r1, #20]               @ new window peak: keep its context
    cmp     r3, r9
    bls     5f
    str     r3, [r1, #20]
    ldr     r9, =MORPH_ADC
    ldr     r9, [r9]
    strh    r9, [r1, #28]
    ldr     r9, =GS_ADC
    ldr     r9, [r9]
    strh    r9, [r1, #30]
    ldr     r9, =RATE
    vldr    s0, [r9]
    vldr    s1, k_thousand
    vmul.f32 s0, s0, s1
    vcvtr.s32.f32 s0, s0
    vstr    s0, [r1, #32]
    ldr     r9, =ENVELOPES              @ active Genes: envelope > 0
    movs    r10, #0
    movs    r11, #0
4:  vldr    s0, [r9]
    vcmpe.f32 s0, #0
    vmrs    APSR_nzcv, fpscr
    it      gt
    addgt   r10, r10, #1
    adds    r9, r9, #4
    adds    r11, r11, #1
    cmp     r11, #4
    blo     4b
    strb    r10, [r1, #36]
    movs    r10, #0                     @ flags
    ldr     r9, =REC_ACTIVE
    ldr     r9, [r9]
    cmp     r9, #0
    it      ne
    orrne   r10, r10, #1
    ldr     r9, =MOD
    ldr     r11, [r9]
    ldr     r12, =MOD_MAGIC
    cmp     r11, r12
    bne     41f
    ldrb    r11, [r9, #16]              @ tape mode on
    cmp     r11, #0
    it      ne
    orrne   r10, r10, #2
    ldrb    r11, [r9, #95]              @ SRR active
    cmp     r11, #0
    it      ne
    orrne   r10, r10, #4
41: strb    r10, [r1, #37]
5:  movw    r9, #WINDOW
    cmp     r5, r9
    blo     9f
    ldr     r9, [r1, #4]                @ window complete: push to the ring
    ldr     r10, [r1, #8]
    sub     r11, r9, r10
    cmp     r11, #RING_N
    bhs     6f
    and     r11, r9, #(RING_N - 1)
    ldr     r12, =RING
    add     r12, r12, r11, lsl #5
    ldr     r10, [r1, #40]
    str     r10, [r12]
    ldr     r10, [r1, #20]
    str     r10, [r12, #4]
    ldr     r10, [r1, #16]
    udiv    r10, r10, r5
    str     r10, [r12, #8]
    ldr     r10, [r1, #24]              @ over-80 | over-100
    str     r10, [r12, #12]
    ldr     r10, [r1, #28]              @ Morph | Gene Size
    str     r10, [r12, #16]
    ldr     r10, [r1, #32]
    str     r10, [r12, #20]
    ldrh    r10, [r1, #36]              @ Genes | flags
    strh    r10, [r12, #24]
    dmb
    adds    r9, r9, #1
    str     r9, [r1, #4]
    b       7f
6:  ldr     r9, [r1, #48]               @ ring full (card not written): drop
    adds    r9, r9, #1
    str     r9, [r1, #48]
7:  ldr     r9, [r1, #40]
    adds    r9, r9, #1
    str     r9, [r1, #40]
    movs    r9, #0
    str     r9, [r1, #12]
    str     r9, [r1, #16]
    str     r9, [r1, #20]
    str     r9, [r1, #24]
9:  cmp     r3, r7                      @ replaced
    b.w     AUDIO_RETURN

    .align 2
k_thousand: .float 1000.0

@ M1, replacing "ldr r6,=CARD_OK; ldr r6,[r6]" at 0x08023eec (then b.w LOOP_HEAD).
    .thumb_func
cpu_main:
    push    {r0-r12, lr}
    vpush   {s0-s15}
    sub     sp, sp, #48                 @ f_printf stack arguments (8-byte aligned)
    ldr     r0, =CARD_OK
    ldr     r0, [r0]
    cmp     r0, #1
    bne     90f
    ldr     r1, =SETTINGS               @ cpul (default 0) and pfch for the header
    ldr     r0, [r1]
    ldr     r2, =SETTINGS_MAGIC
    movs    r8, #0
    movs    r9, #1
    cmp     r0, r2
    itt     eq
    ldrbeq  r8, [r1, #8]
    ldrbeq  r9, [r1, #7]
    cmp     r8, #0
    beq     90f
    ldr     r4, =CPU
    ldr     r0, [r4]
    ldr     r1, =CPU_MAGIC
    cmp     r0, r1
    bne     90f
    ldr     r0, [r4, #4]                @ anything pending?
    ldr     r1, [r4, #8]
    cmp     r0, r1
    beq     90f
    ldr     r0, =BLOCKS                 @ at most every WRITE_EVERY blocks
    ldr     r0, [r0]
    ldr     r1, [r4, #52]
    subs    r1, r0, r1
    ldr     r2, =WRITE_EVERY
    cmp     r1, r2
    blo     90f
    str     r0, [r4, #52]
    ldr     r0, =FIL                    @ f_open(FA_WRITE | FA_OPEN_ALWAYS)
    ldr     r1, =name
    movs    r2, #0x12
    ldr     r3, =F_OPEN
    blx     r3
    cbz     r0, 10f
    str     r0, [r4, #64]
    b       80f
10: ldr     r0, =FIL                    @ append: f_lseek(fil, fil->fsize)
    ldr     r1, [r0, #12]
    ldr     r3, =F_LSEEK
    blx     r3
    cbz     r0, 11f
    str     r0, [r4, #64]
    ldr     r0, [r4, #60]
    adds    r0, r0, #1
    str     r0, [r4, #60]
    b       70f
11: ldrb    r0, [r4, #56]               @ session header, once per power-up
    cbnz    r0, 12f
    ldr     r0, =FIL
    ldr     r1, =fmt_header
    mov     r2, r9
    ldr     r3, =F_PRINTF
    blx     r3
    movs    r0, #1
    strb    r0, [r4, #56]
12: ldr     r2, [r4, #48]               @ windows dropped since the last report
    ldr     r0, [r4, #68]
    subs    r2, r2, r0
    beq     20f
    ldr     r0, [r4, #48]
    str     r0, [r4, #68]
    ldr     r0, =FIL
    ldr     r1, =fmt_drop
    ldr     r3, =F_PRINTF
    blx     r3
20: ldr     r5, [r4, #8]                @ one line per pending window
    ldr     r0, [r4, #4]
    cmp     r5, r0
    beq     70f
    and     r0, r5, #(RING_N - 1)
    ldr     r7, =RING
    add     r7, r7, r0, lsl #5
    ldr     r0, [r7, #8]                @ mean
    str     r0, [sp, #0]
    ldrh    r0, [r7, #12]               @ over 80
    str     r0, [sp, #4]
    ldrh    r0, [r7, #14]               @ over 100
    str     r0, [sp, #8]
    ldrb    r0, [r7, #24]               @ Genes
    str     r0, [sp, #12]
    ldrh    r0, [r7, #16]               @ Morph
    str     r0, [sp, #16]
    ldrh    r0, [r7, #18]               @ Gene Size
    str     r0, [sp, #20]
    ldr     r0, [r7, #20]               @ rate x1000
    str     r0, [sp, #24]
    ldrb    r1, [r7, #25]
    and     r0, r1, #1                  @ recording
    str     r0, [sp, #28]
    ubfx    r0, r1, #1, #1              @ tape mode
    str     r0, [sp, #32]
    ubfx    r0, r1, #2, #1              @ SRR
    str     r0, [sp, #36]
    ldr     r2, [r7]                    @ window number (seconds)
    ldr     r3, [r7, #4]                @ peak
    ldr     r0, =FIL
    ldr     r1, =fmt_line
    ldr     r6, =F_PRINTF
    blx     r6
    adds    r5, r5, #1
    str     r5, [r4, #8]
    b       20b
70: ldr     r0, =FIL
    ldr     r3, =F_CLOSE
    blx     r3
    b       90f
80: ldr     r0, [r4, #60]               @ open failed: retry in 10 s
    adds    r0, r0, #1
    str     r0, [r4, #60]
90: add     sp, sp, #48
    vpop    {s0-s15}
    pop     {r0-r12, lr}
    ldr     r6, =CARD_OK                @ replaced
    ldr     r6, [r6]
    b.w     LOOP_HEAD

    .align 2
name:       .asciz "cpulog.txt"
    .align 2
fmt_header: .asciz "//Morphagene Study CPU log, new session. prefetch %d. One line per second of audio.\n//Budget: 30006 cycles per 8-frame audio block. over80/over100: blocks above 80 and 100 percent of it.\n//Context at the peak block: active Genes, Morph and Gene Size readings (0-4095), Varispeed rate x1000, recording, tape mode, SRR.\n//sec peak mean over80 over100 genes morph gsize rate rec tape srr\n"
    .align 2
fmt_drop:   .asciz "//%u seconds not logged (card busy or missing)\n"
    .align 2
fmt_line:   .asciz "%u %u %u %u %u %u %u %u %d %u %u %u\n"
    .ltorg
