.include "sneaky.h"

    .extern payload_insert
    .extern payload_extract
    .extern strcmp
    .extern printf
    .extern fflush

    .text
    .globl parse_cmdline
    .globl done

# Parses:
#   sneaky add input payload   -> ACTION=0, INPUT_FILE=argv[2], PAYLOAD=argv[3], [OUTPUT_FILE=argv[4]|default]
#   sneaky extract input [out] -> ACTION=1, INPUT_FILE=argv[2], [PAYLOAD=argv[3]|default]
# Expects ideally: a0=argc, a1=argv (RV64). If not, we fall back to globals ARGC/ARGV.

parse_cmdline:
        # Prologue (16B aligned)
	addi  sp, sp, -56
	sd    ra, 48(sp)
	sd    s0, 40(sp)
	sd    s1, 32(sp)
	sd    s2, 24(sp)
	sd    s3, 16(sp)

        # ---------- Acquire argc/argv robustly ----------
        # Prefer a0/a1 if sane; else load from globals ARGC/ARGV.
        mv      s2, a0                  # tentative argc
        mv      s1, a1                  # tentative argv

        # If argv is NULL OR argc < 1, load from globals.
        beqz    s1, .Lload_from_globals
        li      t0, 1
        blt     s2, t0, .Lload_from_globals
        j       .Lhave_args

.Lload_from_globals:
        # s2 = ARGC (int), s1 = ARGV (char**)
        la      t1, ARGC
        lw      s2, 0(t1)               # ARGC may be 32-bit; that's fine
        la      t1, ARGV
        ld      s1, 0(t1)

.Lhave_args:
        # Need at least argv[0], argv[1] (argc >= 2)
        li      t0, 2
        blt     s2, t0, parse_error

        # argv[1] → keep in callee-saved s3 (so calls can't clobber it)
        ld      t1, 8(s1)
        mv      s3, t1

        # strcmp(argv[1], "add")
        la      t2, str_add
        mv      a0, s3
        mv      a1, t2
        call    strcmp
        beqz    a0, is_add

        # strcmp(argv[1], "extract")
        la      t2, str_extract
        mv      a0, s3
        mv      a1, t2
        call    strcmp
        beqz    a0, is_extract

        j       parse_error

is_add:
#       # Debug
#       la      a0, pradd
#       call    printf
#       li      a0, 0
#       call    fflush

        # Require: prog add input payload  (argc >= 4)
        li      t0, 4
        blt     s2, t0, parse_error

        # ACTION = 0
        la      t3, ACTION
        sw      zero, 0(t3)

        # INPUT_FILE = argv[2]
        ld      t4, 16(s1)
        la      t3, INPUT_FILE
        sd      t4, 0(t3)

        # PAYLOAD = argv[3]
        ld      t4, 24(s1)
        la      t3, PAYLOAD
        sd      t4, 0(t3)

#       # printf filenames
#       la      a0, fmt_files_add
#       la      t5, INPUT_FILE
#       ld      a1, 0(t5)
#       la      t5, PAYLOAD
#       ld      a2, 0(t5)
#       call    printf
#       li      a0, 0
#       call    fflush

        # Optional OUTPUT_FILE = argv[4], else default
        li      t0, 5
        blt     s2, t0, .Luse_default_output
        ld      t4, 32(s1)              # argv[4]
        la      t3, OUTPUT_FILE
        sd      t4, 0(t3)
        j       .Loutput_done
.Luse_default_output:
        la      t3, OUTPUT_FILE
        la      t4, default_out
        sd      t4, 0(t3)
.Loutput_done:
        call    payload_insert
        j       done

is_extract:
#       # Debug
#       la      a0, prextract
#       call    printf
#       li      a0, 0
#       call    fflush

        # Require: prog extract input  (argc >= 3)
        li      t0, 3
        blt     s2, t0, parse_error

        # ACTION = 1
        la      t3, ACTION
        li      t4, 1
        sw      t4, 0(t3)

        # INPUT_FILE = argv[2]
        ld      t4, 16(s1)
        la      t3, INPUT_FILE
        sd      t4, 0(t3)

        # Optional: show input filename
        la      a0, fmt_file_extract
        la      t5, INPUT_FILE
        ld      a1, 0(t5)
        call    printf
        li      a0, 0
        call    fflush

        # Optional PAYLOAD for extract: argv[3] or default
        li      t0, 4
        blt     s2, t0, .Luse_default_extract
        ld      t4, 24(s1)              # argv[3]
        la      t3, PAYLOAD
        sd      t4, 0(t3)
        j       .Lextract_output_done
.Luse_default_extract:
        la      t3, PAYLOAD
        la      t4, default_extract
        sd      t4, 0(t3)
.Lextract_output_done:
        call    payload_extract
        j       done

parse_error:
        j       wrong_args              # shared handler elsewhere


done:
        ld      s3, 16(sp)
        ld      s2, 24(sp)
        ld      s1, 32(sp)
        ld      s0, 40(sp)
        ld      ra, 48(sp)
        addi    sp, sp, 56
        ret


    .section .rodata
    .globl str_add
    .globl str_extract
    .globl fmt_files_add
    .globl fmt_file_extract
    .globl pradd
    .globl prextract

str_add:            .asciz "add"
str_extract:        .asciz "extract"
fmt_files_add:      .asciz "Input=%s, Payload=%s\n"
fmt_file_extract:   .asciz "Input=%s\n"
pradd:              .asciz "ADD\n"
prextract:          .asciz "EXTRACT\n"
default_out:        .asciz "output.bmp"
default_extract:    .asciz "extract.bin"
