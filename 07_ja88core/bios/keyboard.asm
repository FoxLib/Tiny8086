; ----------------------------------------------------------------------
; Обработка прерывания IRQ#1
; ----------------------------------------------------------------------

int9:       push    ax bx cx dx ds
            in      al, $60

            ; BDA
            mov     ds, [cs:SEG_40h]
            mov     bx, keyflags1-bios_data

            ; SHIFT LEFT
            cmp     al, $2A+$80
            jne     @f
            and     [bx], byte 11111101b
@@:         cmp     al, $2A
            jne     @f
            or      [bx], byte 00000010b
            ; SHIFT RIGHT
@@:         cmp     al, $36+$80
            jne     @f
            and     [bx], byte 11111110b
@@:         cmp     al, $36
            jne     @f
            or      [bx], byte 00000001b
            ; CTRL
@@:         cmp     al, $1D+$80
            jne     @f
            and     [bx], byte 11111011b
@@:         cmp     al, $1D
            jne     @f
            or      [bx], byte 00000100b
@@:         ; ALT
            cmp     al, $38+$80
            jne     @f
            and     [bx], byte 11110111b
@@:         cmp     al, $38
            jne     @f
            or      [bx], byte 00001000b
@@:         ; Не пропускать отжатые клавиши в клавиатурный буфер
            test    al, $80
            jne     .skip_add_key


.skip_add_key:

            mov     al, $20
            out     $20, al
            pop     ds dx cx bx ax
            iret

; ----------------------------------------------------------------------
; Сервис клавиатуры
; https://www.frolov-lib.ru/books/bsp/v02/ch2_4.htm
; ----------------------------------------------------------------------

int16:
            iret
