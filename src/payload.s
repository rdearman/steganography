.include "sneaky.h"

# ---------- Header constants ----------
.equ HDR_MAGIC0, 0x53        # 'S'
.equ HDR_MAGIC1, 0x4E        # 'N'
.equ HDR_MAGIC2, 0x4B        # 'K'
.equ HDR_MAGIC3, 0x59        # 'Y'
.equ HDR_MAX_NAME, 255

.equ BUFSIZE, 1024

# ---------- Scratch buffers ----------
.bss
.align 3
HEADER_NAMEBUF:
    .skip 256                 # room for basename (<=255) + optional NUL

.text
.globl payload_insert
.globl payload_extract

# libc
.extern printf
.extern fflush
.extern strerror

# (optional external from parse_cmdline.s; not required here)
.extern fmt_file_extract

# ---------- Byte helpers (batched 8 bytes) ----------
# Embed one data byte (in register r) into 8 pixel bytes’ LSBs.
# Requires: s0=input BMP fd, t5=output BMP fd, 'inbuf' scratch (>= 8 bytes).
.macro EMBED_BYTE r
    # read 8 pixel bytes in one go
    mv      a0, s0
    la      a1, inbuf
    li      a2, 8
    li      a7, 63         # read
    ecall

    # modify their LSBs according to bits of \r (LSB-first)
    li      t4, 0          # i = 0..7
1:
    li      t1, 8
    beq     t4, t1, 2f
    add     t2, t4, zero
    la      t6, inbuf
    add     t6, t6, t2
    lbu     t3, 0(t6)
    andi    t3, t3, 0xFE
    srl     t0, \r, t4
    andi    t0, t0, 1
    or      t3, t3, t0
    sb      t3, 0(t6)
    addi    t4, t4, 1
    j       1b
2:
    # write the 8 modified bytes back
    mv      a0, t5
    la      a1, inbuf
    li      a2, 8
    li      a7, 64         # write
    ecall
.endm

# Read one embedded byte from 8 pixel bytes into register 'dest'.
# Requires: s0=input BMP fd, 'inbuf' scratch (>= 8 bytes).
.macro NEXT_EMBEDDED_BYTE dest
    # read 8 pixel bytes at once
    mv      a0, s0
    la      a1, inbuf
    li      a2, 8
    li      a7, 63         # read
    ecall
    blt     a0, x0, syscall_error_x       # syscall failed (a0 < 0)
    li      t0, 8
    bltu    a0, t0, _unexpected_eof_x     # short read (<8) → error

    # assemble their 8 LSBs (LSB-first)
    li      t4, 0
    li      \dest, 0
1:
    li      t1, 8
    beq     t4, t1, 2f
    add     t2, t4, zero
    la      t6, inbuf
    add     t6, t6, t2
    lbu     t0, 0(t6)
    andi    t0, t0, 1
    sll     t0, t0, t4
    or      \dest, \dest, t0
    addi    t4, t4, 1
    j       1b
2:
.endm

# ----------------------------------------------------------------------
# payload_insert: embed header + payload into BMP pixel LSBs
#   Uses: s0..s11, t5 as output BMP fd
# ----------------------------------------------------------------------
payload_insert:
    # Prologue (save all s* you use; keep sp 16B aligned)
    addi    sp, sp, -128
    sd      ra, 120(sp)
    sd      s0, 112(sp)
    sd      s1, 104(sp)
    sd      s2, 96(sp)
    sd      s3, 88(sp)
    sd      s4, 80(sp)
    sd      s5, 72(sp)
    sd      s6, 64(sp)
    sd      s7, 56(sp)
    sd      s8, 48(sp)
    sd      s9, 40(sp)
    sd      s10,32(sp)
    sd      s11,24(sp)

    ####################################
    ## Open PAYLOAD, get size (s11)
    ####################################
    la      t0, PAYLOAD
    ld      a1, 0(t0)              # a1 = payload path
    li      a0, -100               # AT_FDCWD
    li      a2, 0                  # O_RDONLY
    li      a3, 0
    li      a7, 56                 # openat
    ecall
    blt     a0, x0, syscall_error
    mv      s10, a0                # s10 = payload fd

    # size = lseek(fd, 0, SEEK_END)
    mv      a0, s10
    li      a1, 0
    li      a2, 2                  # SEEK_END
    li      a7, 62                 # lseek
    ecall
    blt     a0, x0, syscall_error
    mv      s11, a0                # payload size

    # rewind
    mv      a0, s10
    li      a1, 0
    li      a2, 0                  # SEEK_SET
    li      a7, 62
    ecall

    ####################################
    ## Open INPUT BMP, read+check header
    ####################################
    la      t3, INPUT_FILE
    ld      a1, 0(t3)
    li      a0, -100
    li      a2, 0
    li      a3, 0
    li      a7, 56                 # openat
    ecall
    blt     a0, x0, syscall_error
    mv      s0, a0                 # s0 = input BMP fd

    # read 54 bytes (DIB+file header)
    mv      a0, s0
    la      a1, inbuf
    li      a2, 54
    li      a7, 63                 # read
    ecall
    blt     a0, x0, syscall_error
    mv      s4, a0                 # bytes_read
    li      t5, 54
    blt     s4, t5, short_read_error

    # 'BM' check
    la      t0, inbuf
    lbu     t1, 0(t0)
    lbu     t2, 1(t0)
    li      t3, 0x42
    li      t4, 0x4D
    bne     t1, t3, invalid_bmp_error
    bne     t2, t4, invalid_bmp_error

    # bfOffBits (10..13 LE) -> s1
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
    mv      s1, t1

    # width (18..21 LE) -> s2
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
    mv      s2, t1

    # height (22..25 LE) -> s3 (may be negative)
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
    mv      s3, t1

    # bpp (28..29 LE) -> s4
    lbu     t1, 28(t0)
    lbu     t2, 29(t0)
    sll     t2, t2, 8
    or      t1, t1, t2
    mv      s4, t1

    # capacity calc
    li      t1, 8
    divu    t0, s4, t1             # bytes_per_pixel
    mv      s5, t0

    mul     t2, s2, s5             # row bytes before align
    addi    t2, t2, 3
    li      t3, -4
    and     t2, t2, t3
    mv      s6, t2                 # row_bytes

    mv      t4, s3
    blt     t4, x0, 1f
    j       2f
1:  neg     t4, t4
2:  mv      s7, t4                 # abs(height)

    mul     t5, s6, s7
    mv      s8, t5                 # pixel_array_size

    srli    t6, s8, 3
    mv      s9, t6                 # capacity bytes (one bit per pixel byte)

    # payload <= capacity?
    bgtu    s11, s9, payload_too_large

    ####################################
    ## Open OUTPUT BMP
    ####################################
    la      t0, OUTPUT_FILE
    ld      a1, 0(t0)
    li      a0, -100
    li      a2, 577                # O_WRONLY|O_CREAT|O_TRUNC
    li      a3, 420                # 0644
    li      a7, 56                 # openat
    ecall
    blt     a0, x0, syscall_error
    mv      t5, a0                 # t5 = output BMP fd

    ####################################
    ## Rewind input and copy header up to bfOffBits
    ####################################
    mv      a0, s0
    li      a1, 0
    li      a2, 0                  # SEEK_SET
    li      a7, 62
    ecall

    mv      t1, s1                 # remaining header bytes
copy_hdr_loop:
    beqz    t1, hdr_copied
    li      t2, 512
    bltu    t1, t2, hdr_use_rem
    j       hdr_have_chunk
hdr_use_rem:
    mv      t2, t1
hdr_have_chunk:
    mv      a0, s0
    la      a1, inbuf
    mv      a2, t2
    li      a7, 63                 # read
    ecall
    blt     a0, x0, syscall_error
    beqz    a0, hdr_copied         # unexpected EOF
    mv      t3, a0                 # bytes_read
    mv      a0, t5
    la      a1, inbuf
    mv      a2, t3
    li      a7, 64                 # write
    ecall
    sub     t1, t1, t3
    j       copy_hdr_loop
hdr_copied:
    # Now both fds are positioned at pixel array start.

    ############################################################
    ## Build basename (in HEADER_NAMEBUF), compute name_len in a0
    ############################################################
    la      t0, PAYLOAD
    ld      t1, 0(t0)              # t1 = char* path
    mv      t2, t1                  # scan
    mv      t3, t1                  # last = start
find_slash:
    lbu     t4, 0(t2)
    beqz    t4, have_base
    li      t5, '/'
    bne     t4, t5, next_char
    addi    t3, t2, 1               # last = t2+1
next_char:
    addi    t2, t2, 1
    j       find_slash
have_base:
    la      t6, HEADER_NAMEBUF
    mv      a0, zero                # a0 = name_len
copy_name:
    lbu     t4, 0(t3)
    beqz    t4, name_done
    li      t5, HDR_MAX_NAME
    bgeu    a0, t5, name_done
    sb      t4, 0(t6)
    addi    t6, t6, 1
    addi    t3, t3, 1
    addi    a0, a0, 1
    j       copy_name
name_done:
    sb      zero, 0(t6)             # optional NUL
    sd      a0, 8(sp)               # SAVE name_len BEFORE any EMBED_BYTE uses

    ############################################################
    ## Emit header at pixel data (using macros)
    ############################################################
    # required_bytes = payload_size + 10 (magic+len+name_len) + name_len
    ld      t0, 8(sp)               # saved name_len
    li      t1, 10
    add     t1, t1, t0
    add     t1, t1, s11
    bgtu    t1, s9, payload_too_large

    li      t0, HDR_MAGIC0
    EMBED_BYTE t0
    li      t0, HDR_MAGIC1
    EMBED_BYTE t0
    li      t0, HDR_MAGIC2
    EMBED_BYTE t0
    li      t0, HDR_MAGIC3
    EMBED_BYTE t0

    mv      t1, s11                 # u32 payload_len (LE)
    andi    t0, t1, 0xFF
    EMBED_BYTE t0
    srli    t1, t1, 8
    andi    t0, t1, 0xFF
    EMBED_BYTE t0
    srli    t1, t1, 8
    andi    t0, t1, 0xFF
    EMBED_BYTE t0
    srli    t1, t1, 8
    andi    t0, t1, 0xFF
    EMBED_BYTE t0

    ld      t1, 8(sp)               # u16 name_len (LE) — reload from stack
    andi    t0, t1, 0xFF
    EMBED_BYTE t0
    srli    t1, t1, 8
    andi    t0, t1, 0xFF
    EMBED_BYTE t0

    la      t6, HEADER_NAMEBUF      # name bytes
    ld      a4, 8(sp)               # loop counter = saved name_len
emit_name_loop:
    beqz    a4, header_done
    lbu     t0, 0(t6)
    EMBED_BYTE t0
    addi    t6, t6, 1
    addi    a4, a4, -1
    j       emit_name_loop
header_done:

    ############################################################
    ## Embed payload bytes
    ############################################################
    mv      t4, s11                 # remaining payload bytes
embed_loop:
    beqz    t4, payload_done

    # read 1 byte from payload
    mv      a0, s10
    la      a1, inbuf
    li      a2, 1
    li      a7, 63                  # read
    ecall
    blt     a0, x0, syscall_error
    beqz    a0, payload_done        # unexpected EOF

    la      t6, inbuf
    lbu     t0, 0(t6)
    addi    t4, t4, -1

    EMBED_BYTE t0
    j       embed_loop

payload_done:
    ############################################################
    ## Copy rest of BMP bytes verbatim
    ############################################################
copy_rest:
    mv      a0, s0
    la      a1, inbuf
    li      a2, 512
    li      a7, 63                  # read
    ecall
    blt     a0, x0, syscall_error
    beqz    a0, copy_done
    mv      t2, a0
    mv      a0, t5
    la      a1, inbuf
    mv      a2, t2
    li      a7, 64                  # write
    ecall
    j       copy_rest
copy_done:

    # close fds
close_and_ok:
    mv      a0, s10                 # payload fd
    li      a7, 57                  # close
    ecall

    mv      a0, s0                  # input BMP
    li      a7, 57
    ecall

    mv      a0, t5                  # output BMP
    li      a7, 57
    ecall

    li      a0, 0                   # success
    j       epilogue

# -------------------- Error branches (insert) --------------------
syscall_error:
    neg     t6, a0                  # errno = -retval
    call    payload_error_errno
    li      a0, -1
    j       epilogue

short_read_error:
    la      t0, INPUT_FILE
    ld      a2, 0(t0)               # filename
    mv      a1, s4                  # bytes got
    la      a0, perr_shortread
    call    printf
    li      a0, 0
    call    fflush
    li      a0, -1
    j       epilogue

invalid_bmp_error:
    la      t0, INPUT_FILE
    ld      a3, 0(t0)
    mv      a1, t1
    mv      a2, t2
    la      a0, perr_notbmp
    call    printf
    li      a0, 0
    call    fflush
    li      a0, -1
    j       epilogue

payload_too_large:
    la      a0, perr_toolarge
    mv      a1, s11
    mv      a2, s9
    call    printf
    li      a0, 0
    call    fflush
    li      a0, -1
    j       epilogue

# Common epilogue (insert)
epilogue:
    ld      s11,24(sp)
    ld      s10,32(sp)
    ld      s9, 40(sp)
    ld      s8, 48(sp)
    ld      s7, 56(sp)
    ld      s6, 64(sp)
    ld      s5, 72(sp)
    ld      s4, 80(sp)
    ld      s3, 88(sp)
    ld      s2, 96(sp)
    ld      s1,104(sp)
    ld      s0,112(sp)
    ld      ra,120(sp)
    addi    sp, sp, 128
    ret

# ----------------------------------------------------------------------
# payload_extract: read header at pixel data, then extract exactly s11
#   Uses: s0..s9,s11 ; t5 = output payload fd
# ----------------------------------------------------------------------
payload_extract:
    # Prologue
    addi    sp, sp, -128
    sd      ra, 120(sp)
    sd      s0, 112(sp)
    sd      s1, 104(sp)
    sd      s2, 96(sp)
    sd      s3, 88(sp)
    sd      s4, 80(sp)
    sd      s5, 72(sp)
    sd      s6, 64(sp)
    sd      s7, 56(sp)
    sd      s8, 48(sp)
    sd      s9, 40(sp)
    sd      s11,32(sp)

    ####################################
    ## OPEN + VALIDATE INPUT BMP
    ####################################
    la      t3, INPUT_FILE
    ld      a1, 0(t3)
    li      a0, -100
    li      a2, 0
    li      a3, 0
    li      a7, 56                 # openat
    ecall
    blt     a0, x0, syscall_error_x
    mv      s0, a0

    # read 54 bytes
    mv      a0, s0
    la      a1, inbuf
    li      a2, 54
    li      a7, 63                 # read
    ecall
    blt     a0, x0, syscall_error_x
    mv      s1, a0
    li      t5, 54
    blt     s1, t5, short_read_error_x

    # 'BM'
    la      t0, inbuf
    lbu     t1, 0(t0)
    lbu     t2, 1(t0)
    li      t3, 0x42
    li      t4, 0x4D
    bne     t1, t3, invalid_bmp_error_x
    bne     t2, t4, invalid_bmp_error_x

    # bfOffBits -> s1
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
    mv      s1, t1

    # width -> s2
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
    mv      s2, t1

    # height -> s3
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
    mv      s3, t1

    # bpp -> s4
    lbu     t1, 28(t0)
    lbu     t2, 29(t0)
    sll     t2, t2, 8
    or      t1, t1, t2
    mv      s4, t1

    # capacity
    li      t1, 8
    divu    t0, s4, t1
    mv      s5, t0

    mul     t2, s2, s5
    addi    t2, t2, 3
    li      t3, -4
    and     t2, t2, t3
    mv      s6, t2

    mv      t4, s3
    blt     t4, x0, 1f
    j       2f
1:  neg     t4, t4
2:  mv      s7, t4

    mul     t5, s6, s7
    mv      s8, t5

    srli    t6, s8, 3
    mv      s9, t6

    ####################################
    ## SEEK TO PIXELS, THEN READ HEADER
    ####################################
    mv      a0, s0
    mv      a1, s1                 # bfOffBits
    li      a2, 0                  # SEEK_SET
    li      a7, 62                 # lseek
    ecall
    blt     a0, x0, syscall_error_x

    # --- magic
    NEXT_EMBEDDED_BYTE t1
    NEXT_EMBEDDED_BYTE t2
    NEXT_EMBEDDED_BYTE t3
    NEXT_EMBEDDED_BYTE t4
    li      t5, HDR_MAGIC0
    bne     t1, t5, bad_header
    li      t5, HDR_MAGIC1
    bne     t2, t5, bad_header
    li      t5, HDR_MAGIC2
    bne     t3, t5, bad_header
    li      t5, HDR_MAGIC3
    bne     t4, t5, bad_header

    # --- payload_len u32 LE -> s11
    NEXT_EMBEDDED_BYTE t0          # b0
    mv      s11, t0
    NEXT_EMBEDDED_BYTE t0          # b1
    slli    t0, t0, 8
    or      s11, s11, t0
    NEXT_EMBEDDED_BYTE t0          # b2
    slli    t0, t0, 16
    or      s11, s11, t0
    NEXT_EMBEDDED_BYTE t0          # b3
    slli    t0, t0, 24
    or      s11, s11, t0

    # sanity vs capacity
    bgtu    s11, s9, _req_too_large

    # --- name_len u16 LE -> a0
    NEXT_EMBEDDED_BYTE t0
    mv      a0, t0
    NEXT_EMBEDDED_BYTE t0
    slli    t0, t0, 8
    or      a0, a0, t0
    li      t5, HDR_MAX_NAME
    bleu    a0, t5, 3f
    li      a0, HDR_MAX_NAME
3:
    # --- read name bytes into HEADER_NAMEBUF
    la      t6, HEADER_NAMEBUF
    mv      a4, a0
read_name_loop:
    beqz    a4, name_done_x
    NEXT_EMBEDDED_BYTE t0
    sb      t0, 0(t6)
    addi    t6, t6, 1
    addi    a4, a4, -1
    j       read_name_loop
name_done_x:
    sb      zero, 0(t6)

    # Always use the embedded basename for output
    la      t0, PAYLOAD
    la      t3, HEADER_NAMEBUF
    sd      t3, 0(t0)

have_output_name:

    ####################################
    ## OPEN OUTPUT PAYLOAD (write/trunc)
    ####################################
    la      t0, PAYLOAD
    ld      a1, 0(t0)
    li      a0, -100
    li      a2, 577                # O_WRONLY|O_CREAT|O_TRUNC
    li      a3, 420                # 0644
    li      a7, 56                 # openat
    ecall
    blt     a0, x0, syscall_error_x
    mv      t5, a0                 # t5 = payload out fd

    ####################################
    ## EXTRACT LOOP (exactly s11 bytes)
    ####################################
    mv      t4, s11
_byte_loop:
    beqz    t4, _extract_done
    NEXT_EMBEDDED_BYTE t3          # assembled byte in t3
    # write it
    mv      a0, t5
    la      a1, inbuf
    sb      t3, 0(a1)
    li      a2, 1
    li      a7, 64                 # write
    ecall
    blt     a0, x0, syscall_error_x
    addi    t4, t4, -1
    j       _byte_loop

_extract_done:
    # close fds
    mv      a0, t5
    li      a7, 57                 # close
    ecall
    mv      a0, s0
    li      a7, 57
    ecall
    li      a0, 0
    j       epilogue_x

# -------------------- Error branches (extract) --------------------
bad_header:
    la      a0, err_bad_header
    call    printf
    li      a0, 0
    call    fflush
    li      a0, -1
    j       epilogue_x

_req_too_large:
    la      a0, perr_reqtoolarge
    mv      a1, s11
    mv      a2, s9
    call    printf
    li      a0, 0
    call    fflush
    li      a0, -1
    j       epilogue_x

syscall_error_x:
    neg     t6, a0
    call    payload_error_errno
    li      a0, -1
    j       epilogue_x

short_read_error_x:
    la      t0, INPUT_FILE
    ld      a2, 0(t0)
    mv      a1, s1
    la      a0, perr_shortread
    call    printf
    li      a0, 0
    call    fflush
    li      a0, -1
    j       epilogue_x

invalid_bmp_error_x:
    la      t0, INPUT_FILE
    ld      a3, 0(t0)
    mv      a1, t1
    mv      a2, t2
    la      a0, perr_notbmp
    call    printf
    li      a0, 0
    call    fflush
    li      a0, -1
    j       epilogue_x

_unexpected_eof_x:
    la      a0, perr_unexpected_eof
    call    printf
    li      a0, 0
    call    fflush
    li      a0, -1
    j       epilogue_x


	
# Common epilogue (extract)
epilogue_x:
    ld      s11,32(sp)
    ld      s9, 40(sp)
    ld      s8, 48(sp)
    ld      s7, 56(sp)
    ld      s6, 64(sp)
    ld      s5, 72(sp)
    ld      s4, 80(sp)
    ld      s3, 88(sp)
    ld      s2, 96(sp)
    ld      s1,104(sp)
    ld      s0,112(sp)
    ld      ra,120(sp)
    addi    sp, sp, 128
    ret

# ----------------------------------------------------------------------
# Error printers (shared)
# ----------------------------------------------------------------------
payload_error_errno:
    addi    sp, sp, -16
    sd      ra, 8(sp)
    sd      s0, 0(sp)

    mv      a0, t6
    blez    a0, 1f
    call    strerror               # a0 = char* errstr
    mv      a1, a0
    j       2f
1:
    la      a1, unknown_err
2:
    la      t0, INPUT_FILE
    ld      a2, 0(t0)              # filename
    la      a0, perr_errno         # "Error (%s) opening %s\n"
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
perr_errno:            .asciz "Error (%s) opening %s\n"
perr_shortread:        .asciz "Error: short read (%ld bytes) from %s\n"
perr_notbmp:           .asciz "Error: not a BMP (got 0x%02X 0x%02X) in %s\n"
msg_bmpok:             .asciz "Valid BMP input file\n"
unknown_err:           .asciz "Unknown error"
dbg_fmt:               .asciz "W=%d, H=%d, BPP=%d, CAP=%d\n"
dbg_payload:           .asciz "Payload size = %ld bytes\n"
perr_toolarge:         .asciz "Error: payload too large (%ld > %ld)\n"
perr_reqtoolarge:      .asciz "Error: requested extract length %ld exceeds capacity %ld\n"
perr_unexpected_eof:   .asciz "Error: unexpected EOF in BMP pixel data during extraction\n"
err_bad_header:        .asciz "Error: missing SNKY header in image\n"

.data
.align 8
inbuf:                 .space BUFSIZE
