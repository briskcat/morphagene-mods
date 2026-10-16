@ Module options_keys: mod settings in options.txt (mg204).
@ Requires sd_updater (it resets the settings block to defaults every boot).
@
@ Keys (first four characters, single digit at position 5, like stock keys):
@   tape 0|1   SHIFT+S.O.S.: 0 classic TLA feedback, 1 tape mode (default 1)
@   octl 0|1   SHIFT+Varispeed octave lock: 0 off, 1 on (default 1)
@   fxsl 0-2   SHIFT+Morph effect: 0 off, 1 SRR, 2 warble (default 1)
@   pfch 0|1   flash prefetch: 0 off (stock), 1 on (default 1; cpu_meter)
@   cpul 0|1   CPU log cpulog.txt: 0 off, 1 on (default 0; cpu_meter)
@   mcap 0-9   Morph cap while tape-dubbing: 0 none, 1-9 = 0.1-0.9 (default 3)
@   sldm 0|1   Turing mode: 0 off, 1 on (default 0; modules/gene_shape)
@   root 0-100 Turing: chance (percent) that a step plays the root, not a chord
@              ratio (default 50)
@   tlen 1-16  Turing loop length in steps (default 8)
@   ingn 0-3   input gain (REC held + SHIFT taps), saved across power cycles
@              (default 0 = stock)
@ Parser hook: the stock loop reads each line into fp and dispatches on the
@ key at 0x08023326; ours is checked first. Writer hook: the firmware recreates
@ options.txt (stock keys + comments) after parsing; we append our keys before
@ its final f_close, so they persist and are documented in the file.
@ Settings block (SETTINGS): +0 magic "OPTS", +4 tape, +5 octl, +6 fxsl,
@ +7 pfch, +8 cpul, +9 mcap, +10 sldm, +11 root, +12 tlen, +13 ingn (the
@ saved gain), +14 applied at boot (0/1), +15 pending gain + 1 (0 = none).
@
@ Main-loop hook (opt_main, 0x08023ee6): the request dispatcher's test of
@ flag 0x80 (rewrite options.txt), reached only when no other card request is
@ pending. The first pass applies ingn to the codec. After that, a gain
@ changed with REC + SHIFT and left alone for SETTLE blocks, with no
@ recording and the card mounted, is copied to ingn and flag 0x80 is set,
@ so the stock writer rewrites options.txt (as it does after a reel load).

    .syntax unified
    .cpu cortex-m4
    .thumb

    .equ SETTINGS,       0x2002A0F0
    .equ SETTINGS_MAGIC, 0x5354504f
    .equ F_PRINTF,       0x08034805
    .equ F_CLOSE,        0x080327a9
    .equ PARSE_NEXT,     0x080232fc     @ loop head: read the next line
    .equ PARSE_STOCK,    0x0802332a     @ after the replaced instruction
    .equ WRITE_RETURN,   0x08024566
    .equ KEY_TAPE,       0x65706174     @ "tape" as a little-endian word
    .equ KEY_OCTL,       0x6c74636f     @ "octl"
    .equ KEY_FXSL,       0x6c737866     @ "fxsl"
    .equ KEY_PFCH,       0x68636670     @ "pfch"
    .equ KEY_CPUL,       0x6c757063     @ "cpul"
    .equ KEY_MCAP,       0x7061636d     @ "mcap"
    .equ KEY_SLDM,       0x6d646c73     @ "sldm"
    .equ KEY_ROOT,       0x746f6f72     @ "root"
    .equ KEY_TLEN,       0x6e656c74     @ "tlen"
    .equ KEY_INGN,       0x6e676e69     @ "ingn"
    .equ GAIN,           0x20001068     @ stock input-gain index 0-3
    .equ SET_GAIN,       0x080257dd     @ stock: codec line-in volume = 0x13 + 4 * gain
    .equ FLAGS,          0x20022074     @ main-loop request flags; 0x80 = rewrite options.txt
    .equ CARD_OK,        0x20001290     @ 1 = card mounted
    .equ REC_ACTIVE,     0x20022108
    .equ BLOCKS,         0x20021394     @ +1 per audio block (6000 per second)
    .equ STAMP,          0x2002A600     @ BLOCKS when the pending gain was first seen
    .equ SETTLE,         18000          @ 3 s without a gain change before saving
    .equ WRITE_OPTIONS,  0x080241e6     @ stock: flag 0x80 set
    .equ LOOP_IDLE,      0x08023eec     @ stock: flag 0x80 clear (cpu_meter's M1)

    .text
    .global opt_parse, opt_write, opt_main

@ Live: fp = line buffer, r9 = line number, sl = fp[0]. Free: r0-r3, ip, lr.
    .thumb_func
opt_parse:
    ldrb    r0, [fp]                    @ key bytes (buffer may be unaligned)
    ldrb    r1, [fp, #1]
    orr     r0, r0, r1, lsl #8
    ldrb    r1, [fp, #2]
    orr     r0, r0, r1, lsl #16
    ldrb    r1, [fp, #3]
    orr     r0, r0, r1, lsl #24
    ldr     r2, =SETTINGS
    ldr     r1, =KEY_TAPE
    cmp     r0, r1
    beq     1f
    ldr     r1, =KEY_OCTL
    cmp     r0, r1
    beq     2f
    ldr     r1, =KEY_FXSL
    cmp     r0, r1
    beq     5f
    ldr     r1, =KEY_PFCH
    cmp     r0, r1
    beq     6f
    ldr     r1, =KEY_CPUL
    cmp     r0, r1
    beq     7f
    ldr     r1, =KEY_MCAP
    cmp     r0, r1
    beq     8f
    ldr     r1, =KEY_SLDM
    cmp     r0, r1
    beq     10f
    ldr     r1, =KEY_ROOT
    cmp     r0, r1
    beq     11f
    ldr     r1, =KEY_TLEN
    cmp     r0, r1
    beq     12f
    ldr     r1, =KEY_INGN
    cmp     r0, r1
    beq     17f
    ldrb.w  ip, [fp, #1]                @ replaced instruction: stock keys
    b.w     PARSE_STOCK
8:  adds    r2, r2, #9                  @ mcap -> +9, digits 0-9
    movs    r3, #9
    b       9f
10: adds    r2, r2, #10                 @ sldm -> +10
    b       3f
1:  adds    r2, r2, #4                  @ tape -> +4
    b       3f
2:  adds    r2, r2, #5                  @ octl -> +5
    b       3f
5:  adds    r2, r2, #6                  @ fxsl -> +6, digits 0-2
    movs    r3, #2
    b       9f
6:  adds    r2, r2, #7                  @ pfch -> +7
    b       3f
7:  adds    r2, r2, #8                  @ cpul -> +8
    b       3f
17: adds    r2, r2, #13                 @ ingn -> +13, digits 0-3
    movs    r3, #3
    b       9f
3:  movs    r3, #1                      @ on/off keys: only 0 or 1 accepted
9:  ldrb    r1, [fp, #5]
    subs    r1, r1, #'0'
    cmp     r1, r3
    bhi     4f
    strb    r1, [r2]
4:  b.w     PARSE_NEXT
11: adds    r2, r2, #11                 @ root -> +11, 0-100
    movs    r3, #100
    b       13f
12: adds    r2, r2, #12                 @ tlen -> +12, 1-16
    movs    r3, #16
13: movs    r0, #0                      @ decimal value of up to four digits
    mov     ip, #5
14: ldrb    r1, [fp, ip]
    subs    r1, r1, #'0'
    cmp     r1, #9
    bhi     15f
    add     r0, r0, r0, lsl #2
    add     r0, r1, r0, lsl #1
    add     ip, ip, #1
    cmp     ip, #9
    blo     14b
15: cmp     ip, #5                      @ no digits
    beq     4b
    cmp     r0, r3
    bhi     4b
    cmp     r3, #16                     @ tlen 0 is not a length
    bne     16f
    cmp     r0, #0
    beq     4b
16: strb    r0, [r2]
    b       4b

@ Writer: r0 is free; the FIL is at sp + 1396 (as the stock code computes).
    .thumb_func
opt_write:
    ldr     r3, =SETTINGS
    ldr     r2, [r3]
    ldr     r1, =SETTINGS_MAGIC
    cmp     r2, r1
    ite     eq
    ldrbeq  r2, [r3, #4]
    movne   r2, #1
    addw    r0, sp, #1396
    ldr     r1, =fmt_tape
    ldr     r3, =F_PRINTF
    blx     r3
    ldr     r3, =SETTINGS
    ldr     r2, [r3]
    ldr     r1, =SETTINGS_MAGIC
    cmp     r2, r1
    ite     eq
    ldrbeq  r2, [r3, #5]
    movne   r2, #1
    addw    r0, sp, #1396
    ldr     r1, =fmt_octl
    ldr     r3, =F_PRINTF
    blx     r3
    ldr     r3, =SETTINGS
    ldr     r2, [r3]
    ldr     r1, =SETTINGS_MAGIC
    cmp     r2, r1
    ite     eq
    ldrbeq  r2, [r3, #6]
    movne   r2, #1
    addw    r0, sp, #1396
    ldr     r1, =fmt_fxsl
    ldr     r3, =F_PRINTF
    blx     r3
    ldr     r3, =SETTINGS
    ldr     r2, [r3]
    ldr     r1, =SETTINGS_MAGIC
    cmp     r2, r1
    ite     eq
    ldrbeq  r2, [r3, #7]
    movne   r2, #1
    addw    r0, sp, #1396
    ldr     r1, =fmt_pfch
    ldr     r3, =F_PRINTF
    blx     r3
    ldr     r3, =SETTINGS
    ldr     r2, [r3]
    ldr     r1, =SETTINGS_MAGIC
    cmp     r2, r1
    ite     eq
    ldrbeq  r2, [r3, #8]
    movne   r2, #0                      @ cpul default 0
    addw    r0, sp, #1396
    ldr     r1, =fmt_cpul
    ldr     r3, =F_PRINTF
    blx     r3
    ldr     r3, =SETTINGS
    ldr     r2, [r3]
    ldr     r1, =SETTINGS_MAGIC
    cmp     r2, r1
    ite     eq
    ldrbeq  r2, [r3, #9]
    movne   r2, #3
    addw    r0, sp, #1396
    ldr     r1, =fmt_mcap
    ldr     r3, =F_PRINTF
    blx     r3
    ldr     r3, =SETTINGS
    ldr     r2, [r3]
    ldr     r1, =SETTINGS_MAGIC
    cmp     r2, r1
    ite     eq
    ldrbeq  r2, [r3, #10]
    movne   r2, #0
    addw    r0, sp, #1396
    ldr     r1, =fmt_sldm
    ldr     r3, =F_PRINTF
    blx     r3
    ldr     r3, =SETTINGS
    ldr     r2, [r3]
    ldr     r1, =SETTINGS_MAGIC
    cmp     r2, r1
    ite     eq
    ldrbeq  r2, [r3, #11]
    movne   r2, #50
    addw    r0, sp, #1396
    ldr     r1, =fmt_root
    ldr     r3, =F_PRINTF
    blx     r3
    ldr     r3, =SETTINGS
    ldr     r2, [r3]
    ldr     r1, =SETTINGS_MAGIC
    cmp     r2, r1
    ite     eq
    ldrbeq  r2, [r3, #12]
    movne   r2, #8
    addw    r0, sp, #1396
    ldr     r1, =fmt_tlen
    ldr     r3, =F_PRINTF
    blx     r3
    ldr     r2, =GAIN                   @ the live gain, so every rewrite keeps it
    ldr     r2, [r2]
    addw    r0, sp, #1396
    ldr     r1, =fmt_ingn
    ldr     r3, =F_PRINTF
    blx     r3
    addw    r0, sp, #1396               @ replaced: f_close(options.txt)
    ldr     r3, =F_CLOSE
    blx     r3
    b.w     WRITE_RETURN

@ Main loop, replacing "lsls r1,r5,#24; bmi.w WRITE_OPTIONS" at 0x08023ee6.
@ Live: r5 = request flags as loaded, r6 = card state, r7 = &FLAGS; r1 is
@ free (the replaced lsls writes it). Everything else is preserved.
    .thumb_func
opt_main:
    push    {r0-r4, r6-r12, lr}         @ 13 words; + 4 keeps sp 8-byte aligned
    sub     sp, sp, #4
    ldr     r4, =SETTINGS
    ldr     r0, [r4]
    ldr     r1, =SETTINGS_MAGIC
    cmp     r0, r1
    bne     90f
    ldr     r6, =GAIN
    ldrb    r0, [r4, #14]
    cbnz    r0, 20f
    movs    r0, #1                      @ first pass: apply the saved gain once
    strb    r0, [r4, #14]
    ldrb    r0, [r4, #13]
    ldr     r1, [r6]
    cmp     r0, r1
    beq     90f
    str     r0, [r6]
    ldr     r3, =SET_GAIN
    blx     r3
    b       90f
20: ldr     r0, [r6]                    @ later passes: watch for a change
    ldrb    r1, [r4, #13]
    cmp     r0, r1
    bne     30f
    movs    r1, #0                      @ back to the saved value: nothing pending
    strb    r1, [r4, #15]
    b       90f
30: ldr     r3, =BLOCKS
    ldr     r3, [r3]
    ldr     r2, =STAMP
    adds    r1, r0, #1
    ldrb    r12, [r4, #15]
    cmp     r12, r1
    beq     31f
    strb    r1, [r4, #15]               @ new pending value: restart the wait
    str     r3, [r2]
    b       90f
31: ldr     r1, [r2]
    subs    r1, r3, r1
    ldr     r2, =SETTLE
    cmp     r1, r2
    blo     90f
    ldr     r1, =REC_ACTIVE             @ never while recording
    ldr     r1, [r1]
    cbnz    r1, 90f
    ldr     r1, =CARD_OK
    ldr     r1, [r1]
    cmp     r1, #1
    bne     90f
    strb    r0, [r4, #13]               @ saved: ingn = gain
    movs    r1, #0
    strb    r1, [r4, #15]
    mrs     r2, primask                 @ request the rewrite (the timer ISR also
    cpsid   i                           @ sets bits in FLAGS)
    ldr     r1, =FLAGS
    ldr     r0, [r1]
    orr     r0, r0, #0x80
    str     r0, [r1]
    msr     primask, r2
90: add     sp, sp, #4
    pop     {r0-r4, r6-r12, lr}
    ldr     r1, =FLAGS                  @ pick up our request in this pass
    ldr     r1, [r1]
    tst     r1, #0x80
    it      ne
    orrne   r5, r5, #0x80
    lsls    r1, r5, #24                 @ replaced: flag 0x80 -> stock writer
    bpl     91f
    b.w     WRITE_OPTIONS
91: b.w     LOOP_IDLE
    .ltorg

    .align 2
fmt_tape: .asciz "//\n//Morphagene Study mods\ntape %d //SHIFT+S.O.S.: 0 classic TLA feedback (input + feedback x Gene playback), 1 tape mode (Varispeed tape head in the Slide/Gene Size window)\n"
    .align 2
fmt_octl: .asciz "octl %d //SHIFT+Varispeed: 0 normal, 1 exact octave lock\n"
    .align 2
fmt_fxsl: .asciz "fxsl %d //SHIFT+Morph effect: 0 off (Morph stays stock), 1 SRR (sample-rate reduction), 2 warble (tape wow and flutter on the Gene playback)\n//SHIFT+Slide: Gene start jitter amount (left = off)\n"
    .align 2
fmt_pfch: .asciz "pfch %d //Flash prefetch: 0 off (stock), 1 on (faster code from flash)\n"
    .align 2
fmt_cpul: .asciz "cpul %d //CPU log: 0 off, 1 on (cpulog.txt, one line per second, written every 10 s)\n"
    .align 2
fmt_mcap: .asciz "mcap %d //Morph cap while tape-dubbing: 0 none, 1-9 = Morph limited to 0.1-0.9 (CPU safety; 3 = 0.3)\n"
    .align 2
fmt_sldm: .asciz "sldm %d //Turing mode: 0 off, 1 on: a loop of random seeds decides each Gene's chord ratio, scatter and stereo. SHIFT+Organize = evolution (left = locked loop, right = normal randomness), SHIFT+Gene Size = Genes per step (1-16), SHIFT+Slide = spread (start jitter, repeats when locked)\n"
    .align 2
fmt_root: .asciz "root %d //Turing: chance in percent that a step plays the root rather than a chord ratio (mcr1-mcr3)\n"
    .align 2
fmt_tlen: .asciz "tlen %d //Turing loop length in steps, 1-16\n"
    .align 2
fmt_ingn: .asciz "ingn %d //Input gain 0-3 (REC held + SHIFT taps); saved automatically a few seconds after a change\n"
    .ltorg
