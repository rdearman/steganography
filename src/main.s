	# main.s
	# Embed a file into another file.
	
.include "sneaky.h"

.text
.globl main
.globl error_message
.globl wrong_args

	
error_message:
        la a0, .ER0
        mv a1, a4
        call printf@plt
        j exit
	
wrong_args:
	# Set up arguments for printf	
        la a0, error_args # Load the address of the format string
        call printf@plt # Use "printf" for formatted output
        j exit

	
main:

        li      t6, 3 # need at least 3 args for 'extract'
        addi    t0, sp, -64
        andi    sp, t0, -16
        sd      ra, 56(sp)
        sd      s0, 48(sp)
        addi    s0, sp, 64
        # Save argv/argc
        sd      a1, -48(s0) # save argv
        sw      a0, -36(s0) # save argc
        # argc check WITHOUT clobbering a1
        blt     a0, t6, wrong_args # argv[0], argv[1], argv[2] at minimum
        li      t1, 1
        sw      t1, -20(s0)
        # restore and call
        lw      a0, -36(s0) # argc
        ld      a1, -48(s0) # argv
        call    parse_cmdline
        j       exit
	
exit:
        li a0, 0
        li a7, 93
        ecall



