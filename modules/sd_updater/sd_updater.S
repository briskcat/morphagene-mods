@ Module sd_updater: SD-card firmware updater (mg204).
@ Design and evidence: README.md.
@
@ Hooked after the startup card mount (0x08023288). If "mgmod.bin" exists
@ (and SHIFT is held, when REQUIRE_SHIFT = 1):
@   1. read it into SDRAM (0xD0000000) with the firmware's own FatFs;
@   2. validate: size, footer "MGMD" + length + CRC32 (zlib), initial SP
@      0x20030000, reset vector odd and inside 0x08020000..0x0805FFFF;
@   3. delete any old "mgmod.ok", rename "mgmod.bin" -> "mgmod.ok"
@      (so a held SHIFT can never reflash in a loop);
@   4. copy the flasher below into SRAM and jump to it: interrupts off, erase
@      sectors 5 and 6 only, program words with an address guard, verify,
@      reset. Sectors 0-4 (bootloader, calibration) are never touched.
@ Any failure before step 4 just continues the stock boot.
@ DIAG = 1 (sd_updater.DIAG = 1 when building) leaves marker files per stage:
@   mghook.txt, mgshift.txt / mgnoshft.txt, mgopenNN.txt, mgreadNN.txt
@   (FatFs result codes), mgfailNN.txt (validation check NN), mgren_NN.txt.

    .syntax unified
    .cpu cortex-m4
    .thumb

    .equ F_OPEN,      0x08032261        @ Thumb addresses of the firmware's FatFs
    .equ F_READ,      0x080323fd
    .equ F_CLOSE,     0x080327a9
    .equ F_UNLINK,    0x080333dd
    .equ F_RENAME,    0x08033849
    .equ HOOK_RETURN, 0x0802328c        @ the stock "bl stop(3)" after our hook
    .equ SHIFT_GPIO,  0x40020810        @ GPIOC IDR, bit 1 high = SHIFT pressed
    .equ FIL,         0x2002B000        @ ~600 B FIL object (heap/stack gap)
    .equ GOT,         0x2002B3F0        @ bytes read
    .equ RAMCODE,     0x2002B400        @ flasher copy
    .equ STAGE,       0xD0000000        @ SDRAM staging (sample memory)
    .equ APP_START,   0x08020000
    .equ APP_LIMIT,   0x08060000        @ end of sector 6
    .equ MAX_IMAGE,   0x40000
    .equ FOOTER,      12
    .equ FOOTER_MAGIC, 0x444d474d       @ "MGMD"
    .ifndef REQUIRE_SHIFT
    .equ REQUIRE_SHIFT, 0               @ 1: also require SHIFT held at the mount
    .endif
    .ifndef DIAG
    .equ DIAG, 0                        @ 1: leave empty marker files per stage
    .endif
    .equ NAMEBUF,     0x2002B3C0        @ RAM copy of a marker name
    .equ MARKFIL,     0x2002B600        @ separate FIL for markers (mgmod.bin may be open)
    .equ SETTINGS,    0x2002A0F0        @ mod settings from options.txt (options_keys)
    .equ SETTINGS_MAGIC, 0x5354504f     @ "OPTS"

    .text
    .global upd_hook, flasher, flasher_end

@ Diagnostic markers: create an empty file on the card (FA_WRITE |
@ FA_CREATE_ALWAYS) and close it. MARKN puts a two-digit code into the name.
    .macro MARK name
    .if DIAG
    ldr     r0, =\name
    bl      mark_file
    .endif
    .endm
    .macro MARKN template, reg
    .if DIAG
    mov     r1, \reg
    ldr     r0, =\template
    bl      mark_code
    .endif
    .endm

    .thumb_func
upd_hook:
    push    {r0-r12, lr}
    ldr     r0, =SETTINGS               @ settings defaults for this boot: tape 1,
    ldr     r1, =SETTINGS_MAGIC         @ octl 1, fxsl 1, pfch 1, cpul 0, mcap 3, sldm 0,
    str     r1, [r0]                    @ root 50, tlen 8, ingn 0 (options.txt may override)
    ldr     r1, =0x01010101
    str     r1, [r0, #4]
    movs    r1, #0                      @ cpul 0
    strb    r1, [r0, #8]
    movs    r1, #3
    strb    r1, [r0, #9]
    movs    r1, #0                      @ sldm 0
    strb    r1, [r0, #10]
    movs    r1, #50                     @ root 50
    strb    r1, [r0, #11]
    movs    r1, #8                      @ tlen 8
    strb    r1, [r0, #12]
    movs    r1, #0                      @ ingn 0 (stock gain), not yet applied,
    strb    r1, [r0, #13]               @ nothing pending
    strh    r1, [r0, #14]
    ldr     r0, =0x2002A700             @ warble state (tape_mode, fxsl 2): start
    movs    r1, #0                      @ at rest after any reset
    str     r1, [r0]
    ldr     r0, =0x2002A740             @ Turing state (gene_shape): defaults
    str     r1, [r0]                    @ (new seeds, evolution 1) after any reset
    MARK    m_hook
    ldr     r0, =SHIFT_GPIO
    ldr     r0, [r0]
    tst     r0, #2
    beq     1f
    MARK    m_shift
    b       2f
1:  MARK    m_noshift
    .if REQUIRE_SHIFT
    b       90f
    .endif
2:  ldr     r0, =FIL
    ldr     r1, =name_bin
    movs    r2, #1                      @ FA_READ
    ldr     r4, =F_OPEN
    blx     r4
    mov     r5, r0
    MARKN   m_open, r5
    cmp     r5, #0
    bne     90f
    ldr     r0, =FIL
    ldr     r1, =STAGE
    ldr     r2, =(MAX_IMAGE + FOOTER + 4)  @ one word extra detects oversize files
    ldr     r3, =GOT
    ldr     r4, =F_READ
    blx     r4
    mov     r5, r0
    ldr     r0, =FIL
    ldr     r4, =F_CLOSE
    blx     r4
    MARKN   m_read, r5
    cmp     r5, #0
    bne     90f
    @ Validate.
    ldr     r6, =GOT
    ldr     r6, [r6]                    @ r6 = file size
    cmp     r6, #(FOOTER + 8)
    blt     fail1
    tst     r6, #3
    bne     fail2
    ldr     r0, =(MAX_IMAGE + FOOTER)
    cmp     r6, r0
    bgt     fail3
    sub     r7, r6, #FOOTER             @ r7 = image length
    ldr     r8, =STAGE
    add     r9, r8, r7                  @ r9 = footer
    ldr     r0, [r9]
    ldr     r1, =FOOTER_MAGIC
    cmp     r0, r1
    bne     fail4
    ldr     r0, [r9, #4]
    cmp     r0, r7
    bne     fail5
    ldr     r0, [r8]                    @ initial stack pointer
    ldr     r1, =0x20030000
    cmp     r0, r1
    bne     fail6
    ldr     r0, [r8, #4]                @ reset vector
    tst     r0, #1
    beq     fail7
    ldr     r1, =APP_START
    cmp     r0, r1
    blo     fail8
    ldr     r1, =APP_LIMIT
    cmp     r0, r1
    bhs     fail9
    @ CRC32 (zlib: reflected 0xEDB88320, init/final 0xFFFFFFFF).
    mvn     r0, #0
    movs    r1, #0
    ldr     r3, =0xedb88320
10: cmp     r1, r7
    bhs     13f
    ldrb    r2, [r8, r1]
    eors    r0, r0, r2
    movs    r2, #8
11: lsrs    r0, r0, #1
    it      cs
    eorcs   r0, r0, r3
    subs    r2, r2, #1
    bne     11b
    adds    r1, r1, #1
    b       10b
13: mvn     r0, r0
    ldr     r1, [r9, #8]
    cmp     r0, r1
    bne     fail10
    b       retire
fail1: movs    r5, #1
    b       fail_common
fail2: movs    r5, #2
    b       fail_common
fail3: movs    r5, #3
    b       fail_common
fail4: movs    r5, #4
    b       fail_common
fail5: movs    r5, #5
    b       fail_common
fail6: movs    r5, #6
    b       fail_common
fail7: movs    r5, #7
    b       fail_common
fail8: movs    r5, #8
    b       fail_common
fail9: movs    r5, #9
    b       fail_common
fail10: movs    r5, #10
    b       fail_common
fail_common:
    MARKN   m_fail, r5
    b       90f
retire:
    @ Retire the file before anything is erased.
    ldr     r0, =name_ok
    ldr     r4, =F_UNLINK
    blx     r4                          @ result ignored (usually "no file")
    ldr     r0, =name_bin
    ldr     r1, =name_ok
    ldr     r4, =F_RENAME
    blx     r4
    mov     r5, r0
    MARKN   m_rename, r5
    cmp     r5, #0
    bne     90f
    @ Copy the flasher into SRAM and run it there. It never returns.
    ldr     r0, =flasher
    bic     r0, r0, #1
    ldr     r1, =flasher_end
    ldr     r2, =RAMCODE
20: ldr     r3, [r0], #4
    str     r3, [r2], #4
    cmp     r0, r1
    blo     20b
    dsb
    isb
    ldr     r0, =STAGE
    mov     r1, r7
    ldr     r2, =(RAMCODE + 1)
    bx      r2
90: pop     {r0-r12, lr}
    mov     r1, r0                      @ replaced instructions
    movs    r0, #3
    b.w     HOOK_RETURN

@ mark_file(r0 = name): create an empty file. Preserves r4-r11.
    .thumb_func
mark_file:
    push    {r4, lr}
    mov     r1, r0
    ldr     r0, =MARKFIL
    movs    r2, #0x0a                   @ FA_WRITE | FA_CREATE_ALWAYS
    ldr     r4, =F_OPEN
    blx     r4
    cbnz    r0, 1f
    ldr     r0, =MARKFIL
    ldr     r4, =F_CLOSE
    blx     r4
1:  pop     {r4, pc}

@ mark_code(r0 = template with "00" at offset 6, r1 = code 0..99).
    .thumb_func
mark_code:
    push    {r4, r5, lr}
    ldr     r2, =NAMEBUF
    movs    r3, #0
1:  ldrb    r4, [r0, r3]                @ copy the template (<= 15 chars + NUL)
    strb    r4, [r2, r3]
    adds    r3, r3, #1
    cmp     r3, #16
    blt     1b
    cmp     r1, #99
    it      hi
    movhi   r1, #99
    movs    r3, #10
    udiv    r4, r1, r3
    mls     r5, r4, r3, r1
    adds    r4, r4, #'0'
    adds    r5, r5, #'0'
    strb    r4, [r2, #6]
    strb    r5, [r2, #7]
    mov     r0, r2
    bl      mark_file
    pop     {r4, r5, pc}

    .align 2
name_bin:   .asciz "mgmod.bin"
    .align 2
name_ok:    .asciz "mgmod.ok"
    .align 2
m_hook:     .asciz "mghook.txt"
    .align 2
m_shift:    .asciz "mgshift.txt"
    .align 2
m_noshift:  .asciz "mgnoshft.txt"
    .align 2
m_open:     .asciz "mgopen00.txt\0\0\0"
    .align 2
m_read:     .asciz "mgread00.txt\0\0\0"
    .align 2
m_fail:     .asciz "mgfail00.txt\0\0\0"
    .align 2
m_rename:   .asciz "mgren_00.txt\0\0\0"
    .ltorg

@ ---------------------------------------------------------------------------
@ Flasher: runs from SRAM (position independent, own literal pool).
@ r0 = source (SDRAM), r1 = length in bytes (multiple of 4, <= 256 KiB).
    .align 2
    .thumb_func
flasher:
    cpsid   i
    ldr     r4, f_base                  @ FLASH registers 0x40023C00
    ldr     r2, [r4, #0x10]             @ unlock if locked
    tst     r2, #0x80000000
    beq     1f
    ldr     r2, f_key1
    str     r2, [r4, #4]
    ldr     r2, f_key2
    str     r2, [r4, #4]
1:  bl      fw_wait
    movs    r2, #0xf3                   @ clear EOP and error flags
    str     r2, [r4, #0x0c]
    movs    r5, #5                      @ erase sectors 5 and 6 only
2:  cmp     r5, #5
    blt     fw_hang                     @ guard: never below sector 5
    cmp     r5, #6
    bgt     fw_hang
    ldr     r2, [r4, #0x10]
    bic     r2, r2, #0x300
    orr     r2, r2, #0x200              @ PSIZE x32
    str     r2, [r4, #0x10]
    ldr     r2, [r4, #0x10]
    bic     r2, r2, #0xf8
    orr     r2, r2, r5, lsl #3          @ SNB
    orr     r2, r2, #2                  @ SER
    str     r2, [r4, #0x10]
    ldr     r2, [r4, #0x10]
    orr     r2, r2, #0x10000            @ STRT
    str     r2, [r4, #0x10]
    bl      fw_wait
    ldr     r2, [r4, #0x10]
    bic     r2, r2, #0xfa               @ clear SER and SNB
    str     r2, [r4, #0x10]
    adds    r5, r5, #1
    cmp     r5, #7
    blt     2b
    ldr     r2, [r4, #0x10]             @ program
    bic     r2, r2, #0x300
    orr     r2, r2, #0x200              @ PSIZE x32
    orr     r2, r2, #1                  @ PG
    str     r2, [r4, #0x10]
    ldr     r6, f_app
    ldr     r8, f_limit
    movs    r7, #0
3:  cmp     r7, r1
    bhs     4f
    add     r3, r6, r7
    cmp     r3, r6                      @ guard every word
    blo     fw_hang
    cmp     r3, r8
    bhs     fw_hang
    ldr     r2, [r0, r7]
    str     r2, [r3]
    dsb
    bl      fw_wait
    adds    r7, r7, #4
    b       3b
4:  ldr     r2, [r4, #0x10]
    bic     r2, r2, #1                  @ PG off
    orr     r2, r2, #0x80000000         @ LOCK
    str     r2, [r4, #0x10]
    ldr     r2, [r4, #0x00]             @ ACR: disable and reset the ART caches
    bic     r2, r2, #0x600              @ so verification reads the new contents
    str     r2, [r4, #0x00]
    orr     r2, r2, #0x1800
    str     r2, [r4, #0x00]
    bic     r2, r2, #0x1800
    str     r2, [r4, #0x00]
    movs    r7, #0                      @ verify
5:  cmp     r7, r1
    bhs     6f
    ldr     r2, [r0, r7]
    ldr     r3, [r6, r7]
    cmp     r2, r3
    bne     fw_hang
    adds    r7, r7, #4
    b       5b
6:  dsb
    ldr     r2, f_aircr
    ldr     r3, f_reset
    str     r3, [r2]
    dsb
fw_hang:
    b       fw_hang                     @ failed write: recover with the audio bootloader
fw_wait:
    ldr     r2, [r4, #0x0c]
    tst     r2, #0x10000                @ BSY
    bne     fw_wait
    bx      lr
    .align 2
f_base:  .word 0x40023c00
f_key1:  .word 0x45670123
f_key2:  .word 0xcdef89ab
f_app:   .word APP_START
f_limit: .word APP_LIMIT
f_aircr: .word 0xe000ed0c
f_reset: .word 0x05fa0004
flasher_end:
