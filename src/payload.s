.include "sneaky.h"

.equ BUFSIZE, 1024

.text
.globl payload_insert
.globl payload_extract

.extern fmt_file_extract    # defined in parse_cmdline.s

# ----------------------------------------------------------------------
# payload_insert(a0..): open INPUT_FILE, validate BMP header, etc.
# ----------------------------------------------------------------------
payload_insert:

        ####################################
        ## Check PAYLOAD size first
        ####################################

        # --- open(PAYLOAD, O_RDONLY) ---
        la      t0, PAYLOAD
        ld      a1, 0(t0)       # a1 = pointer to payload filename
        li      a0, -100        # AT_FDCWD
        li      a2, 0           # O_RDONLY
        li      a3, 0           # mode
        li      a7, 56          # syscall: openat
        ecall
        blt     a0, x0, syscall_error
        mv      s10, a0         # save payload fd in s10

        # --- lseek(fd, 0, SEEK_END) to get size ---
        mv      a0, s10         # fd
        li      a1, 0           # offset = 0
        li      a2, 2           # SEEK_END
        li      a7, 62          # syscall: lseek
        ecall
        blt     a0, x0, syscall_error
        mv      s11, a0         # s11 = payload_size

        # --- rewind to start: lseek(fd, 0, SEEK_SET) ---
        mv      a0, s10
        li      a1, 0
        li      a2, 0           # SEEK_SET
        li      a7, 62
        ecall

#        # Debug print: payload size
#        la      a0, dbg_payload
#        mv      a1, s11
#        call    printf
#        li      a0, 0
#        call    fflush
	
        ####################################
        ## Check INPUT capacity
        ####################################

	# Check Imput File Capacity. 
        addi    sp, sp, -16
        sd      ra, 8(sp)
        sd      s0, 0(sp)

        # --- open(INPUT_FILE, O_RDONLY) ---
        la      t3, INPUT_FILE
        ld      a1, 0(t3)
        li      a0, -100
        li      a2, 0
        li      a3, 0
        li      a7, 56
        ecall
        blt     a0, x0, syscall_error
        mv      s0, a0          # save input BMP fd in s0


        # --- read first 54 bytes into inbuf ---
        mv      a0, s0          # fd
        la      a1, inbuf
        li      a2, 54          # header size
        li      a7, 63          # syscall: read
        ecall
        blt     a0, x0, syscall_error

        mv      s4, a0          # save bytes_read
        li      t5, 54
        blt     s4, t5, short_read_error

        # --- check buf[0] == 0x42 and buf[1] == 0x4D ---
        la      t0, inbuf
        lbu     t1, 0(t0)       # first byte
        lbu     t2, 1(t0)       # second byte
        li      t3, 0x42
        li      t4, 0x4D
        bne     t1, t3, invalid_bmp_error
        bne     t2, t4, invalid_bmp_error

 #       # Valid BMP signature
 #       la      a0, msg_bmpok
 #       call    printf
 #       li      a0, 0
 #       call    fflush

        # ----------------------------------------------------------
        # Extract BMP header fields from inbuf
        # ----------------------------------------------------------
        la      t0, inbuf

        # bfOffBits (bytes 10–13, little endian 32-bit)
        lbu     t1, 10(t0)
        lbu     t2, 11(t0)
        lbu     t3, 12(t0)
        lbu     t4, 13(t0)
        sll     t2, t2, 8
        sll     t3, t3, 16
        sll     t4, t4, 24
        or      t1, t1, t2
        or      t1, t1, t3
        or      t1, t1, t4
        mv      s1, t1                # save bfOffBits (pixel data offset)

        # biWidth (bytes 18–21, little endian 32-bit)
        lbu     t1, 18(t0)
        lbu     t2, 19(t0)
        lbu     t3, 20(t0)
        lbu     t4, 21(t0)
        sll     t2, t2, 8
        sll     t3, t3, 16
        sll     t4, t4, 24
        or      t1, t1, t2
        or      t1, t1, t3
        or      t1, t1, t4
        mv      s2, t1                # save width

        # biHeight (bytes 22–25, little endian 32-bit)
        lbu     t1, 22(t0)
        lbu     t2, 23(t0)
        lbu     t3, 24(t0)
        lbu     t4, 25(t0)
        sll     t2, t2, 8
        sll     t3, t3, 16
        sll     t4, t4, 24
        or      t1, t1, t2
        or      t1, t1, t3
        or      t1, t1, t4
        mv      s3, t1                # save height (may be negative for top-down BMP)

        # biBitCount (bytes 28–29, little endian 16-bit)
        lbu     t1, 28(t0)
        lbu     t2, 29(t0)
        sll     t2, t2, 8
        or      t1, t1, t2
        mv      s4, t1                # save bits per pixel

	# s1, save bfOffBits (pixel data offset)
	# s2, save width
	# s3, save height (may be negative for top-down BMP)
	# s4, save bits per pixel
        # --- calculate storage capacity ---
        # s5 = bytes per pixel
        # s6 = row_bytes (aligned)
        # s7 = abs(height)
        # s8 = pixel_array_size
        # s9 = capacity_bytes

	li      t1, 8
	divu    t0, s4, t1      # instead of divu t0, s4, x8
	addi    s5, t0, 0       # s5 = bytes_per_pixel

        mul     t2, s2, s5       # width * bytes_per_pixel
        addi    t2, t2, 3
        li      t3, -4
        and     t2, t2, t3
        addi    s6, t2, 0        # s6 = row_bytes

        addi    t4, s3, 0
        blt     t4, x0, neg_height
        j       height_done
neg_height:
        neg     t4, t4
height_done:
        addi    s7, t4, 0        # s7 = abs(height)

        mul     t5, s6, s7
        addi    s8, t5, 0        # s8 = pixel_array_size (bytes)

        srli    t6, s8, 3
        addi    s9, t6, 0        # s9 = capacity_bytes

        # --- compare payload_size (s11) with capacity (s9) ---
        bgtu    s11, s9, payload_too_large

	
#        # ----------------------------------------------------------
#        # Debug: print width, height, bpp, capacity
#        # printf("W=%d, H=%d, BPP=%d, CAP=%d\n", s2, s7, s4, s9);
#        # ----------------------------------------------------------
#        la      a0, dbg_fmt
#        addi    a1, s2, 0        # width
#        addi    a2, s7, 0        # abs(height)
#        addi    a3, s4, 0        # bits per pixel
#        addi    a4, s9, 0        # capacity bytes
#        call    printf
#        li      a0, 0
#        call    fflush

        ############################################################
        ## OPEN OUTPUT FILE
        ############################################################
        la      t0, OUTPUT_FILE
        ld      a1, 0(t0)           # a1 = pointer to output filename
        li      a0, -100            # AT_FDCWD
        li      a2, 577             # O_WRONLY | O_CREAT | O_TRUNC
        li      a3, 420             # mode = 0644 (0664 -> 436, 0644 -> 420)
        li      a7, 56              # openat
        ecall
        blt     a0, x0, syscall_error
        mv      t5, a0              # t5 = output fd

        ############################################################
        ## REWIND INPUT BMP TO START (we already consumed 54 bytes)
        ############################################################
        mv      a0, s0              # input fd
        li      a1, 0               # offset
        li      a2, 0               # SEEK_SET
        li      a7, 62              # lseek
        ecall
        blt     a0, x0, syscall_error

        ############################################################
        ## COPY HEADER (bfOffBits bytes) EXACTLY
        ############################################################
        mv      t1, s1              # t1 = remaining header bytes (bfOffBits)
header_copy_loop:
        beqz    t1, header_done

        # t2 = chunk = min(t1, 512)
        li      t2, 512
        bltu    t1, t2, header_use_remaining
        j       header_have_chunk
header_use_remaining:
        mv      t2, t1
header_have_chunk:

        # read chunk from input
        mv      a0, s0              # input fd
        la      a1, inbuf
        mv      a2, t2
        li      a7, 63              # read
        ecall
        blt     a0, x0, syscall_error
        beqz    a0, header_done     # unexpected EOF

        # write the bytes we actually got
        mv      t3, a0              # bytes_read
        mv      a0, t5              # output fd
        la      a1, inbuf
        mv      a2, t3
        li      a7, 64              # write
        ecall

        sub     t1, t1, t3          # remaining -= bytes_read
        j       header_copy_loop
header_done:

        ############################################################
        ## EMBED PAYLOAD INTO PIXELS
        ############################################################
        mv      t4, s11             # t4 = remaining payload bytes
embed_loop:
        beqz    t4, payload_done    # no more payload

        # read 1 byte from payload
        mv      a0, s10             # payload fd
        la      a1, inbuf
        li      a2, 1
        li      a7, 63              # read
        ecall
        blt     a0, x0, syscall_error
        beqz    a0, payload_done    # unexpected EOF in payload

        la      t6, inbuf
        lbu     t0, 0(t6)           # t0 = payload byte
        addi    t4, t4, -1

        li      t1, 8               # 8 bits per payload byte
bit_loop:
        beqz    t1, embed_loop

        # read 1 pixel byte from BMP input
        mv      a0, s0              # input BMP fd
        la      a1, inbuf
        li      a2, 1
        li      a7, 63              # read
        ecall
        blt     a0, x0, syscall_error
        beqz    a0, payload_done    # EOF in BMP (! shouldn't happen if prechecked)

        la      t6, inbuf
        lbu     t2, 0(t6)           # pixel byte
        andi    t2, t2, 0xFE        # clear LSB
        andi    t3, t0, 1           # get current payload bit (LSB-first)
        or      t2, t2, t3          # merge bit into pixel

        # write modified pixel byte to output BMP
        mv      a0, t5              # output fd
        la      a1, inbuf
        sb      t2, 0(a1)           # store modified pixel into buffer
        li      a2, 1
        li      a7, 64              # write
        ecall

        srli    t0, t0, 1           # consume payload bit
        addi    t1, t1, -1
        j       bit_loop
payload_done:

        ############################################################
        ## COPY REMAINING BMP DATA (after payload embedded)
        ############################################################
copy_rest:
        mv      a0, s0              # input BMP fd
        la      a1, inbuf
        li      a2, 512
        li      a7, 63              # read
        ecall
        blt     a0, x0, syscall_error
        beqz    a0, copy_done

        mv      t2, a0              # bytes_read
        mv      a0, t5              # output fd
        la      a1, inbuf
        mv      a2, t2
        li      a7, 64              # write
        ecall
        j       copy_rest
copy_done:

        # --- close all file descriptors ---
close_and_ok:

        # close payload (s10)
        mv      a0, s10
        li      a7, 57
        ecall

	# close input BMP
	mv a0, s0
	li a7, 57
	ecall

        # close output BMP (t5)
        mv      a0, t5
        li      a7, 57
        ecall

        # return success
        li      a0, 0
        j       epilogue

	
# ----------------------------------------------------------------------
# Error branches
#   - For syscalls: set t6 = errno and print strerror(errno)
#   - For validation: print targeted messages (no errno)
# ----------------------------------------------------------------------
syscall_error:
        neg     t6, a0          # errno = -a0 (positive)
        call    payload_error_errno
        li      a0, -1
        j       epilogue

short_read_error:
        # printf("Error: short read (%ld bytes) from %s\n", s4, INPUT_FILE)
        la      t0, INPUT_FILE
        ld      a2, 0(t0)       # filename
        mv      a1, s4          # bytes actually read
        la      a0, perr_shortread
        call    printf
        li      a0, 0
        call    fflush
        li      a0, -1
        j       epilogue

invalid_bmp_error:
        # printf("Error: not a BMP (got 0x%02X 0x%02X) in %s\n", t1, t2, INPUT_FILE)
        la      t0, INPUT_FILE
        ld      a3, 0(t0)       # filename
        mv      a1, t1
        mv      a2, t2
        la      a0, perr_notbmp
        call    printf
        li      a0, 0
        call    fflush
        li      a0, -1
        j       epilogue

payload_too_large:
        # printf("Error: payload too large (%ld > %ld)\n", s11, s9);
        la      a0, perr_toolarge
        mv      a1, s11
        mv      a2, s9
        call    printf
        li      a0, 0
        call    fflush

        li      a0, -1
        j       epilogue


	
# ----------------------------------------------------------------------
# Common epilogue
# ----------------------------------------------------------------------
epilogue:
        ld      s0, 0(sp)
        ld      ra, 8(sp)
        addi    sp, sp, 16
        j       done

# ----------------------------------------------------------------------
# Stub for payload_extract
# ----------------------------------------------------------------------
payload_extract:
        addi    sp, sp, -16
        sd      ra, 8(sp)
        sd      s0, 0(sp)

        # Not implemented: reuse errno-style printer with EINVAL
        li      t6, 22
        call    payload_error_errno
        li      a0, -1

        ld      s0, 0(sp)
        ld      ra, 8(sp)
        addi    sp, sp, 16
        ret

# ----------------------------------------------------------------------
# Error printers
# ----------------------------------------------------------------------
# Use strerror(errno) with filename
payload_error_errno:
        addi    sp, sp, -16
        sd      ra, 8(sp)
        sd      s0, 0(sp)

        mv      a0, t6
        blez    a0, use_unknown
        call    strerror            # a0 = char* errstr
        mv      a1, a0              # a1 = errstr
        j       have_errstr
use_unknown:
        la      a1, unknown_err
have_errstr:
        la      t0, INPUT_FILE
        ld      a2, 0(t0)           # a2 = filename
        la      a0, perr_errno      # "Error (%s) opening %s\n"
        call    printf
        li      a0, 0
        call    fflush

        ld      s0, 0(sp)
        ld      ra, 8(sp)
        addi    sp, sp, 16
        ret

# ----------------------------------------------------------------------
# Data
# ----------------------------------------------------------------------
.section .rodata
	perr_errno:      .asciz "Error (%s) opening %s\n"
	perr_shortread:  .asciz "Error: short read (%ld bytes) from %s\n"
	perr_notbmp:     .asciz "Error: not a BMP (got 0x%02X 0x%02X) in %s\n"
	msg_bmpok:       .asciz "Valid BMP input file\n"
	unknown_err:     .asciz "Unknown error"
	dbg_fmt: .asciz "W=%d, H=%d, BPP=%d, CAP=%d\n"
	dbg_payload: .asciz "Payload size = %ld bytes\n"
	perr_toolarge: .asciz "Error: payload too large (%ld > %ld)\n"
	
.data
.align 8
	inbuf:           .space 1024
