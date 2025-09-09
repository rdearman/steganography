.include "sneaky.h"

.extern payload_insert
.extern payload_extract
	
.text
.globl parse_cmdline
.globl done

	
# Parses:
#   sneaky add input payload   -> ACTION=0, INPUT_FILE=argv[2], PAYLOAD=argv[3]
#   sneaky extract input       -> ACTION=1, INPUT_FILE=argv[2]
# Expects: a0=argc, a1=argv

parse_cmdline:
        # Prologue (preserve s0/s1/s2/ra, keep stack 16B aligned)
        addi    sp, sp, -40
        sd      ra, 32(sp)
        sd      s0, 24(sp)
        sd      s1, 16(sp)
        sd      s2, 8(sp)
        mv      s0, sp
        mv      s1, a1 # save argv in s1 (callee-saved)
        mv      s2, a0 # save argc in s2 (stable across calls)

        # Need at least: argv[0], argv[1] => argc >= 2 for command,
        li      t0, 2
        blt     s2, t0, parse_error # too few to even read argv[1]

        # t1 = argv[1]
        ld      t1, 8(s1)

        # strcmp(argv[1], "add")
        la      t2, str_add
        mv      a0, t1
        mv      a1, t2
        call    strcmp
        beqz    a0, is_add

        # strcmp(argv[1], "extract")
        la      t2, str_extract
        mv      a0, t1
        mv      a1, t2
        call    strcmp
        beqz    a0, is_extract

        j       parse_error

is_add:
#        # Debug print
#        la      a0, pradd
#        call    printf
#        li      a0, 0
#        call    fflush

        # argc >= 4 required
        li      t0, 4
        blt     s2, t0, parse_error

        la      t3, ACTION
        sw      zero, 0(t3) # ACTION = 0 (add)

        # INPUT_FILE = argv[2], PAYLOAD = argv[3]
        ld      t4, 16(s1) # argv[2]
        la      t3, INPUT_FILE
        sd      t4, 0(t3)

        ld      t4, 24(s1) # argv[3]
        la      t3, PAYLOAD
        sd      t4, 0(t3)

#        # ---- printf both filenames ----
#        la      a0, fmt_files_add
#        la      t5, INPUT_FILE
#        ld      a1, 0(t5) # a1 = *(INPUT_FILE)
#        la      t5, PAYLOAD
#        ld      a2, 0(t5) # a2 = *(PAYLOAD)
#        call    printf
#        li      a0, 0
#        call    fflush

        # ----------------------------------------------------------
        # Optional OUTPUT_FILE = argv[4]
        # If not provided, default to "output.bmp"
        # ----------------------------------------------------------
        li      t0, 5
        blt     s2, t0, use_default_output   # argc < 5 → no argv[4]

        # argv[4] exists → use it
        ld      t4, 32(s1)              # argv[4]
        la      t3, OUTPUT_FILE
        sd      t4, 0(t3)
        j       output_done

use_default_output:
        la      t3, OUTPUT_FILE
        la      t4, default_out
        sd      t4, 0(t3)

output_done:
	
	# -------- Need to now open the files and insert payload --------- #
        j 	payload_insert
        j       done

is_extract:
        # Debug print
        la      a0, prextract
        call    printf
        li      a0, 0
        call    fflush

        # argc >= 3 required
        li      t0, 3
        blt     s2, t0, parse_error

        la      t3, ACTION
        li      t4, 1
        sw      t4, 0(t3) # ACTION = 1 (extract)

        # INPUT_FILE = argv[2]
        ld      t4, 16(s1)
        la      t3, INPUT_FILE
        sd      t4, 0(t3)

        # ---- printf input filename ----
        la      a0, fmt_file_extract
        la      t5, INPUT_FILE
        ld      a1, 0(t5) # a1 = *(INPUT_FILE)
        call    printf
        li      a0, 0
        call    fflush
	
	# -------- Need to now extract payload --------- #
	# payload_extract
	
        j       done

parse_error:
        # Return non-zero to signal error to caller
        # li      a0, 1
        j wrong_args
	
done:
        # Epilogue
        ld      s2, 8(sp)
        ld      s1, 16(sp)
        ld      s0, 24(sp)
        ld      ra, 32(sp)
        addi    sp, sp, 40
        ret


.section .rodata
.globl str_add
.globl str_extract
.globl fmt_files_add
.globl fmt_file_extract
.globl pradd
.globl prextract

	str_add:          .asciz "add"
	str_extract:      .asciz "extract"
	fmt_files_add:    .asciz "Input=%s, Payload=%s\n"
	fmt_file_extract: .asciz "Input=%s\n"
	pradd:            .asciz "ADD\n"
	prextract:        .asciz "EXTRACT\n"
	default_out:    .asciz "output.bmp"
