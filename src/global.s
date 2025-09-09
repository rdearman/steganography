# src/globals.s
.section .data
.globl ACTION, INPUT_FILE, PAYLOAD, OUTPUT_FILE
        ACTION:         .word 0
        INPUT_FILE:     .dword 0
        PAYLOAD:        .dword 0
        OUTPUT_FILE:    .dword 0
.align 8
.globl EXTRACT_LEN
EXTRACT_LEN:    .quad 0      # set by parse_cmdline (or left 0 to trigger needlen error)

.section .rodata
.globl error_args
error_args:
.asciz "Usage: sneaky add [input file] [payload file]\n\tsneaky extract [input file]\n"

    # Keep your original label name so main.s doesn't need changing
.globl .ER0
.ER0:
.asciz "%s\n"

.bss
.align 3              # 8-byte alignment
.globl ARGC
.globl ARGV

ARGC:
    .word 0               # 32-bit argc
    .word 0               # pad to keep ARGV aligned on 8
ARGV:
    .dword 0              # 64-bit pointer to char**
