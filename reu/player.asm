; Portrait animation player: disk -> REU -> screen (ACME).
;
; 1. Checks for a REU of at least 512 KB.
; 2. Loads frame files F001..F100 from the boot drive into a buffer and stashes each
;    into its own 4 KB REU slot (frame n at REU address n*$1000).
; 3. Plays the frames in a loop at 10 fps (PAL and NTSC detected), fetching each one
;    from the REU straight into the bitmap during the vertical blank.
;
; Frame file layout (built by build_player.sh): 25 cell rows, each 120 bitmap bytes
; followed by that row's 15 screen-RAM bytes (3375 bytes). Row-interleaving lets one
; continuous REU read fill bitmap and colors row by row, staying ahead of the raster.

!cpu 6510

COL        = 12             ; left column of the 15-column strip
BITMAP     = $2000
SCREEN     = $0400
BUFFER     = $4000          ; load buffer for one frame file
FRAMES     = 100
ROWS       = 25
ROW_BITMAP = 120
ROW_SCREEN = 15
FRAME_SIZE = ROWS * (ROW_BITMAP + ROW_SCREEN)

REU_CMD    = $df01
REU_C64    = $df02          ; 2 bytes
REU_ADDR   = $df04          ; 2 bytes
REU_BANK   = $df06
REU_LEN    = $df07          ; 2 bytes
REU_CTRL   = $df0a
STASH      = $90            ; execute now, C64 -> REU
FETCH      = $91            ; execute now, REU -> C64

SETLFS     = $ffba
SETNAM     = $ffbd
LOAD       = $ffd5
CHROUT     = $ffd2

frame      = $02
framewait  = $03
ptr        = $fb            ; 2 bytes

* = $0801
!byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00   ; 10 SYS2061

start:
        lda #0
        sta $d020
        sta $d021
        lda #1
        sta $0286           ; white text
        lda #<msg_title
        ldy #>msg_title
        jsr print

        jsr check_reu
        bcc +
        lda #<msg_noreu
        ldy #>msg_noreu
        jmp print
+
        ; ---- load every frame file and stash it in the REU ----
        lda #0
        sta frame
load_loop:
        lda #1
        ldx $ba             ; device we were loaded from
        bne +
        ldx #8
+       ldy #0              ; secondary address 0: load to X/Y, not the file's address
        jsr SETLFS
        lda #name_end - name
        ldx #<name
        ldy #>name
        jsr SETNAM
        lda #0
        ldx #<BUFFER
        ldy #>BUFFER
        jsr LOAD
        bcs load_error

        lda #<BUFFER
        sta REU_C64
        lda #>BUFFER
        sta REU_C64+1
        lda frame
        jsr set_reu_slot
        lda #<FRAME_SIZE
        sta REU_LEN
        lda #>FRAME_SIZE
        sta REU_LEN+1
        lda #STASH
        sta REU_CMD

        lda #'.'
        jsr CHROUT
        jsr next_name
        inc frame
        lda frame
        cmp #FRAMES
        bne load_loop
        jmp play

load_error:
        lda #<msg_loaderr
        ldy #>msg_loaderr
        jsr print
        lda #<name
        ldy #>name
        jmp print

        ; ---- playback ----
play:
        sei
        jsr detect_video

        lda #0              ; clear bitmap and screen RAM
        sta ptr
        tay
        ldx #>BITMAP
        stx ptr+1
        ldx #$20
-       sta (ptr),y
        iny
        bne -
        inc ptr+1
        dex
        bne -
-       sta SCREEN,y
        sta SCREEN+$100,y
        sta SCREEN+$200,y
        sta SCREEN+$300,y
        iny
        bne -

        lda #$3b            ; bitmap mode, 25 rows, screen on
        sta $d011
        lda #$08            ; hires, 40 columns
        sta $d016
        lda #$18            ; screen $0400, bitmap $2000
        sta $d018

        lda #0
        sta frame
play_loop:
        ldx framewait
-       lda $d012           ; wait for raster line 251 (below the picture)
        cmp #$fb
        bne -
--      lda $d012
        cmp #$fb
        beq --
        dex
        bne -

        lda frame
        jsr set_reu_slot    ; REU address auto-advances after each fetch
        lda #0
        sta REU_LEN+1
        ldx #0
row_loop:
        lda bitmap_lo,x
        sta REU_C64
        lda bitmap_hi,x
        sta REU_C64+1
        lda #ROW_BITMAP
        sta REU_LEN
        lda #FETCH
        sta REU_CMD
        lda screen_lo,x
        sta REU_C64
        lda screen_hi,x
        sta REU_C64+1
        lda #ROW_SCREEN
        sta REU_LEN
        lda #FETCH
        sta REU_CMD
        inx
        cpx #ROWS
        bne row_loop

        inc frame
        lda frame
        cmp #FRAMES
        bne +
        lda #0
        sta frame
+       jmp play_loop

; ---- subroutines ----

; A = frame number -> REU address frame * $1000
set_reu_slot:
        pha
        asl
        asl
        asl
        asl
        sta REU_ADDR+1
        lda #0
        sta REU_ADDR
        pla
        lsr
        lsr
        lsr
        lsr
        sta REU_BANK
        rts

; Carry clear if a REU of 512 KB or more is present.
check_reu:
        lda #$5a
        sta REU_C64
        lda #$a5
        sta REU_C64+1
        lda REU_C64
        cmp #$5a
        bne no_reu
        lda REU_C64+1
        cmp #$a5
        bne no_reu
        lda #0
        sta REU_CTRL
        lda #1              ; 1 -> bank 0, 2 -> bank 4; a smaller REU wraps bank 4 onto bank 0
        sta tmp
        ldx #0
        lda #STASH
        jsr reu_byte
        lda #2
        sta tmp
        ldx #4
        lda #STASH
        jsr reu_byte
        ldx #0
        lda #FETCH
        jsr reu_byte
        lda tmp
        cmp #1
        bne no_reu
        clc
        rts
no_reu:
        sec
        rts

; Transfer the byte at tmp to/from REU bank X, address 0. A = command.
reu_byte:
        stx REU_BANK
        ldx #0
        stx REU_ADDR
        stx REU_ADDR+1
        stx REU_LEN+1
        inx
        stx REU_LEN
        ldx #<tmp
        stx REU_C64
        ldx #>tmp
        stx REU_C64+1
        sta REU_CMD
        rts

; framewait = 5 on PAL (50 Hz), 6 on NTSC (60 Hz). Needs interrupts off.
detect_video:
-       lda $d012
--      cmp $d012
        beq --
        bmi -               ; loop until the raster wraps; A = last line's low byte
        cmp #$20            ; PAL ends at $37 (line 311), NTSC at $05/$06
        lda #5
        bcs +
        lda #6
+       sta framewait
        rts

; Advance the 3-digit number in name.
next_name:
        ldx #name_end - name - 1
-       inc name,x
        lda name,x
        cmp #'9' + 1
        bne +
        lda #'0'
        sta name,x
        dex
        bne -
+       rts

; Print zero-terminated string at A/Y.
print:
        sta ptr
        sty ptr+1
        ldy #0
-       lda (ptr),y
        beq +
        jsr CHROUT
        iny
        bne -
+       rts

name:        !text "F001"
name_end:    !byte 0        ; terminator so the name can be printed in the load error
tmp:         !byte 0

msg_title:   !pet 147, "loading 100 frames into reu", 13, 0
msg_noreu:   !pet "this needs a reu of 512 kb or more.", 13, 0
msg_loaderr: !pet 13, "load error: ", 0

bitmap_lo:   !for r, 0, ROWS - 1 { !byte <(BITMAP + r * 320 + COL * 8) }
bitmap_hi:   !for r, 0, ROWS - 1 { !byte >(BITMAP + r * 320 + COL * 8) }
screen_lo:   !for r, 0, ROWS - 1 { !byte <(SCREEN + r * 40 + COL) }
screen_hi:   !for r, 0, ROWS - 1 { !byte >(SCREEN + r * 40 + COL) }

!if * > BITMAP { !error "player code overlaps the bitmap" }
