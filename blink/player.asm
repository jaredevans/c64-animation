; Full-screen hires animation player (ACME). Runs on a stock C64 - no REU or disk access.
;
; Shows the first frame (bitmap loaded straight to $2000, screen RAM copied to $0400),
; then applies one frame of the delta stream every 1/10 s (PAL and NTSC detected).
; Delta records (built by convert_blink.py), one per changed cell:
;   bitmap addr hi, bitmap addr lo, screen addr hi, screen addr lo, 8 bitmap bytes, 1 screen byte
; A 0 byte ends a frame; $FF ends the stream, which wraps back to the start. The last frame's
; deltas lead back to frame 1, so the loop is seamless.

!cpu 6510

BITMAP    = $2000
SCREEN    = $0400
DELTAS    = $4000

framewait = $02
ptr       = $fb         ; 2 bytes: position in the delta stream
dst       = $fd         ; 2 bytes: bitmap address of the cell
col       = $f7         ; 2 bytes: screen address of the cell

* = $0801
!byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$31,$00,$00,$00   ; 10 SYS2061

start:
        sei
        lda #$36            ; BASIC ROM off so deltas above $a000 are readable
        sta $01
        jsr detect_video

        ldx #0              ; first frame's colors into screen RAM
-       lda first_screen,x
        sta SCREEN,x
        lda first_screen+$100,x
        sta SCREEN+$100,x
        lda first_screen+$200,x
        sta SCREEN+$200,x
        lda first_screen+$2e8,x
        sta SCREEN+$2e8,x
        inx
        bne -

        lda #0
        sta $d020
        lda #$3b            ; bitmap mode, 25 rows, screen on
        sta $d011
        lda #$08            ; hires, 40 columns
        sta $d016
        lda #$18            ; screen $0400, bitmap $2000
        sta $d018

        lda #<DELTAS
        sta ptr
        lda #>DELTAS
        sta ptr+1

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

        ldy #0
        lda (ptr),y
        cmp #$ff
        bne cell
        lda #<DELTAS        ; end of stream: back to the start
        sta ptr
        lda #>DELTAS
        sta ptr+1

cell:
        ldy #0
        lda (ptr),y
        beq frame_done
        sta dst+1
        iny
        lda (ptr),y
        sta dst
        iny
        lda (ptr),y
        sta col+1
        iny
        lda (ptr),y
        sta col
        lda ptr             ; skip the 4 address bytes
        clc
        adc #4
        sta ptr
        bcc +
        inc ptr+1
+       ldy #7
-       lda (ptr),y
        sta (dst),y
        dey
        bpl -
        ldy #8
        lda (ptr),y
        ldy #0
        sta (col),y
        lda ptr             ; skip the 9 data bytes
        clc
        adc #9
        sta ptr
        bcc cell
        inc ptr+1
        jmp cell

frame_done:
        inc ptr
        bne +
        inc ptr+1
+       jmp play_loop

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

first_screen:
        !binary "data/screen.bin"

!if * > BITMAP { !error "code and screen data overlap the bitmap" }
* = BITMAP
        !binary "data/bitmap.bin"

* = DELTAS
        !binary "data/deltas.bin"
!if * > $d000 { !error "delta stream too long: runs into I/O at $d000" }
