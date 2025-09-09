# src/globals.s
.section .data
.globl ACTION, INPUT_FILE, PAYLOAD, OUTPUT_FILE
        ACTION:         .word 0
        INPUT_FILE:     .dword 0
        PAYLOAD:        .dword 0
        OUTPUT_FILE:    .dword 0

.section .rodata
.globl error_args
error_args:
.asciz "Usage: sneaky add [input file] [payload file]\n\tsneaky extract [input file]\n"

    # Keep your original label name so main.s doesn't need changing
.globl .ER0
.ER0:
.asciz "%s\n"
